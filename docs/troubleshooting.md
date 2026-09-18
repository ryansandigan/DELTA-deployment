# Troubleshooting

Find the symptom, run the checks, apply the action. Each entry links to the
canonical procedure rather than repeating it.

Two commands come up constantly:

```
docker compose ps                      # what is running and whether it is healthy
docker compose logs --tail 100 delta   # why it is not
```

**Contents**

- [Docker and Compose](#docker-and-compose)
- [Virtualisation on Windows](#virtualisation-on-windows)
- [Image pulls](#image-pulls)
- [Ports](#ports)
- [.env and configuration](#env-and-configuration)
- [Database connectivity and health](#database-connectivity-and-health)
- [DELTA will not start](#delta-will-not-start)
- [Startup and migrations](#startup-and-migrations)
- ["System configuration errors" page](#system-configuration-errors-page)
- [The proxy](#the-proxy)
- [HTTP 413 on upload](#http-413-on-upload)
- [HTTPS and sessions](#https-and-sessions)
- [Volume identity - "where did my data go?"](#volume-identity---where-did-my-data-go)
- [Permissions](#permissions)
- [Logs](#logs)

---

## Docker and Compose

**`docker: command not found`, or "Cannot connect to the Docker daemon"**

Checks:

```
docker --version
docker info
```

Action. If the version prints but `docker info` fails, the daemon is not
running: start Docker Desktop on Windows or macOS; on Linux,
`sudo systemctl start docker`. On Linux, "permission denied" on the socket means
your user is not in the `docker` group - see your platform's Docker guide.

**`docker compose` is not recognised, but `docker-compose` works**

You have the old v1 tool. This deployment needs Compose v2.20 or newer. Install
the Compose v2 plugin - see your platform's Docker guide:
[Windows](docker/windows.md) · [macOS](docker/macos.md) ·
[Ubuntu](docker/ubuntu.md) · [Debian](docker/debian.md) ·
[AlmaLinux](docker/almalinux.md).

**`unknown shorthand flag` or unexpected errors on `docker compose config`**

Check `docker compose version`. Below v2.20, update it.

---

## Virtualisation on Windows

**Docker reports "Virtualization support not detected", or WSL 2 will not
start**

First establish whether this machine is physical or a virtual machine — the
same readings mean different things:

```powershell
Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model, HypervisorPresent
(Get-CimInstance Win32_Processor | Select-Object -First 1) |
  Select-Object VirtualizationFirmwareEnabled, VMMonitorModeExtensions, SecondLevelAddressTranslationExtensions
```

A `Manufacturer`/`Model` such as `Microsoft Corporation` / `Virtual Machine`,
`VMware, Inc.`, `QEMU` or `Xen` means this is a virtual machine.

**On a physical machine.** Virtualisation is available if `HypervisorPresent` is
`True` **or** either processor flag is `True`; any one is enough. If all are
`False`, it is switched off in the firmware: reboot into BIOS/UEFI and enable it
(Intel VT-x or AMD-V, sometimes with a separate SLAT/VT-d entry).

**On a virtual machine**, the host's hypervisor must expose virtualisation to
the guest — nested virtualisation.

> `HypervisorPresent` is `True` inside **every** guest VM and proves nothing
> here. The processor flags are one-way evidence: `True` means nested
> virtualisation is genuinely present, `False` means **inconclusive**, not
> absent. Measured on a Windows Server 2022 Hyper-V guest whose host had nested
> virtualisation enabled, all three flags still read `False` while it was
> working.

So a `False` reading is not a reason to stop. If Docker then reports
"Virtualization support not detected", nested virtualisation really is missing.
Fix it on the physical host with the VM shut down — on Hyper-V:

```powershell
Set-VMProcessor -VMName <vm-name> -ExposeVirtualizationExtensions $true
```

On VMware or another hypervisor, enable the equivalent "expose hardware assisted
virtualization" setting.

**Windows features not in effect.** WSL 2 also needs the Virtual Machine
Platform feature and the hypervisor set to start at boot. Both need a restart
after being changed:

```powershell
Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform | Select-Object State
bcdedit /enum '{current}' | Select-String hypervisorlaunchtype
```

See [docker/windows.md](docker/windows.md#1-turn-on-the-windows-features-wsl-2-needs).

---

## Image pulls

**`pull access denied`, `manifest unknown`, or `not found`**

Checks:

```
docker compose config | findstr image      # PowerShell
docker compose config | grep image         # Linux/macOS
```

Action. Look for a typo in `DELTA_IMAGE`, or a digest that does not exist. The
DELTA image is public - no `docker login` is needed, so an authentication error
usually means the reference itself is wrong.

**The pull is very slow or times out**

The DELTA image is around 214 MB. On a restricted network, check whether a proxy
or registry mirror is required and configure it in Docker itself, not here.

**`no matching manifest for linux/arm64`**

The DELTA image is published for `linux/amd64` only. On an arm64 machine,
uncomment `platform: linux/amd64` in the `delta` service to run it under
emulation. Expect it to be slow; this combination is not covered by testing we
have.

---

## Ports

**`bind: address already in use` when nginx starts**

Checks:

```
docker compose logs nginx
netstat -ano | findstr :80      # PowerShell
sudo ss -lptn 'sport = :80'     # Linux
```

Action. Something else already owns the port - IIS, Apache, another Compose
project. Either stop it, or set `HTTP_PORT` in `.env` to a free port (`8080`,
say), update `PUBLIC_URL` to match, and `docker compose up -d`.

**`permission denied` binding port 80 on Linux**

Ports below 1024 need privileges. Run Docker as configured in the official
post-installation steps, or use a high port and let your gateway map it.

---

## .env and configuration

**Compose warns "variable is not set" or a value comes out empty**

Checks:

```
docker compose config
```

Action. `.env` must sit next to `docker-compose.yml` and be named exactly
`.env` - `.env.example`, `env`, or `.env.txt` are not read. On Windows, check
File Explorer is not hiding an extension.

**`DATABASE_URL` is empty or still shows `${...}` in `docker compose config`**

Action. `POSTGRES_USER`, `POSTGRES_PASSWORD` or `POSTGRES_DB` is missing from
`.env`. Set all three, or set `DATABASE_URL` explicitly. Re-run
`docker compose config` until the line is a complete connection string.

**A password with a `$` in it does not work**

Action. Compose reads `$` as the start of a variable reference. Generate a new
secret without one -
[configuration.md](configuration.md#generating-secrets).

**Changes to `.env` seem to have no effect**

Action. `docker compose restart` does not apply them. Use
`docker compose up -d`, which recreates the container. See
[lifecycle.md](lifecycle.md#restart-versus-applying-configuration-changes).

---

## Database connectivity and health

**`db` never becomes healthy**

Checks:

```
docker compose ps
docker compose logs db
```

Action:

- `database files are incompatible with server` - the `pgdata` volume was
  created by a different PostgreSQL major version. Put the previous `DB_IMAGE`
  back. See [update.md](update.md#do-not-upgrade-postgresql-at-the-same-time).
- `initdb: directory not empty` or permission errors - the volume is in an
  unexpected state. Do not delete it if it holds your data; investigate.

**DELTA reports `password authentication failed for user "delta"`**

Cause, almost always: `POSTGRES_PASSWORD` was changed in `.env` after the volume
was first created. PostgreSQL only reads that variable when it initialises the
volume, so the database still expects the original password.

Action:

Open a database prompt:

```
docker compose exec db sh -c 'psql -U $POSTGRES_USER -d $POSTGRES_DB'
```

At the `delta=#` prompt, set the role's password to the value now in `.env` -
substitute your own `POSTGRES_USER` for `delta` if you changed it:

```
ALTER ROLE delta WITH PASSWORD 'the-value-now-in-your-env';
\q
```

Then recreate the container so DELTA picks up the matching value:

```
docker compose up -d delta
```

> **Do not "fix" this by deleting the volume.** That deletes the entire
> database.

**DELTA cannot reach an external database**

Checks:

```
docker compose config | grep DATABASE_URL
echo "select 1;" | docker compose exec -T delta sh -c 'set -f; psql $DATABASE_URL'
```

Action. Check the host, port and firewall between this host and the database;
check `sslmode`; check every special character in the username or password is
percent-encoded -
[configuration.md](configuration.md#connection-strings-and-special-characters).

---

## DELTA will not start

**`delta` restarts in a loop**

Checks:

```
docker compose ps
docker compose logs --tail 200 delta
```

Action, by what the log says:

| Message | Cause | Fix |
|---|---|---|
| `could not connect to server` / `Connection refused` | The database was not ready, or is unreachable | Confirm `db` is healthy; for an external database see above |
| `password authentication failed` | Credential mismatch | See the previous section |
| `permission denied to create extension "postgis"` | External database without PostGIS pre-created | A superuser must run `CREATE EXTENSION postgis;` and `CREATE EXTENSION pgcrypto;` first - [deployment-options.md](deployment-options.md#what-the-external-database-must-provide) |
| `database "delta" does not exist` | Wrong database name in `DATABASE_URL` | Correct it |

**`delta` runs but never becomes healthy**

A first start loads the whole schema and can take around 90 seconds; the
healthcheck allows 3 minutes. If it is still not healthy after that, read the
logs - the application is up but the probe is failing, which usually means the
application itself is erroring.

---

## Startup and migrations

**Did the schema step actually work?**

A healthy container is **not** proof. The schema step does not stop on error -
it can fail partway and the application still starts.

Checks:

```
docker compose logs --since 10m delta
echo "select version_no from dts_system_info;" | docker compose exec -T db sh -c 'psql -U $POSTGRES_USER -d $POSTGRES_DB --tuples-only --no-align'
```

What to look for:

- One of `Initializing new database with full schema...` or
  `Applying upgrade migrations to existing database...`, from **this** start -
  the container logs every start it has ever made, so scope the output.
- No `ERROR`, `FATAL` or `PANIC` after that line.
- `NOTICE` and `WARNING` are normal. Lines beginning `psql:` are not a verdict
  either way - that prefix appears on ordinary notices too. Judge by the
  severity word.
- The version query returns a number.

Full detail: [update.md](update.md#reading-the-migration-output).

**It says "Initializing new database" but this deployment already had data**

Stop immediately - `docker compose stop delta` - before anything is written.
DELTA found an empty database and is building a new schema. Either it is pointed
at the wrong database, or it is using different volumes than you think. See
[volume identity](#volume-identity---where-did-my-data-go).

---

## "System configuration errors" page

**The site loads but shows a page listing variable names**

DELTA started fine; a required setting is missing. Note that this page returns a
normal HTTP 200, so an uptime monitor will not report anything wrong.

Checks. The page names the variables. The required set is `PUBLIC_URL`,
`SESSION_SECRET`, `DATABASE_URL`, `AUTHENTICATION_SUPPORTED`, `EMAIL_TRANSPORT`
and `EMAIL_FROM`.

Action. Add the named variables to `.env`, then `docker compose up -d delta`.

Common causes:

- `AUTHENTICATION_SUPPORTED` left out because DELTA "defaults to form anyway" -
  it does, but the check still requires the variable to be present.
- `EMAIL_FROM` set to something without a dot, such as `delta@localhost`.
- `EMAIL_TRANSPORT=smtp` without all four of `SMTP_HOST`, `SMTP_PORT`,
  `SMTP_USER` and `SMTP_PASS`.

See [configuration.md](configuration.md#required-settings).

---

## The proxy

**`nginx` will not start: `duplicate default server`**

Both the HTTP and the HTTPS server block are active in `nginx/delta.conf`.
Delete the HTTP one when enabling TLS - the file's own HTTPS instructions say
so.

**`nginx` will not start: `host not found in upstream "delta"`**

nginx resolves the `delta` name while it reads its configuration, so the DELTA
container has to be running first. Start it - `docker compose up -d delta` -
then start nginx. This is also why the installation guide checks the proxy
configuration at step 7 rather than step 4.

**`nginx` is unhealthy but the site works**

You enabled TLS but left the HTTP healthcheck in place. Port 80 now answers
`301`, and this image's `wget` does not follow redirects. Comment out the HTTP
healthcheck in `docker-compose.yml` and uncomment the HTTPS one, then
`docker compose up -d nginx`.

**502 Bad Gateway**

Checks:

```
docker compose ps
docker compose logs nginx
docker compose logs --tail 50 delta
```

Action. `delta` is not answering. Work through
[DELTA will not start](#delta-will-not-start). nginx waits for `delta` to be
healthy before starting, so a 502 usually means DELTA failed *after* it was
healthy.

**Edits to `nginx/delta.conf` have no effect**

```
docker compose restart nginx
```

The file is mounted from disk, so nginx only needs to re-read it.

---

## HTTP 413 on upload

**Uploads over about 1 MB fail**

Cause. A proxy is refusing the request body before DELTA sees it. nginx's
default limit is 1 MB; DELTA accepts up to 10 MB generally and 50 MB on one
path.

Checks. Which proxy is in front of DELTA?

Action:

- **Bundled nginx**: `client_max_body_size 64m;` is already in
  `nginx/delta.conf`. If it is missing from the server block you are using -
  the HTTPS one, for instance - add it, then `docker compose restart nginx`.
- **Your own gateway** (pattern C or D): raise its body limit to at least
  64 MB. See
  [deployment-options.md](deployment-options.md#what-your-gateway-must-do).

---

## HTTPS and sessions

**Sign-in appears to succeed, then you are signed out on the next page**

Cause. The session cookie is not coming back. DELTA marks it `Secure`, so the
browser only returns it over HTTPS.

Checks:

- Is `PUBLIC_URL` `https://` and does it match how you actually reached the
  site?
- Pattern C or D: is your gateway sending `X-Forwarded-Proto: https`?

Action:

- Enable HTTPS - [step 3 of the installation guide](../README.md#3-set-up-https)
  and the HTTPS section of `nginx/delta.conf` - or terminate TLS at your gateway.
- Set the forwarded headers on your gateway -
  [deployment-options.md](deployment-options.md#what-your-gateway-must-do).

> Testing on `http://localhost` will **not** reproduce this. Browsers treat
> localhost as a secure context, so the cookie works there and nowhere else over
> plain HTTP.

**The site loads, but every form submission returns HTTP 403**

Cause. React Router's CSRF check is rejecting an `Origin` mismatch. TLS was
terminated in front of DELTA and the hop onward is plain HTTP, so the browser
sends `Origin: https://your.host` while DELTA computes `http://your.host` for
the same request. You stay signed in, and only state-changing requests fail.

Checks, on the request that returned 403:

- `Origin` - does it say `https://` while DELTA is reached over HTTP?
- `Host` - does your gateway forward the original host, or substitute an
  internal name?
- `X-Forwarded-Proto` / `-Host` / `-Port` - are they set, and do they describe
  the public address the browser used?

Action. The default `nginx/delta.conf` does not handle this, by design. Select
the alternate configuration, or implement the same behaviour on your own
gateway:
[deployment-options.md](deployment-options.md#when-tls-is-terminated-in-front).

**Browser warns the certificate is not trusted**

The certificate is self-signed, or `certs/delta.crt` is missing its intermediate
certificates. The file must contain the full chain: server certificate first,
then intermediates.

**Timeouts on long uploads or report generation**

Both the bundled nginx and any gateway in front of DELTA need a read timeout of
at least 300 seconds. The default in most proxies is 60.

---

## Volume identity - "where did my data go?"

**The deployment starts, works, and is empty**

Cause, nearly always: it is using different volumes than you think. Compose
names volumes after the project, and the project defaults to the directory
name - so renaming or moving the folder can point it at a fresh, empty set.

Checks:

```
docker compose config --volumes
docker volume ls
docker volume inspect delta_pgdata
```

Action. If `docker volume ls` shows your data under another prefix - say
`deltaold_pgdata` - set `COMPOSE_PROJECT_NAME` in `.env` to that prefix and run
`docker compose up -d`. `docker-compose.yml` pins the project name to `delta` to
prevent this; a deployment created before that pin may be on a different one.

> Do not run `docker volume prune` while investigating this. It deletes volumes
> no container currently uses - which is exactly the state your real data is in
> at that moment.

See [configuration.md](configuration.md#project-identity-and-why-it-matters).

---

## Permissions

**On Linux, a bind-mounted directory is owned by root**

Expected. The DELTA container runs as root, so files it creates on a bind mount
are root-owned. The supplied configuration uses named volumes precisely to avoid
this - see
[configuration.md](configuration.md#volumes-and-persistence).

**`permission denied` reading `nginx/delta.conf`**

The file must be readable by the Docker daemon's user. On Linux, check it is not
mode 600 owned by another user.

**Windows: Docker Desktop cannot access the folder**

The deployment folder must be on a drive shared with Docker Desktop
(Settings → Resources → File sharing). Only `nginx/` and `certs/` are bind
mounted, but they still need this.

---

## Logs

**Where do I look?**

| Question | Command |
|---|---|
| Why did the container stop? | `docker compose logs --tail 200 <service>` |
| What is happening right now? | `docker compose logs -f <service>` |
| What happened at 14:05? | `docker compose logs --since 2026-09-16T14:00:00 <service>` |
| What does DELTA's own log file say? | `docker compose exec delta cat /delta/logs/error-<date>.log` |

**Old log output has disappeared**

Container logs are capped at 20 MB per service with 5 files kept, so the oldest
output is discarded. That cap is there to stop logs filling the disk. For a
durable record, ship logs off the host - or read DELTA's own rotating files in
the `logs` volume, which are governed by `LOG_RETENTION_DAYS`.

**Collecting evidence before you change anything**

```
docker compose ps > diagnosis.txt
docker compose logs --tail 500 >> diagnosis.txt
docker compose config >> diagnosis.txt
```

> `docker compose config` prints your `.env` values, including passwords and
> `SESSION_SECRET`. Remove them before sending the file to anyone.
