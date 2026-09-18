# Deployment patterns

The bundled stack runs everything: a reverse proxy, DELTA, and PostgreSQL.
Either of the two supporting services can be removed when you already have that
piece.

| | Pattern | Edits needed |
|---|---|---|
| **A** | `client -> nginx -> delta -> db` | None |
| **B** | `client -> nginx -> delta -> your database` | [Remove `db`](#b-external-database) |
| **C** | `client -> your gateway -> delta -> db` | [Remove `nginx`](#c-existing-proxy-load-balancer-or-waf) |
| **D** | `client -> your gateway -> delta -> your database` | [Both](#d-existing-gateway-and-external-database) |

**This page only describes the edits.** The deployment procedure itself is the
same for all four and lives in the
[installation guide](index.md#install-delta). Make these edits **before**
starting it, then work through it.

> **None of these patterns needs a database dump to deploy.** DELTA builds its
> own schema and seed data the first time the container starts, against an empty
> database that meets the requirements below. Importing a dump is for migrating
> existing data or recovering a deployment, not for installation. This does not
> mean DELTA will initialise against a database that is missing its required
> extensions or privileges - read the requirements for patterns B and D.

---

## A - Standalone

The supplied files, unchanged. Continue with the
[installation guide](index.md#install-delta).

---

## B - External database

Use this when your organisation runs PostgreSQL for you - a managed service, or
a database team's cluster.

### What the external database must provide

| Requirement | Detail |
|---|---|
| **PostgreSQL 17** | The bundled stack uses 17. Older majors are not tested here. The major version cannot be changed later without a dump and restore. |
| **PostGIS** | Required. DELTA's schema runs `CREATE EXTENSION IF NOT EXISTS postgis`. |
| **pgcrypto** | Required. Used by the schema and by the administrator password reset. |
| **A database and a role** | DELTA needs to own its schema in that database: create tables, indexes, functions. |
| **Network reachability** | The DELTA container must be able to reach the host and port. |
| **TLS** | Use `?sslmode=require` in the connection URL for anything not on a private network. |

> **Have your DBA create the extensions before DELTA first starts.** `postgis`
> is not a *trusted* extension, so creating it needs superuser rights, which
> DELTA's own role should not have. Once a superuser has run
> `CREATE EXTENSION postgis;` and `CREATE EXTENSION pgcrypto;` in the target
> database, DELTA's `IF NOT EXISTS` statements find them and do nothing. Without
> this, the very first start fails on a permissions error.

### Edits to `docker-compose.yml`

**1.** Delete the whole `db:` service block - from `db:` down to its
`logging: *logging` line.

**2.** In the `delta:` service, delete its dependency on it:

```yaml
    depends_on:
      db:
        condition: service_healthy
```

**3.** Still in the `delta:` service, point the connection string at `.env`
instead of building it from the deleted database. Replace this line:

```yaml
      DATABASE_URL: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:5432/${POSTGRES_DB}
```

with:

```yaml
      DATABASE_URL: ${DATABASE_URL}
```

**4.** At the bottom of the file, delete the now-unused volume:

```yaml
volumes:
  pgdata:        # <- delete this line
  uploads:
  logs:
```

### Edits to `.env`

Uncomment `DATABASE_URL` and set the full connection string. The `POSTGRES_*`
settings are then unused and can be left as they are.

```
DATABASE_URL=postgresql://delta:PASSWORD@db.example.org:5432/delta?sslmode=require
```

Percent-encode any character in the username or password that is not a letter,
digit, `-`, `.`, `_` or `~`. See
[Configuration](configuration.md#connection-strings-and-special-characters).

> Both edits are required. Setting `DATABASE_URL` in `.env` alone is not enough:
> without edit 3, `docker-compose.yml` still overrides it with a string pointing
> at a `db` service that no longer exists. `docker compose config` below is what
> catches that.

### Confirm before starting

```
docker compose config
```

Check the `DATABASE_URL` under the `delta` service is exactly your external URL,
not one pointing at `db:5432`.

### Replacing the administrator password on an external database

Your deployment guide's administrator step uses the bundled `db` container,
which you do not have. Run `psql` inside the DELTA container instead — it
already holds the connection string. Everything else about the step is
unchanged, including when it happens: **before any route to this deployment is
enabled.**

Read the password into your environment first, exactly as your platform guide
describes, then run these two commands.

=== "Bash/zsh"

    Set:

    ```bash
    docker compose exec -T -e DELTA_ADMIN_NEW_PASSWORD delta \
      sh -c 'set -f; psql $DATABASE_URL --set ON_ERROR_STOP=on --tuples-only --no-align -f -' <<'SQL'
    \getenv password DELTA_ADMIN_NEW_PASSWORD
    UPDATE public.super_admin_users
       SET password = crypt(:'password', gen_salt('bf', 10))
     WHERE email = 'admin@admin.com' RETURNING email;
    SQL
    ```

    Verify:

    ```bash
    docker compose exec -T -e DELTA_ADMIN_NEW_PASSWORD delta \
      sh -c 'set -f; psql $DATABASE_URL --set ON_ERROR_STOP=on --tuples-only --no-align -f -' <<'SQL'
    \getenv password DELTA_ADMIN_NEW_PASSWORD
    SELECT email, (password = crypt(:'password', password)) AS verifies
      FROM public.super_admin_users WHERE email = 'admin@admin.com';
    SQL
    ```

=== "PowerShell"

    Set:

    ```powershell
    @'
    \getenv password DELTA_ADMIN_NEW_PASSWORD
    UPDATE public.super_admin_users
       SET password = crypt(:'password', gen_salt('bf', 10))
     WHERE email = 'admin@admin.com' RETURNING email;
    '@ | docker compose exec -T -e DELTA_ADMIN_NEW_PASSWORD delta sh -c 'set -f; psql $DATABASE_URL --set ON_ERROR_STOP=on --tuples-only --no-align -f -'
    ```

    Verify:

    ```powershell
    @'
    \getenv password DELTA_ADMIN_NEW_PASSWORD
    SELECT email, (password = crypt(:'password', password)) AS verifies
      FROM public.super_admin_users WHERE email = 'admin@admin.com';
    '@ | docker compose exec -T -e DELTA_ADMIN_NEW_PASSWORD delta sh -c 'set -f; psql $DATABASE_URL --set ON_ERROR_STOP=on --tuples-only --no-align -f -'
    ```

**Expected:** the set command succeeds and prints `admin@admin.com`; a status
line such as `UPDATE 1` may also appear and is normal. The verify command
prints `admin@admin.com|t`. If it does not print `t`, the password was not
replaced — do not enable any route to the deployment.

Then clear the variable: `Remove-Item Env:\DELTA_ADMIN_NEW_PASSWORD` in
PowerShell, `unset DELTA_ADMIN_NEW_PASSWORD` elsewhere.

`set -f` stops the container's shell treating characters such as `?` in the
connection URL as filename patterns.

### Backups

**The bundled backup procedure does not apply to you.** Your database is backed
up by whoever operates it, under their procedures and their retention policy.
Confirm that this database is actually included before you go live.

You still need to back up the **uploads** volume yourself - see
[Backup and Restore](backup-restore.md#taking-a-backup). A database backup on
its own is not a recoverable deployment.

---

## C - Existing proxy, load balancer or WAF

Use this when you already terminate TLS and route traffic - an nginx you
operate, HAProxy, a cloud load balancer, an API gateway, a WAF.

### Edits to `docker-compose.yml`

**1.** Delete the whole `nginx:` service block.

**2.** In the `delta:` service, publish it so your gateway can reach it. Add a
`ports:` entry - read the next section before choosing the address:

```yaml
    ports:
      - "127.0.0.1:8080:3000"
```

**3.** The `nginx/` directory and its mount are no longer used. Nothing else
references them, so you can leave the directory in place or delete it.

### Choosing the published address - this is a security decision

The port you publish is DELTA with no proxy in front of it. Bind it to the
narrowest address that still lets your gateway reach it.

| Your gateway runs... | Publish as | Why |
|---|---|---|
| On this same host | `"127.0.0.1:8080:3000"` | Reachable only from this machine. The safe default. |
| On another machine, private network | `"10.0.0.5:8080:3000"` (this host's private address) | Reachable on that interface only, never on a public one. |
| Anywhere | **not** `"8080:3000"` | A bare port binds to every interface, including public ones. |

> **On Linux, publishing a port can bypass your host firewall.** Docker inserts
> its own rules, so a port published on all interfaces may be reachable from the
> internet even though `ufw` or `firewalld` appears to deny it. Binding to a
> specific address, as above, is the control that actually works. Do not rely on
> the host firewall alone.

### Bootstrap - do not skip this

!!! danger "Removing the bundled nginx does not make the deployment private"

    Your gateway is the thing that exposes it, and it is outside this
    repository's control. During the deployment procedure you must **not**
    enable the route on your gateway until step 7.

    Steps 5 and 6 of the [installation guide](index.md#install-delta) start
    DELTA, verify the database, and change the publicly-known administrator
    password. Publishing on `127.0.0.1` or a private address is what keeps that
    window closed. Enable the public route afterwards.

### What your gateway must do

DELTA reads forwarded headers directly, rather than relying on a framework
setting, so these are requirements and not tuning.

| Requirement | Value |
|---|---|
| Forward to | DELTA's published address, for example `http://127.0.0.1:8080` |
| `Host` | The original host |
| `X-Real-IP` | The client address |
| `X-Forwarded-For` | The client address, appended |
| `X-Forwarded-Proto` | `https` when the client used HTTPS. **Required for sign-in to work.** |
| `X-Forwarded-Host` | The original host |
| `X-Forwarded-Port` | The original port |
| `Origin` | Normalised to the scheme of the hop your gateway makes - see [When TLS is terminated in front](#when-tls-is-terminated-in-front). |
| Maximum request body | **At least 64 MB.** DELTA accepts uploads up to 50 MB; a lower limit gives users an HTTP 413 before DELTA sees the request. |
| Read timeout | **At least 300 seconds.** Uploads and report generation outlive a 60-second default. |
| Backend protocol | HTTP/1.1, keep-alive enabled |
| TLS | Terminated at your gateway. `PUBLIC_URL` must be the `https://` address clients use. |

> If users can sign in but are signed out again on the next page, the cause is
> almost always a missing or wrong `X-Forwarded-Proto`. DELTA's session cookies
> are marked `Secure`, and without that header it does not know the client is on
> HTTPS. See [Troubleshooting](troubleshooting.md#https-and-sessions).

The bundled `nginx/delta.conf` is a working reference for all of the above if
you want to compare against your own configuration.

### When TLS is terminated in front

Applies whenever a gateway, load balancer or WAF terminates HTTPS and forwards
to DELTA over plain HTTP. The symptom, if this is not handled, is distinctive:
**the site loads normally but every form submission returns HTTP 403.**

DELTA's CSRF protection compares the browser's `Origin` header against the
origin of the request it actually received:

| | |
|---|---|
| Browser sends | `Origin: https://delta.example.org` |
| DELTA receives | a plain HTTP request, so it computes `http://delta.example.org` |
| Result | same site, different scheme - rejected |

`X-Forwarded-Proto` does not fix this. DELTA uses it for session cookies; the
CSRF comparison is made against the request's own origin. The fix is to
normalise the `Origin` header on the last hop.

**If you kept the bundled nginx** (your gateway forwards to it), swap the
configuration file. In `docker-compose.yml`, replace the nginx volume entry:

```yaml
- ./nginx/delta-behind-tls-proxy.conf.example:/etc/nginx/conf.d/delta.conf:ro
```

That is the whole change. The default `nginx/delta.conf` deliberately does
**not** do this: it assumes nothing in front of it and trusts no incoming
`X-Forwarded-*` header.

**If your gateway connects directly to DELTA** (patterns C and D, no bundled
nginx), your gateway must implement the equivalent behaviour itself - the
forwarded headers above, plus the same `Origin` normalisation. Nothing in this
repository can do it for you.

The normalisation, in the form the alternate file uses:

```nginx
set $delta_origin $http_origin;

if ($http_origin = "https://$http_host") {
    set $delta_origin "http://$http_host";
}

proxy_set_header Host   $http_host;
proxy_set_header Origin $delta_origin;
```

Three requirements come with it, and none is optional:

!!! danger "The comparison must stay a whole-string equality test"

    A regex, prefix, suffix or wildcard match turns a scheme correction into an
    origin bypass, and `https://delta.example.org.attacker.example` starts being
    accepted. Only the scheme is ever rewritten, never the host. A foreign
    origin must reach DELTA untouched so DELTA still rejects it, and a request
    with no `Origin` must arrive with none.

- **Only your gateway may reach that endpoint.** The alternate configuration
  trusts the `X-Forwarded-*` headers it receives. Publish it on a private
  address, as above.
- **Your gateway must preserve the original `Host`.** The check compares against
  it and DELTA derives its own origin from it. A gateway that substitutes an
  internal name while advertising the public one in `X-Forwarded-Host` will keep
  failing.

---

## D - Existing gateway and external database

Both sets of edits. Compose ends up containing the `delta` service alone, plus
the `uploads` and `logs` volumes.

1. Apply the [B edits](#b-external-database): delete `db`, its `depends_on`
   and the `pgdata` volume; change the `DATABASE_URL` line to `${DATABASE_URL}`;
   set the connection string in `.env`.
2. Apply the [C edits](#c-existing-proxy-load-balancer-or-waf): delete
   `nginx`, publish `delta` on a narrow address.
3. Observe **both** bootstrap rules: the external database must have `postgis`
   and `pgcrypto` created by a superuser first, and your gateway's route stays
   disabled until the administrator password has been changed and verified.

Your resulting file should be roughly:

```yaml
name: ${COMPOSE_PROJECT_NAME:-delta}

x-logging: &logging
  driver: json-file
  options:
    max-size: "20m"
    max-file: "5"

services:
  delta:
    image: ${DELTA_IMAGE}
    restart: unless-stopped
    env_file:
      - .env
    environment:
      DATABASE_URL: ${DATABASE_URL}
      NODE_ENV: production
      LOG_DIR: /delta/logs
    ports:
      - "127.0.0.1:8080:3000"
    volumes:
      - uploads:/delta/uploads
      - logs:/delta/logs
    healthcheck:
      test: ["CMD", "node", "-e", "fetch('http://127.0.0.1:3000/').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]
      interval: 15s
      timeout: 10s
      retries: 10
      start_period: 180s
    logging: *logging

volumes:
  uploads:
  logs:
```

`DATABASE_URL` now comes entirely from `.env`. Confirm it with
`docker compose config` before starting anything.

> If this host runs more than one DELTA deployment, give each one a distinct
> `COMPOSE_PROJECT_NAME` in its `.env`, and a distinct published port. Two
> deployments left on the default project name share containers and volumes -
> [Configuration](configuration.md#project-identity-and-why-it-matters).

**Recovery in this pattern spans two owners.** Your database team restores the
database; you restore the uploads volume. Neither alone brings the deployment
back, and the two need to be from the same point in time - see
[Backup and Restore](backup-restore.md#consistency-between-database-and-uploads).
