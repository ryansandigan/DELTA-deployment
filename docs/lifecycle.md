# Day-to-day operation

> **This page assumes the deployment is already in service** - deployed and
> bootstrapped through the [installation guide](../README.md#install-delta), with the built-in
> administrator password already changed and verified.
>
> **Do not use `docker compose up -d` to bring up a deployment for the first
> time.** It starts the proxy and publishes the site while `admin@admin.com`
> still has the password that ships in the public image. First deployment goes
> through the [installation guide](../README.md#install-delta), which starts the application
> privately, fixes that, and publishes afterwards.

Everything here is run from the folder containing `docker-compose.yml`.

Commands act on the whole deployment unless you name a service, for example
`docker compose restart delta`. The service names are `delta`, `db` and `nginx`.

> **Changing the DELTA image or version is not on this page.** It runs a schema
> migration that cannot be undone. Use [update.md](update.md).

**Contents**

- [Status and logs](#status-and-logs)
- [Starting and stopping](#starting-and-stopping)
- [Restart versus applying configuration changes](#restart-versus-applying-configuration-changes)
- [Removing the deployment](#removing-the-deployment)
- [Quick reference](#quick-reference)

---

## Status and logs

### What is running

```
docker compose ps
```

Shows each service, its state and its health. `Up 2 hours (healthy)` is what you
want. `Restarting` means the container keeps exiting - go to the logs.

Add `-a` to include containers that have stopped.

### Recent logs

```
docker compose logs
```

Everything from every service, oldest first. Usually too much - narrow it:

```
docker compose logs delta              # one service
docker compose logs --tail 100 delta   # the last 100 lines
docker compose logs --since 15m        # the last 15 minutes
```

### Follow logs live

```
docker compose logs -f delta
```

Streams new output until you press `Ctrl+C`. Stopping the stream does not affect
the container.

This is the command to run in a second terminal while you start the deployment
or reproduce a problem.

### Where logs actually live

| Stream | Where |
|---|---|
| Application and migration output | `docker compose logs delta` |
| PostgreSQL | `docker compose logs db` |
| nginx access and error | `docker compose logs nginx` |
| DELTA's own rotating log files | Inside the `logs` volume, at `/delta/logs` |

Container logs are capped at 20 MB per service with 5 files kept, so they cannot
fill the disk - but old output is discarded. Do not treat them as an audit
trail.

To read DELTA's own log files:

```
docker compose exec delta ls /delta/logs
docker compose exec delta cat /delta/logs/error-2026-09-16.log
```

---

## Starting and stopping

### Start the deployment

```
docker compose up -d
```

Creates and starts anything not already running. `-d` returns your terminal
immediately.

Safe to run repeatedly: services already running as configured are left alone.
It is also the command that applies configuration changes - see below.

### Stop

```
docker compose stop
```

Stops the containers, keeps them. Nothing is deleted; data is untouched. This is
the right command for planned downtime, host maintenance, or a reboot.

### Start again after a stop

```
docker compose start
```

Starts the same stopped containers. They come back with their existing
configuration - if you changed `.env` while they were stopped, use
`docker compose up -d` instead.

### Restart

```
docker compose restart
docker compose restart nginx
```

Stops and starts the running containers. Useful for a process that has got
itself stuck, and for picking up an edited `nginx/delta.conf`.

> **`restart` does not apply changes to `.env`.** See the next section. This is
> the single most common mistake in operating this deployment.

### Automatic restarts

All three services are set to `restart: unless-stopped`, so Docker restarts them
if they crash and starts them again when the host boots - unless you stopped
them yourself with `docker compose stop`, which is remembered across reboots.

---

## Restart versus applying configuration changes

| You changed | Command | Why |
|---|---|---|
| `.env` | `docker compose up -d` | Environment variables are fixed when a container is created. Compose sees the values differ and **recreates** the container. |
| `docker-compose.yml` | `docker compose up -d` | Same. |
| `nginx/delta.conf` | `docker compose restart nginx` | The file is mounted from disk, so the new content is already in the container - nginx just has to re-read it. |
| Nothing; a service is misbehaving | `docker compose restart <service>` | |

`docker compose restart` stops and starts the *existing* container, with the
environment it was created with. New values in `.env` are simply not there. The
container comes back, everything looks fine, and your change did nothing.

To apply a change to one service only:

```
docker compose up -d delta
```

Recreating `delta` does not touch `db` or `nginx`, and no data is affected - the
volumes are reattached to the new container.

---

## Removing the deployment

### Remove containers, keep data

```
docker compose down
```

Stops and **deletes** the containers and the network. Named volumes are kept, so
the database, uploads and logs all survive. `docker compose up -d` afterwards
brings the deployment back with its data.

`stop` keeps the containers; `down` deletes them. Both keep your data.

### Remove everything, including data

```
docker compose down -v
```

> ## Danger
>
> **`-v` deletes the named volumes: the entire database, every uploaded file,
> and the logs. It cannot be undone, and Docker does not ask for confirmation.**
>
> There is no reason to use it on a deployment you care about. If you are
> clearing out a test deployment, make sure you are in the right directory and
> that `docker compose config --volumes` lists the volumes you expect.
>
> Restoring afterwards is only possible from a backup you already took -
> [backup-restore.md](backup-restore.md).

---

## Quick reference

| Task | Command |
|---|---|
| Status | `docker compose ps` |
| Logs | `docker compose logs --tail 100 delta` |
| Follow logs | `docker compose logs -f delta` |
| Start | `docker compose up -d` |
| Apply `.env` changes | `docker compose up -d` |
| Stop | `docker compose stop` |
| Start after stop | `docker compose start` |
| Restart a service | `docker compose restart nginx` |
| Reload nginx config | `docker compose restart nginx` |
| Remove containers, keep data | `docker compose down` |
| Remove containers **and data** | `docker compose down -v` - see the warning above |
| Shell in a container | `docker compose exec delta sh` |
| Database prompt | `docker compose exec db sh -c 'psql -U $POSTGRES_USER -d $POSTGRES_DB'` |
| Which volumes exist | `docker compose config --volumes` |
| Update DELTA | [update.md](update.md) |
| Back up | [backup-restore.md](backup-restore.md) |
