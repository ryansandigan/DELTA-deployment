# Backup and restore

A fresh deployment needs no dump. DELTA builds its own schema and seed data the
first time it starts against an empty database. Dumps are for moving existing
data and for recovery.

---

## What a backup contains

A database dump alone will not bring DELTA back: it restores the records and
loses every uploaded file. Keep all four parts together as one set.

| Part | What it is |
|---|---|
| Database | All application data |
| Uploads | Every uploaded file, in the `uploads` volume |
| Configuration | `.env`, `docker-compose.yml`, `nginx/delta.conf`, TLS certificates. `SESSION_SECRET` exists nowhere else |
| Image digest | The `DELTA_IMAGE` the dump's schema belongs to. A restore needs it |

The `logs` volume is not part of a backup set.

**Which deployment are you acting on?** Every command here runs through
`docker compose` from the deployment's own directory, so it acts on that
project's containers and volumes. Volume names are the project name plus the
volume name — `delta_pgdata`, `delta_uploads`, `delta_logs` by default. Check
with:

```
docker compose ps
docker compose config --volumes
```

---

## Working with the uploads volume

Uploads live in a Docker volume, and both backup and restore need to read and
write it while DELTA is stopped. This command shape does that:

=== "Bash/zsh"

    ```bash
    docker compose run --rm --no-deps --entrypoint sh \
      -v "$(pwd)/backups:/backup" delta -c '<command>'
    ```

=== "PowerShell"

    ```powershell
    docker compose run --rm --no-deps --entrypoint sh -v "$($PWD.Path)\backups:/backup" delta -c '<command>'
    ```

It starts a throwaway container from the DELTA image with the same volumes
attached, so `/delta/uploads` is the data DELTA sees. `--entrypoint sh` replaces
the image's startup command, so DELTA's schema and migration step does not run.
`--no-deps` starts no other service, `docker compose run` publishes no ports, and
`--rm` removes the container afterwards. The `-v` mount makes the host
`backups/` folder available inside as `/backup`; add `:ro` when the command only
reads from it.

---

## Taking a backup

### 1. Create a folder and a timestamp

=== "Bash/zsh"

    ```bash
    mkdir -p backups
    stamp=$(date +%Y%m%d-%H%M%S)
    ```

=== "PowerShell"

    ```powershell
    New-Item -ItemType Directory -Force backups | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    ```

`backups/` is excluded by `.gitignore`.

### 2. Stop the application

```
docker compose stop delta
```

The database stays running. Nothing is writing to the database or the uploads
volume now, so the two halves of the backup match.

### 3. Dump the database

```
docker compose exec -T db sh -c 'pg_dump -U $POSTGRES_USER -d $POSTGRES_DB -Fc -f /tmp/delta.dump'
```

No output, and a clean exit. `-Fc` is PostgreSQL's compressed custom format. The
user and database name come from the container, so this is correct whatever you
set `POSTGRES_USER` and `POSTGRES_DB` to.

The dump must be taken in the `db` container. The DELTA container's `pg_dump` is
an older major version and refuses to dump a PostgreSQL 17 server.

### 4. Copy the dump out and check it arrived

```
docker compose cp db:/tmp/delta.dump ./backups/delta-$stamp.dump
```

=== "Bash/zsh"

    ```bash
    ls -l ./backups/delta-$stamp.dump
    ```

=== "PowerShell"

    ```powershell
    Get-ChildItem ./backups/delta-$stamp.dump | Select-Object Name, Length
    ```

The file exists and is not zero bytes. Only then remove the container copy:

```
docker compose exec -T db rm -f /tmp/delta.dump
```

### 5. Copy the uploads out

Uses the [maintenance container](#working-with-the-uploads-volume). `-e DEST=...`
expands in both shells before the command is sent; `$DEST` inside the quoted
string is expanded by the container.

=== "Bash/zsh"

    ```bash
    docker compose run --rm --no-deps --entrypoint sh -e DEST=uploads-$stamp \
      -v "$(pwd)/backups:/backup" delta -c 'mkdir -p /backup/$DEST && cp -a /delta/uploads/. /backup/$DEST/'
    ```

=== "PowerShell"

    ```powershell
    docker compose run --rm --no-deps --entrypoint sh -e DEST=uploads-$stamp -v "$($PWD.Path)\backups:/backup" delta -c 'mkdir -p /backup/$DEST && cp -a /delta/uploads/. /backup/$DEST/'
    ```

`backups/uploads-<stamp>/` now holds the uploaded files — tenant folders such as
`tenant-1`. On a new deployment it may be empty. `cp -a` copies hidden files and
preserves ownership and timestamps.

### 6. Record the image digest

An **image digest** is a fixed identifier for one exact image build, unlike a
tag such as `prod-latest`, which moves. Take it from the deployed container, not
from a tag:

```
docker image inspect $(docker compose images -q delta) --format '{{index .RepoDigests 0}}'
```

A line like `ghcr.io/preventionweb/delta-country@sha256:...`. Save it, and a
copy of `.env`, next to the dump — the schema in this dump belongs to that
version.

If the command returns nothing, the image has no registry digest (it was built
locally rather than pulled). Record how it was produced instead.

### 7. Start the application again

```
docker compose start delta
docker compose ps
```

`delta` returns to `Up ... (healthy)`.

**Skip this step when the backup is part of a restore** — see
[Restoring](#restoring) step 1, where DELTA must stay stopped.

---

## Checking a backup

```
docker compose cp ./backups/delta-$stamp.dump db:/tmp/verify.dump
docker compose exec -T db pg_restore --list /tmp/verify.dump
docker compose exec -T db rm -f /tmp/verify.dump
```

A table of contents listing tables, indexes, constraints and functions. An error
or no output means the file is not a usable dump.

This proves the file is readable, not that the data is complete. The only
complete proof is a restore into a separate deployment — a copy of this folder
with its own `COMPOSE_PROJECT_NAME` and `HTTP_PORT`. Do that once before you
rely on these backups.

---

## Restoring

This section covers the bundled database. If your database is hosted elsewhere,
its restore belongs to whoever operates it — see
[External databases](#external-databases) — but the uploads steps are still
yours.

The steps below are one sequence. Two of them differ depending on your
situation:

- **Empty target** — a rebuilt host, or a separate deployment used to check a
  backup. Nothing existing is overwritten.
- **Rollback** — an existing deployment goes back to an earlier point, in place.
  This overwrites live data, and step 1 applies.

Confirm which deployment you are in before starting: `docker compose ps`.

### 1. Close public access, and protect what you have

Stop the proxy, so nothing is reachable while the data is inconsistent:

```
docker compose stop nginx
docker compose stop delta
```

Patterns C and D have no bundled proxy: **disable the route on your own gateway,
load balancer or WAF now**, and leave it disabled until step 8.

DELTA stays stopped until step 6. Its restart policy would otherwise bring it
back mid-restore and run its migration step against a half-restored schema.

!!! danger "Rollback only: capture the current state before you overwrite it"

    Take a full backup of the current state now. Once step 4 runs, the current
    database is gone and cannot be captured afterwards.

    Work through [Taking a backup](#taking-a-backup) steps 1 and 3–6, using a
    stamp such as `before-rollback-20260916-1400`. Skip step 2 (DELTA is already
    stopped) and **skip step 7**, which would start it again. Also copy `.env`
    aside. Then check the result with [Checking a backup](#checking-a-backup).

    If you cannot produce and verify that set, stop here rather than continuing
    to step 4. A rollback without it cannot be undone.

### 2. Choose the image that matches the backup

Set `DELTA_IMAGE` in `.env` to the digest recorded with the backup you are
restoring:

```
DELTA_IMAGE=ghcr.io/preventionweb/delta-country@sha256:...
```

```
docker compose pull delta
```

DELTA runs its migration step on start, and migrations only go forward.
Starting a newer image against an older restored schema migrates it immediately,
and nothing here can undo that.

### 3. Start the database only

```
docker compose up -d db
docker compose ps
```

`db` reaches `Up ... (healthy)`. DELTA is not running, so no schema is created.

### 4. Restore the database

Copy the dump in and restore it. The database user and name come from the
container, so these are correct whatever you set `POSTGRES_USER` and
`POSTGRES_DB` to:

```
docker compose cp ./backups/delta-20260916-101500.dump db:/tmp/restore.dump
docker compose exec -T db sh -c 'pg_restore -U $POSTGRES_USER -d $POSTGRES_DB --clean --if-exists /tmp/restore.dump'
```

Read the exit status — Bash/zsh `echo $?`, PowerShell `$LASTEXITCODE`.

**Judging the result.** `pg_restore` does not stop at the first problem, so a
non-zero status means there were errors, not that it stopped.

- Exit 0 with no error output: continue to the checks below.
- Any error output: stop and investigate. Do not start DELTA against it.

Errors are not expected here, including extension errors. In this stack
`POSTGRES_USER` is the database superuser — the `postgres` image creates it
"with superuser power" — so the restoring role owns the `postgis` extension and
has the privileges the dump needs. A permission or ownership diagnostic means
something is different about this database, not that it can be ignored.
(Restoring into a database somebody else administers is a different case; see
[External databases](#external-databases).)

**Then check the data arrived.** Structure and rows are separate questions:

```
echo "select version_no from dts_system_info;" | docker compose exec -T db sh -c 'psql -U $POSTGRES_USER -d $POSTGRES_DB --tuples-only --no-align'
echo "select count(*) from pg_tables where schemaname='public';" | docker compose exec -T db sh -c 'psql -U $POSTGRES_USER -d $POSTGRES_DB --tuples-only --no-align'
echo "select count(*) from public.super_admin_users;" | docker compose exec -T db sh -c 'psql -U $POSTGRES_USER -d $POSTGRES_DB --tuples-only --no-align'
```

Expect the schema version recorded with the backup, a table count in the dozens,
and at least one administrator account.

These show the schema is present and readable. They do not show your application
data is complete. If you recorded exact `COUNT(*)` values for tables your
deployment actually uses before the backup, re-run those same counts now and
compare — that comparison is the useful one. Otherwise treat step 7 as the
verdict.

Once satisfied, remove the container copy:

```
docker compose exec -T db rm -f /tmp/restore.dump
```

If the restore failed, leave it. The file in `backups/` is the authoritative
copy and is never deleted during a restore.

### 5. Restore the uploads

DELTA is still stopped. Look at the volume before writing to it:

```
docker compose run --rm --no-deps --entrypoint sh delta -c 'ls -A /delta/uploads'
```

**If nothing is listed** — an empty target — copy the backup straight in.

**If files are listed** — a rollback — empty the directory first. A plain copy
would merge the two states and give you neither. `-mindepth 1` keeps the
directory and removes everything in it, including hidden files:

```
docker compose run --rm --no-deps --entrypoint sh delta -c 'find /delta/uploads -mindepth 1 -delete'
```

This deletes the volume's contents, not the volume. Everything it removes is in
the uploads copy from step 1; do not run it if that copy does not exist.

Then copy the backup in. `-e SRC=...` names the folder inside `backups/`:

=== "Bash/zsh"

    ```bash
    docker compose run --rm --no-deps --entrypoint sh -e SRC=uploads-20260916-101500 \
      -v "$(pwd)/backups:/backup:ro" delta -c 'cp -a /backup/$SRC/. /delta/uploads/'
    ```

=== "PowerShell"

    ```powershell
    docker compose run --rm --no-deps --entrypoint sh -e SRC=uploads-20260916-101500 -v "$($PWD.Path)\backups:/backup:ro" delta -c 'cp -a /backup/$SRC/. /delta/uploads/'
    ```

Check:

```
docker compose run --rm --no-deps --entrypoint sh delta -c 'ls -la /delta/uploads'
```

The tenant folders from the backup, owned by `root`. DELTA runs as root, so root
ownership here is correct.

### 6. Start DELTA

Both halves are restored, so DELTA can start against a consistent set.

```
docker compose up -d delta
```

Use `up -d`, not `start` or `restart`. Those reuse the existing container with
the image it was created from, so the `DELTA_IMAGE` change from step 2 would not
take effect.

Confirm the image actually running, and what the schema step did:

```
docker image inspect $(docker compose images -q delta) --format '{{index .RepoDigests 0}}'
docker compose logs --since 5m delta
docker compose ps
```

Expect the digest from step 2; `Applying upgrade migrations to existing
database...` with no `ERROR`, `FATAL` or `PANIC`; and `delta` healthy.

If the log says `Initializing new database with full schema...`, stop the
container — DELTA found an empty database and is building a new schema over your
restore. Check you restored into the database this deployment connects to.

### 7. Verify, before reopening access

Two separate checks.

#### a. The administrator credential

A restore reinstates whatever the password was when the backup was taken. If the
backup predates the change made at deployment, the account is back to the
password that ships in the public image.

This is checked at the database and needs no browser. Run the verification from
[step 6.2 of the installation guide](index.md#62-replace-the-built-in-administrator-password),
using the password you expect to be current. If it does not return
`admin@admin.com|t`, run the whole of that step now, while access is still
closed.

#### b. The application

This needs a browser. Choose one of the two below.

**Full check over HTTPS, preferred.** This uses the real hostname, the real
certificate and the real proxy, so it validates sign-in and sessions as users
will experience them.

1. In `.env`, bind the proxy to loopback for the moment — `HTTPS_PORT=127.0.0.1:8443`,
   or `HTTP_PORT=127.0.0.1:8080` on a deployment that does not use TLS here.
2. `docker compose up -d nginx`
3. On the machine with the browser, point the deployment's hostname at
   `127.0.0.1` in its hosts file, so the certificate still matches. If the
   server is remote, forward the port first:
   `ssh -L 8443:127.0.0.1:8443 you@the-server`
4. Browse to `https://your.hostname:8443`.
5. Afterwards, restore the original `HTTP_PORT` / `HTTPS_PORT` values.

**Quick check without the proxy.** Reaches DELTA directly over plain HTTP. Good
for confirming the application loads and the data looks right.

1. **Write down the `delta` service's current `ports:` entry**, exactly as it
   appears. Patterns C and D have one — it is the address your gateway connects
   to. Patterns A and B have none.
2. **Replace** that entry with `"127.0.0.1:8080:3000"`. Replace, not add: a
   second, wider mapping would publish DELTA beyond loopback while you work.
3. `docker compose up -d delta`, then browse `http://127.0.0.1:8080` —
   forwarding the port first if the server is remote.
4. Afterwards, **put the original entry back exactly as you wrote it down** (or
   remove it entirely on patterns A and B) and run `docker compose up -d delta`
   again. On patterns C and D this is what restores your gateway's route to the
   backend; skipping it leaves the gateway pointing at a port that no longer
   accepts its traffic.

Sign-in on this path is not something we have tested: `PUBLIC_URL` still names
the production HTTPS address while the browser is on plain HTTP, and how DELTA's
`Secure` session cookies behave in that combination is not established. Treat a
sign-in failure here as inconclusive and confirm on the HTTPS path above.

Either way, check:

- The application loads, and is not the "System configuration errors" page.
- A record you know about is present.
- **An existing uploaded file downloads.** This is the check that proves the
  database and the uploads agree.
- A new upload larger than 1 MB succeeds.
- On the HTTPS path, you sign in and stay signed in.

### 8. Reopen access

```
docker compose up -d
```

Patterns C and D: re-enable the route on your gateway. Then repeat the browser
checks over the real URL.

### If a restore has failed after the database was overwritten

The previous state was replaced and cannot be captured now.

1. Leave the deployment stopped: `docker compose stop delta nginx`.
2. List what you actually hold — the set from step 1, older sets in `backups/`,
   and copies kept off this host.
3. Verify the most recent usable set with
   [Checking a backup](#checking-a-backup).
4. Restore it from step 2 onwards, using the image digest recorded with that
   set.

If no verified set exists, the data is not recoverable from this host.

---

## Consistency between database and uploads

The database records that a file exists; the volume holds the file. Captured at
different moments, the two disagree — records pointing at missing files, or
files nothing refers to.

Stopping `delta` for the duration of the backup is what keeps them together, and
is the only method here that does. It assumes nothing else writes to the
database or the uploads volume meanwhile, which is true of a standard
deployment. The backup takes seconds to a few minutes.

No ordering makes a running backup consistent. Uploads first and database second
means a file uploaded in between is in the dump but missing from disk — the
failure users see. The reverse order trades that for orphaned files. If you
cannot stop the application, you need a real online-backup design: a volume
snapshot taken at one instant, or PostgreSQL continuous archiving paired with a
snapshot of the uploads. That is outside what this deployment provides.

---

## External databases

Patterns B and D have no `db` container, so the database commands here do not
apply to your database.

- Your database is backed up and restored by whoever operates it. Confirm this
  deployment's database is included and that a restore has been tested.
- The uploads volume is yours: step 5 of
  [Taking a backup](#taking-a-backup) and step 5 of
  [Restoring](#restoring) are unchanged.
- The sequencing is yours. Access closed first, DELTA stopped before the
  database restore and kept stopped until the uploads are back, image chosen
  before DELTA is recreated, verification before the route reopens. Your DBA's
  restore happens inside that sequence.
- Recovery spans two owners: their database restore and your uploads copy must
  come from the same point in time. Agree who coordinates it.
- This is the one case where extension ownership errors can be legitimate — a
  non-superuser role cannot adopt extensions it does not own. Ask your DBA which
  diagnostics are expected in their environment.

---

## Storing backups

- Off this host. A backup on the same machine does not survive the machine.
- Treat them as sensitive: a dump contains all application data, and the `.env`
  copy contains every secret in the deployment.
- Keep the image digest with each set.
- Keep enough history to survive a problem nobody notices for a few days.
- Take one before every update — [Update](update.md).
