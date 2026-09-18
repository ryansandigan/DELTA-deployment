# DELTA Deployment

Deployment files and operator documentation for DELTA. The documented
deployment procedure uses Docker and Docker Compose. Three files are the
deployment - `docker-compose.yml`, `.env` and `nginx/delta.conf` - and they
are the same on every platform.

This page is the complete installation guide.

## Contents

- [Prerequisite: Docker](#prerequisite-docker)
- [Install DELTA](#install-delta)
  - [1. Get the deployment files](#1-get-the-deployment-files)
  - [2. Configure `.env`](#2-configure-env)
  - [3. Set up HTTPS](#3-set-up-https)
  - [4. Validate the configuration and download the images](#4-validate-the-configuration-and-download-the-images)
  - [5. Start the database and DELTA privately](#5-start-the-database-and-delta-privately)
  - [6. Check initialisation and secure the administrator account](#6-check-initialisation-and-secure-the-administrator-account)
  - [7. Start nginx and allow access](#7-start-nginx-and-allow-access)
  - [8. Open DELTA and verify sign-in](#8-open-delta-and-verify-sign-in)
- [Lifecycle](#lifecycle)
- [Troubleshooting](#troubleshooting)

---

## Prerequisite: Docker

Docker and Docker Compose must be working:

```
docker --version
docker compose version
docker run --rm hello-world
```

You need a Docker version, `Docker Compose version v2.20` or newer, and
*"Hello from Docker!"*. If you have that, go to [Install DELTA](#install-delta).

If not, install Docker first — each guide ends when Docker is verified:

- [Windows](docs/docker/windows.md) — Windows 10/11 and Windows Server
  2022/2025, with Docker Desktop
- [macOS](docs/docker/macos.md) — Docker Desktop
- [Ubuntu](docs/docker/ubuntu.md) · [Debian](docs/docker/debian.md) ·
  [AlmaLinux](docs/docker/almalinux.md) — Docker Engine

---

## Install DELTA

This installs the reference stack: bundled PostgreSQL/PostGIS, DELTA, and
bundled nginx.

```
   client  ──▶  nginx  ──▶  delta  ──▶  db
                  :80        :3000       :5432
              (published)   (private)   (private)
```

> **Using a database you host elsewhere, or your own proxy/gateway?** Apply the
> edits for your pattern in
> [docs/deployment-options.md](docs/deployment-options.md) **before** you start.
> The steps below note where your commands differ.

Most commands are identical everywhere. Where the shell genuinely differs, both
forms are shown — **PowerShell** on Windows, **Bash/zsh** on macOS and Linux.

### 1. Get the deployment files

Copy the DELTA deployment folder onto the machine and open a terminal in it.
This project is not published to a Git repository yet, so there is no
`git clone` — you should have received the folder directly.

PowerShell:

```powershell
Get-ChildItem -Force
```

Bash/zsh:

```bash
ls -a
```

**Expected:** `docker-compose.yml`, `.env.example`, `nginx/` and `docs/`.

### 2. Configure `.env`

PowerShell:

```powershell
Copy-Item .env.example .env
```

Bash/zsh:

```bash
cp .env.example .env
```

Generate a session secret — PowerShell:

```powershell
$b=[byte[]]::new(32)
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
[Convert]::ToBase64String($b)
```

Bash/zsh:

```bash
openssl rand -base64 32
```

Generate a database password of letters and digits only, which avoids any URL
encoding question — PowerShell:

```powershell
$b=[byte[]]::new(64)
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
([Convert]::ToBase64String($b) -replace '[^A-Za-z0-9]','').Substring(0,32)
```

Bash/zsh:

```bash
openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32; echo
```

Edit `.env` and set:

| Setting | Value |
|---|---|
| `PUBLIC_URL` | The address people will use — `https://your.hostname`, or `http://localhost` for local testing |
| `SESSION_SECRET` | The generated session secret |
| `POSTGRES_PASSWORD` | The generated database password. **External database:** set `DATABASE_URL` instead, per [deployment-options.md](docs/deployment-options.md#b---external-database) |
| `HTTP_PORT` | Leave at `80` unless something else on the host uses it |

Leave `AUTHENTICATION_SUPPORTED`, `EMAIL_TRANSPORT` and `EMAIL_FROM` as
supplied — DELTA requires them to be present, and the defaults give a working
deployment with no mail server. Every setting:
[configuration.md](docs/configuration.md).

Two things that bite later:

- If a generated value contains a `$`, generate it again — Compose reads `$` as
  the start of a variable reference.
- `POSTGRES_PASSWORD` only takes effect when the database volume is first
  created. Changing it afterwards makes DELTA send a password the database does
  not expect.

On Windows, save `.env` as UTF-8 without a byte order mark.

### 3. Set up HTTPS

Skip this step only for `http://localhost` testing. DELTA marks session cookies
`Secure`, so at a real hostname over plain HTTP users sign in and are
immediately signed out again.

**Using your own gateway?** It terminates TLS — skip this step, but meet the
requirements in
[deployment-options.md](docs/deployment-options.md#what-your-gateway-must-do).

Otherwise create a `certs` folder next to `docker-compose.yml`, put your
certificate and key in it as `delta.crt` (full chain) and `delta.key`, follow
the numbered HTTPS instructions in `nginx/delta.conf`, and set `HTTPS_PORT` in
`.env` if it is not 443.

### 4. Validate the configuration and download the images

```
docker compose config
docker compose pull
```

**Expected:** `docker compose config` prints the resolved configuration and
exits cleanly — check `DATABASE_URL` is a complete connection string with no
leftover `${...}`. Each image then reports `Pulled` or that it already exists.

### 5. Start the database and DELTA privately

> **External database:** there is no `db` service. Start DELTA alone with
> `docker compose up -d delta` instead of the command below.

```
docker compose up -d db delta
docker compose ps
```

**Expected:** `db` and `delta` both `Up ... (healthy)`. A first start loads the
whole schema and takes about 90 seconds.

> Do not run `docker compose up -d` yet — that starts nginx and publishes the
> site while the built-in administrator account still has the password shipped
> in the public image. Using your own gateway? Leave its route disabled.

### 6. Check initialisation and secure the administrator account

#### 6.1 Confirm the schema initialised

A healthy container is not proof; the schema step does not stop on error.

```
docker compose logs delta
```

**Expected:** the log contains `Initializing new database with full schema...`
(first deployment) or `Applying upgrade migrations to existing database...`,
with no `ERROR`, `FATAL` or `PANIC` after it. `NOTICE` and `WARNING` are normal
schema-load output.

Then read the schema version back. **External database** — use this form, which
takes the connection string from the container:

```
echo "select version_no from dts_system_info;" | docker compose exec -T delta sh -c 'set -f; psql $DATABASE_URL --tuples-only --no-align'
```

**Bundled database:**

```
echo "select version_no from dts_system_info;" | docker compose exec -T db sh -c 'psql -U $POSTGRES_USER -d $POSTGRES_DB --tuples-only --no-align'
```

**Expected:** a version number such as `0.2.3`. If the query fails, the schema
is unusable whatever the container status says —
[troubleshooting.md](docs/troubleshooting.md#startup-and-migrations).

#### 6.2 Replace the built-in administrator password

DELTA's schema creates `admin@admin.com` with a password hash that is public in
the container image. Replace it now, before anything is published.

> **External database:** the commands below use the bundled `db` container,
> which you do not have. Use the complete procedure in
> [deployment-options.md](docs/deployment-options.md#replacing-the-administrator-password-on-an-external-database),
> then continue at [step 7](#7-start-nginx-and-allow-access).

Read the new password into your environment — not echoed, not stored in history.
Use at least 12 characters.

PowerShell:

```powershell
$sec  = Read-Host -AsSecureString 'New DELTA administrator password'
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
$env:DELTA_ADMIN_NEW_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
```

Bash/zsh — this form works in bash, zsh and dash alike. If you interrupt it
part-way, run `stty echo` to make typing visible again:

```bash
printf 'New DELTA administrator password: '
stty -echo; read -r DELTA_ADMIN_NEW_PASSWORD; stty echo; printf '\n'
export DELTA_ADMIN_NEW_PASSWORD
```

Apply it — PowerShell:

```powershell
@'
\getenv password DELTA_ADMIN_NEW_PASSWORD
UPDATE public.super_admin_users
   SET password = crypt(:'password', gen_salt('bf', 10))
 WHERE email = 'admin@admin.com' RETURNING email;
'@ | docker compose exec -T -e DELTA_ADMIN_NEW_PASSWORD db sh -c 'psql -U $POSTGRES_USER -d $POSTGRES_DB --set ON_ERROR_STOP=on --tuples-only --no-align -f -'
```

Bash/zsh:

```bash
docker compose exec -T -e DELTA_ADMIN_NEW_PASSWORD db \
  sh -c 'psql -U $POSTGRES_USER -d $POSTGRES_DB --set ON_ERROR_STOP=on --tuples-only --no-align -f -' <<'SQL'
\getenv password DELTA_ADMIN_NEW_PASSWORD
UPDATE public.super_admin_users
   SET password = crypt(:'password', gen_salt('bf', 10))
 WHERE email = 'admin@admin.com' RETURNING email;
SQL
```

**Expected:** it prints `admin@admin.com`. `psql` may also print a status line
such as `UPDATE 1`, which is normal.

`-e NAME` with no value passes the variable in from your shell rather than
putting it on a command line, and `\getenv` reads it inside the container, so
the password appears in no process's arguments and no history file.

#### 6.3 Verify the new password

This uses the same check the application uses — PowerShell:

```powershell
@'
\getenv password DELTA_ADMIN_NEW_PASSWORD
SELECT email, (password = crypt(:'password', password)) AS verifies
  FROM public.super_admin_users WHERE email = 'admin@admin.com';
'@ | docker compose exec -T -e DELTA_ADMIN_NEW_PASSWORD db sh -c 'psql -U $POSTGRES_USER -d $POSTGRES_DB --set ON_ERROR_STOP=on --tuples-only --no-align -f -'
```

Bash/zsh:

```bash
docker compose exec -T -e DELTA_ADMIN_NEW_PASSWORD db \
  sh -c 'psql -U $POSTGRES_USER -d $POSTGRES_DB --set ON_ERROR_STOP=on --tuples-only --no-align -f -' <<'SQL'
\getenv password DELTA_ADMIN_NEW_PASSWORD
SELECT email, (password = crypt(:'password', password)) AS verifies
  FROM public.super_admin_users WHERE email = 'admin@admin.com';
SQL
```

**Expected:**

```
admin@admin.com|t
```

The `t` means the stored credential matches what you typed.

> **If it does not print `t`, stop.** The password was not replaced. Do not
> continue to step 7 and do not make this deployment reachable.

Clear the password, then record it in your password manager — nothing else
stores it.

PowerShell:

```powershell
Remove-Item Env:\DELTA_ADMIN_NEW_PASSWORD
```

Bash/zsh:

```bash
unset DELTA_ADMIN_NEW_PASSWORD
```

### 7. Start nginx and allow access

> **Using your own gateway?** There is no bundled nginx to configure, start or
> check — skip to *Allowing network access* below, publish the `delta` backend
> port as described in
> [deployment-options.md](docs/deployment-options.md#c---existing-proxy-load-balancer-or-waf),
> and enable the gateway route now. Not before step 6.3 passed: an unprotected
> backend is reachable whether or not the gateway route exists.

```
docker compose run --rm --no-deps --entrypoint nginx nginx -t
docker compose up -d
```

**Expected:** `syntax is ok` / `test is successful`, then every service starts.
If `nginx -t` reports `duplicate default server`, both the HTTP and HTTPS server
blocks are active in `nginx/delta.conf` — delete the HTTP one.

#### Allowing network access

Open only the ports your configuration actually serves:

| Your configuration | Open |
|---|---|
| HTTPS enabled (the TLS blocks) | `HTTPS_PORT`, plus `HTTP_PORT` only if the HTTP-to-HTTPS redirect should work from other machines |
| HTTP only | `HTTP_PORT` |
| Your own gateway | Only the `delta` backend port, and only to the gateway |

**Windows** — PowerShell, substituting your port:

```powershell
New-NetFirewallRule -DisplayName "DELTA 443" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow
```

**Linux** — use your host's firewall (`ufw`, `firewalld` or your platform's
tooling). Docker inserts its own rules, so a published port can be reachable
even when the host firewall appears to deny it; binding a service to a specific
address is the more reliable control, as in
[deployment-options.md](docs/deployment-options.md#choosing-the-published-address---this-is-a-security-decision).

**macOS** — no rule is normally needed for local use.

A firewall rule permits traffic; it does not by itself prove the port is
reachable, since routing, other firewalls and network policy all still apply.
Confirm from another machine.

### 8. Open DELTA and verify sign-in

```
docker compose ps
```

**Expected:** every service `Up` and `(healthy)`.

Then in a browser:

| Check | Expected |
|---|---|
| Open `PUBLIC_URL` | The application loads, not a "System configuration errors" page |
| Sign in at `PUBLIC_URL` + `/en/admin/login` as `admin@admin.com` | You are signed in |
| Move between pages | You stay signed in |
| Upload a file over 1 MB | It completes |

Finally, confirm data survives the container being replaced:

```
docker compose up -d --force-recreate delta
```

Reload and check your data and the uploaded file are still there. This replaces
the container and reattaches the volumes; `docker compose restart` would reuse
the same container and prove less.

Being signed out immediately after signing in means session cookies are being
dropped — [troubleshooting.md](docs/troubleshooting.md#https-and-sessions). An
HTTP 413 on upload means a proxy is refusing the body size —
[troubleshooting.md](docs/troubleshooting.md#http-413-on-upload).

**Before handing this over:** pin `DELTA_IMAGE` to a digest
([update.md](docs/update.md#pin-the-image)), and take and test a backup
([backup-restore.md](docs/backup-restore.md)).

---

## Lifecycle

Day-to-day operation — starting, stopping, logs, and applying configuration
changes — is in [lifecycle.md](docs/lifecycle.md), which also points to
[update.md](docs/update.md) and
[backup-restore.md](docs/backup-restore.md).

Three things that catch people out:

- **`docker compose restart` does not apply `.env` changes.** Use
  `docker compose up -d`.
- **`docker compose down -v` deletes your database and every uploaded file.**
  Without `-v` it removes the containers and keeps the data.
- **A healthy container does not mean the schema migration worked.** The
  migration step does not stop on error —
  [update.md](docs/update.md#reading-the-migration-output).

## Troubleshooting

Symptom, checks, action: [troubleshooting.md](docs/troubleshooting.md).

Reference documents: [configuration.md](docs/configuration.md) for every
setting, and [deployment-options.md](docs/deployment-options.md) for using your
own database or gateway.
