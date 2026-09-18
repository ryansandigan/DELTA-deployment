# Configuration reference

Everything DELTA reads, what it does, and what happens if you get it wrong.

For the installation procedure itself, see the
[installation guide](index.md#install-delta).

---

## The three files

| File | What it is for | Who edits it |
|---|---|---|
| `.env` | Every setting and every secret for this deployment. | You, routinely. |
| `docker-compose.yml` | Which containers run, how they connect, what persists. | Only when changing the deployment pattern, or enabling HTTPS. |
| `nginx/delta.conf` | The reverse proxy in front of DELTA. | Only when enabling HTTPS, or if you removed nginx. |

`.env.example` is the template. Copy it to `.env` and edit that. `.env` is
excluded by `.gitignore`; keep it that way.

The `nginx/` directory holds two configurations, and only one is ever loaded:

| File | For |
|---|---|
| `delta.conf` | The default. nginx is the first thing clients reach, over HTTP or with TLS terminated here. Every forwarded value is what this server observed; nothing a client sends is trusted. |
| `delta-behind-tls-proxy.conf.example` | Only when a TLS-terminating gateway, load balancer or WAF sits in front. It trusts the `X-Forwarded-*` headers that gateway sets, and normalises the `Origin` header so DELTA's CSRF check works across the HTTPS-to-HTTP hop. |

The `.example` suffix keeps the second out of nginx's `conf.d/*.conf` include,
so it is never loaded by accident. Selecting it is a one-line Compose mount
change - see
[Deployment Options](deployment-options.md#when-tls-is-terminated-in-front).

Compose reads `.env` twice, and it is worth knowing why:

1. To fill in `${...}` placeholders in `docker-compose.yml` - this is how
   `POSTGRES_PASSWORD` reaches the database container.
2. As `env_file` for the DELTA container, which passes the whole file into it.

The second is what lets you add SMTP or SSO settings by editing `.env` alone,
with no change to `docker-compose.yml`. The tradeoff is that the DELTA container
also receives values it has no use for, such as `POSTGRES_PASSWORD` and
`HTTP_PORT`. That is a deliberate, documented choice in favour of one file to
edit rather than two.

> **Avoid `$` in any value in `.env`.** Compose reads it as the start of a
> variable reference. If a generated secret contains one, generate another.

---

## Required settings

DELTA checks these on every page load. If any is missing it serves a page headed
**"System configuration errors"** listing the ones it wants. That page returns a
normal HTTP 200, so an uptime check will report the site as fine.

Note carefully: DELTA requires these to be **present**, which is not the same as
it having a working default. `AUTHENTICATION_SUPPORTED` is the clearest example
- internally the application behaves as `form` when it is unset, but the
validator still reports it missing and the error page still appears. Leave them
set even at their default values.

| Setting | Accepted values | Notes |
|---|---|---|
| `PUBLIC_URL` | A full URL | The canonical address people use. Omit the port when it is standard for the scheme. |
| `SESSION_SECRET` | Any string | Signs session cookies. Changing it signs everyone out. |
| `DATABASE_URL` | A `postgresql://` URL | Built for you from the `POSTGRES_*` settings unless you set it. |
| `AUTHENTICATION_SUPPORTED` | `form`, `sso_azure_b2c`, or both comma-separated | Nothing else is recognised. |
| `EMAIL_TRANSPORT` | `file` or `smtp` | Anything else is rejected when mail is sent. |
| `EMAIL_FROM` | An address containing both `@` and `.` | `delta@localhost` is **rejected** - no dot. |

### `PUBLIC_URL`

The one canonical external address. It must match how people actually reach the
deployment, including the scheme.

!!! warning "It must be `https://` for any real hostname"

    DELTA marks session cookies `Secure`, so a browser will not return them over
    plain HTTP. Browsers make an exception for `http://localhost`, which is why
    local testing over HTTP works and the same deployment on a real hostname
    silently fails to keep anyone signed in.

Include the port only when it is not standard: `https://delta.example.org` for
443, `https://delta.example.org:8443` otherwise.

### `EMAIL_FROM`

Must contain an `@` and a `.`, otherwise DELTA reports *"Email sender address
appears to be invalid"*. The supplied default `noreply@delta.invalid` satisfies
that and can never resolve, which is correct while no mail is being sent. Use a
real address once you configure SMTP. Use a bare address - no display name.

---

## Database settings

| Setting | Used by | Notes |
|---|---|---|
| `POSTGRES_USER` | The bundled `db` container, and the derived connection string | Default `delta`. |
| `POSTGRES_DB` | Same | Default `delta`. |
| `POSTGRES_PASSWORD` | Same | See the warning below. |
| `DATABASE_URL` | DELTA | Leave unset for the bundled database - Compose builds it. For an external database, set it here **and** change one line in `docker-compose.yml`. |

> **`POSTGRES_PASSWORD` only applies when the data volume is created.**
> PostgreSQL sets the password at first initialisation and never looks at the
> variable again. Changing it in `.env` afterwards changes what DELTA sends, not
> what the database expects, and DELTA will fail to connect.
>
> To change it properly: set the new password in the database with
> `ALTER ROLE delta WITH PASSWORD '...';`, then update `.env` to match, then
> `docker compose up -d delta` to recreate the container with the new value.
> **Deleting the volume is not the fix** - that deletes all your data.

For the bundled database, `DATABASE_URL` is built in `docker-compose.yml` from
the three values above:

```yaml
      DATABASE_URL: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:5432/${POSTGRES_DB}
```

so the credentials the database is created with and the credentials DELTA uses
cannot drift apart. You do not set `DATABASE_URL` in `.env` for patterns A or C,
and a value set there is ignored - the line above wins.

For an external database (patterns B and D) you change that line to

```yaml
      DATABASE_URL: ${DATABASE_URL}
```

and set the full connection string in `.env`, including options like
`?sslmode=require`. **Both edits are needed**; doing only the `.env` half leaves
DELTA pointed at a `db` service that is no longer there.
[Deployment Options](deployment-options.md#b-external-database) walks
through it.

Confirm what Compose resolved before you start anything:

```
docker compose config
```

and look at the `DATABASE_URL` line under the `delta` service.

---

## Connection strings and special characters

A connection URL looks like this:

```
postgresql://USER:PASSWORD@HOST:PORT/DATABASE?option=value
```

The username and password sit in the part before the `@`. Characters there that
are not **unreserved** must be percent-encoded, or the URL is parsed wrongly -
usually silently and in a way that produces a confusing authentication failure.

Unreserved characters, safe as-is:

```
A-Z  a-z  0-9  -  .  _  ~
```

Everything else should be percent-encoded. The ones that actually break parsing
if left alone:

| Character | Encode as | | Character | Encode as |
|---|---|---|---|---|
| `@` | `%40` | | `#` | `%23` |
| `:` | `%3A` | | `?` | `%3F` |
| `/` | `%2F` | | `%` | `%25` |
| `[` | `%5B` | | `]` | `%5D` |
| space | `%20` | | `+` | `%2B` |

So a password of `p@ss/word` is written `p%40ss%2Fword` inside the URL.

**Other characters are not forbidden** - they just have to be encoded
correctly by whoever writes the URL, and when the URL is assembled from parts by
Compose, nothing encodes them for you. That is the whole reason step 2 of the
installation guide generates a password made only of letters and digits: it
sidesteps the problem rather than relying on everyone getting the encoding
right.

If you are given an existing password you cannot change, encode it and set the
complete `DATABASE_URL` in `.env` yourself rather than letting Compose assemble
it.

---

## Generating secrets

Use a cryptographically secure generator. Do not use `Get-Random`, a password
you thought of, or a value copied from another deployment.

**Session secret**

=== "Bash/zsh"

    ```bash
    openssl rand -base64 32
    ```

=== "PowerShell"

    ```powershell
    $b=[byte[]]::new(32)
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
    [Convert]::ToBase64String($b)
    ```

**Database password** - letters and digits only, so no URL encoding is needed:

=== "Bash/zsh"

    ```bash
    openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32; echo
    ```

=== "PowerShell"

    ```powershell
    $b=[byte[]]::new(64)
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
    ([Convert]::ToBase64String($b) -replace '[^A-Za-z0-9]','').Substring(0,32)
    ```

Both PowerShell forms use the .NET cryptographic random number generator and
work in Windows PowerShell 5.1 and PowerShell 7.

> Changing `SESSION_SECRET` later signs every user out immediately. It is not a
> value to rotate casually, and it is one you need in order to recover a
> deployment - keep it with your backups. See
> [Backup and Restore](backup-restore.md#what-a-backup-contains).

---

## Email and SMTP

`EMAIL_TRANSPORT` accepts `file` or `smtp`, and nothing else.

**`file`** is the default. DELTA writes messages to the container log instead of
sending them. A new deployment therefore needs no mail server at all, and this
is why the first deployment asks you no mail questions.

> Left on `file` in production, nothing reaches anyone: no password reset
> emails, no notifications. It is a fine default for getting started and a poor
> one to forget about.

**`smtp`** makes all four of these mandatory. Missing any one produces the
configuration-errors page:

| Setting | Notes |
|---|---|
| `SMTP_HOST` | Hostname of your mail server. |
| `SMTP_PORT` | Commonly 587, 465 or 25. |
| `SMTP_USER` | |
| `SMTP_PASS` | |
| `SMTP_SECURE` | Optional. `true` for implicit TLS on connect (port 465), `false` for 587 and 25. |

`EMAIL_FROM` must also be a valid, bare address - `"DELTA" <x@example.org>` is
rejected.

After changing any of these, recreate the container so it picks them up:

```
docker compose up -d delta
```

> `docker compose restart delta` will **not** apply new environment values. See
> [Lifecycle](lifecycle.md#restart-versus-applying-configuration-changes).

---

## Authentication

`AUTHENTICATION_SUPPORTED` is a comma-separated list. Only two values are
recognised:

- **`form`** - normal sign-in with an email address and password. Needs nothing
  else configured.
- **`sso_azure_b2c`** - Azure AD B2C. Including it makes
  `SSO_AZURE_B2C_TENANT`, `SSO_AZURE_B2C_CLIENT_ID` and
  `SSO_AZURE_B2C_CLIENT_SECRET` mandatory.

You can list both.

The built-in administrator account (`admin@admin.com`) is a form-login account
and is created by DELTA's own schema, not by anything in this repository. There
is no environment variable that sets its password - it is changed with a
database statement, which
[step 6.2 of the installation guide](index.md#62-replace-the-built-in-administrator-password)
walks through.
That step is mandatory: the password the schema ships with is public.

---

## Ports and networking

| Setting | Default | What it does |
|---|---|---|
| `HTTP_PORT` | `80` | Host port the bundled nginx listens on. |
| `HTTPS_PORT` | `443` | Host port for TLS, once you have enabled the HTTPS blocks. |

Inside the deployment, containers reach each other by service name on a private
network Compose creates: nginx connects to `delta:3000`, DELTA connects to
`db:5432`.

**Neither 3000 nor 5432 is published to the host.** That is deliberate. The
database is not reachable from outside the deployment at all, and DELTA is
reachable only through the proxy. If you remove nginx (scenario C or D) you must
publish DELTA yourself, and
[Deployment Options](deployment-options.md#c-existing-proxy-load-balancer-or-waf)
explains how to do that without exposing it to the world.

If port 80 is already in use on the host, change `HTTP_PORT` - to `8080`, say -
and set `PUBLIC_URL` to match (`http://localhost:8080`).

---

## Volumes and persistence

Three named volumes hold everything that must survive a container being
replaced:

| Volume | Mounted at | Contents |
|---|---|---|
| `pgdata` | `/var/lib/postgresql/data` | The entire database. |
| `uploads` | `/delta/uploads` | Every file users have uploaded. |
| `logs` | `/delta/logs` | DELTA's own rotating log files. |

Their real names are prefixed with the project name: `delta_pgdata`,
`delta_uploads`, `delta_logs`. List them with:

```
docker compose config --volumes     # the names in the file
docker volume ls                    # the real volumes on this host
```

Named volumes rather than bind mounts is a deliberate choice. They behave
identically on Windows, Linux and macOS; on Windows they measurably outperform a
bind mount for the database; and on Linux they avoid the root-owned directories a
bind mount produces, because the DELTA container runs as root.

**If you prefer bind mounts** for uploads or logs - to read log files directly,
for example - replace the entry in `docker-compose.yml`:

```yaml
    volumes:
      - ./logs:/delta/logs
```

and remove `logs:` from the `volumes:` block at the bottom. Expect the directory
to be created root-owned on Linux. Do **not** do this for `pgdata` on Windows or
macOS; a bind-mounted PostgreSQL data directory there is slower and its file
semantics are not a faithful match.

> **Never mount anything over `/delta` itself.** That hides the application
> inside the image. Only the two paths above are mounted, and `/delta/uploads`
> is hard-coded in DELTA - it cannot be moved.

Backing these up is [Backup and Restore](backup-restore.md). The one thing to
know here: `docker compose down -v` deletes all three.

---

## Project identity and why it matters

Compose groups containers, networks and volumes under a **project name**. That
name is the prefix on your volumes, so it decides which data a deployment finds.

By default Compose uses the name of the directory the file sits in. That is a
trap: rename `delta` to `delta-old`, or move the deployment to another path, and
Compose looks for `delta-old_pgdata`, does not find it, creates it empty, and
DELTA initialises a brand-new database. Everything still starts. It looks
exactly like the data vanished.

`docker-compose.yml` therefore pins the name:

```yaml
name: ${COMPOSE_PROJECT_NAME:-delta}
```

so the directory can be renamed or moved freely.

### Running more than one DELTA deployment on one host

**Each deployment must set a distinct `COMPOSE_PROJECT_NAME` in its own `.env`,
and publish a distinct `HTTP_PORT`.** Two deployments left on the pinned default
share one project name, which means they share containers, one network and one
set of volumes - the second `docker compose up -d` recreates the first one's
containers against the first one's data. They will corrupt each other.

Give them names that say what they are: `delta-prod`, `delta-staging`. The
volumes then separate cleanly into `delta-prod_pgdata`, `delta-staging_pgdata`
and so on, and `docker compose` run from each directory only ever touches its
own.

**Changing the name on an existing deployment is a different thing entirely.**
It points that deployment at a different, empty set of volumes. The old data is
still on the host under the old prefix, but nothing is using it, and DELTA will
initialise a new database and look exactly as though the data is gone.

To check which volumes a deployment is actually using:

```
docker compose ps --format '{{.Name}}'
docker volume ls
```

---

## Settings deliberately not included

The DELTA server reads a number of other environment variables. They are not in
`.env.example` because their accepted values and effects are not verified
anywhere available to us, and documenting a guess is worse than leaving a
setting out. If you know you need one, add it to `.env` - `env_file` passes the
whole file to the container, so nothing else has to change.

Equally, several settings that appear in the Windows installer's template are
**not** here because they configure that installer rather than DELTA:
`TLS_MODE`, `TLS_ENABLED`, `PGDATA_VOLUME`, `DELTA_IMAGE_TAG`, `DELTA_HOSTNAME`
and `DELTA_DB_PASSWORD`. Their absence is not an omission.
