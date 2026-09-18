# Updating DELTA

Updating DELTA is not like updating an ordinary container. Read this page first.

---

## What makes this different

**Starting a new DELTA image migrates your database.** The container's own
startup command loads or upgrades the schema before the application starts. You
do not run a migration command; there isn't one. Pulling and starting a new
image *is* the migration.

Three consequences:

1. **`prod-latest` is a moving tag.** If `DELTA_IMAGE` points at a tag rather
   than a digest, any `docker compose pull` followed by `up -d` can pick up a
   new image and migrate your schema at a moment you did not choose, with no
   backup taken.

2. **Migrations only go forward.** There are no down-migrations. Putting the old
   image back does not put the old schema back; the only way back is restoring
   the database from a backup.

3. **A healthy container does not mean the migration worked.** The migration
   step does not stop on error, so it can fail partway while the application
   still starts and reports healthy. Read the output and check the schema
   version yourself.

---

## Pin the image

An **image digest** is a fixed identifier for one exact image build; a tag such
as `prod-latest` moves. Once a deployment is in production, point `DELTA_IMAGE`
at a digest, so a restart or a host reboot cannot pull a different version and
migrate the schema.

Take the digest from the **deployed container**, not from a tag — the local copy
of a tag can be newer than what the container is actually running:

```
docker image inspect $(docker compose images -q delta) --format '{{index .RepoDigests 0}}'
```

Expect something like `ghcr.io/preventionweb/delta-country@sha256:aa180b...`.
If it returns nothing, the image has no registry digest (it was built locally
rather than pulled).

Put that value in `.env`:

```
DELTA_IMAGE=ghcr.io/preventionweb/delta-country@sha256:aa180b...
```

then recreate the container and confirm what it is running:

```
docker compose up -d delta
docker image inspect $(docker compose images -q delta) --format '{{index .RepoDigests 0}}'
```

The digest should match what you set. `up -d` recreates the container, so the
application restarts briefly; the running version is unchanged only if the two
digests agree, which is what this check is for.

### Is there an update available?

Compare the digest behind the moving tag with the one you have pinned. This
downloads nothing:

```
docker buildx imagetools inspect ghcr.io/preventionweb/delta-country:prod-latest --format '{{.Manifest.Digest}}'
```

If `docker buildx` is unavailable, `docker manifest inspect` reports the same
thing in a longer form. If the answer matches your pinned digest, you are
current and there is nothing to do.

---

## The update procedure

### Step 1 - Back up. This is mandatory.

Follow [Backup and Restore](backup-restore.md) and take a full backup: the
database **and** the uploads volume.

Verify it. An unverified backup is not a backup, and because migrations are
forward-only this backup is your **only** route back.

!!! danger "If the backup fails, stop. Do not update."

    You would be starting an irreversible change with no way to undo it.

### Step 2 - Record what you are running now

```
docker compose images
docker image inspect $(docker compose images -q delta) --format '{{index .RepoDigests 0}}'
```

Write the DELTA digest down and keep it with the backup. You need it to
reproduce this exact version later.

Also note the current schema version. The database user and name come from the
container, so this is correct whatever you set `POSTGRES_USER` and
`POSTGRES_DB` to:

=== "Bundled database"

    ```
    echo "select version_no from dts_system_info;" | docker compose exec -T db sh -c 'psql -U $POSTGRES_USER -d $POSTGRES_DB --tuples-only --no-align'
    ```

=== "External database"

    Patterns B and D:

    ```
    echo "select version_no from dts_system_info;" | docker compose exec -T delta sh -c 'set -f; psql $DATABASE_URL --tuples-only --no-align'
    ```

### Step 3 - Choose and pull the new image

Set `DELTA_IMAGE` in `.env` to the digest you intend to deploy, then:

```
docker compose pull delta
```

**Expected result.** The image is downloaded, or reported as already present.
Nothing has changed yet - the running container is still the old one.

### Step 4 - Note the time, then recreate the container

Take a note of the current time. You need it to read only this start's output.

```
docker compose up -d delta
```

**Expected result.** Compose recreates only the `delta` container. `db` and
`nginx` are untouched. The volumes are reattached, so uploads, logs and the
database are unaffected by the recreation itself.

The new container runs the migration and then starts the application.

### Step 5 - Read the migration output

```
docker compose logs --since 10m delta
```

Adjust `--since` so it covers the moment you ran step 4 and nothing earlier.
This matters: the container re-runs its schema step on **every** start, so the
log contains branch messages from previous starts too. Judging the update by an
old line is a real way to miss a failure.

Then read the output as described in
[Reading the migration output](#reading-the-migration-output) below.

### Step 6 - Verify the schema

=== "Bundled database"

    ```
    echo "select version_no from dts_system_info;" | docker compose exec -T db sh -c 'psql -U $POSTGRES_USER -d $POSTGRES_DB --tuples-only --no-align'
    ```

=== "External database"

    Patterns B and D, where there is no `db` container:

    ```
    echo "select version_no from dts_system_info;" | docker compose exec -T delta sh -c 'set -f; psql $DATABASE_URL --tuples-only --no-align'
    ```

**Expected result.** A version number is returned. If the migration introduced a
new schema version, it is higher than the one you recorded in step 2. If the
query fails, the schema is not usable - go to
[If the update fails](#if-the-update-fails).

### Step 7 - Verify the application

```
docker compose ps
```

**Expected result.** Every service `Up` and `(healthy)`.

Then in a browser:

- `PUBLIC_URL` loads, and is **not** the "System configuration errors" page.
- You can sign in, and you stay signed in.
- Existing data is present - open a record you know about.
- An upload larger than 1 MB succeeds.

Only now is the update finished.

---

## Reading the migration output

The schema step is run by `psql`, and its output needs interpreting.

**Find the branch message for this start.** One of:

- `Initializing new database with full schema...` - the database was empty.
  During an *update* this is alarming: it means DELTA found no schema and built
  a new one, which usually means it is pointed at the wrong database or an empty
  volume. Stop and check before anyone writes data into it.
- `Applying upgrade migrations to existing database...` - the normal message for
  an update.

**Then, in the output after that line:**

| Sign | Meaning |
|---|---|
| `ERROR`, `FATAL`, `PANIC` | **Failure.** The schema is in an unknown state. |
| `NOTICE`, `WARNING` | Normal. The schema load produces plenty of these - things like "relation already exists, skipping". Not a problem on their own. |
| Lines beginning `psql:` | **Not a verdict either way.** `psql:` prefixes its ordinary notices as well as its errors. Judge by the severity word, never by this prefix. |

So: scope the output to this start, look at the severity words, and ignore the
prefix. A migration that finished cleanly shows the branch message, some
notices, and no `ERROR`/`FATAL`/`PANIC`.

---

## If the update fails

**Do not simply put the old image back and assume it is over.**

If the migration ran at all, the schema may already have moved forward, and the
old image will run against a schema it does not expect. Image rollback alone is
only safe if you are certain nothing migrated.

**Capture the evidence before changing anything:**

```
docker compose logs --since 30m delta > update-failure.log
```

Then roll back to the backup you took in step 1, following
[Restoring](backup-restore.md#restoring) from the top. It closes public access
first, keeps DELTA stopped until both the database and the uploads are back, and
recreates the container with the **old** digest recorded in step 2 using
`docker compose up -d` - `start` and `restart` would keep running the new image
you are backing out of.

Take its step 1 backup of the current state as well. This state is broken, but
it preserves the evidence and is what you would need if the older backup also
turns out to be unusable.

---

## Do not upgrade PostgreSQL at the same time

`DB_IMAGE` pins PostgreSQL 17 with PostGIS. Leave it alone during an application
update.

**PostgreSQL will not start against a data directory created by a different
major version.** If you change `17` to `18` in `DB_IMAGE` and run
`docker compose up -d`, the new container will refuse to start and report a
version mismatch. Your data is not damaged - but the deployment is down until
you put the old image back.

There is no in-place major upgrade in this deployment. Moving to a new
PostgreSQL major means: back up with `pg_dump`, start a fresh volume on the new
major, restore, verify. That is its own maintenance window, planned separately
from any DELTA update.

Minor updates within the same major - `17.5` to `17.6` - are safe and happen
when the `postgis/postgis:17-3.5` tag is rebuilt. Take a backup first regardless.
