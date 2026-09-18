# Install Docker on macOS

Docker Desktop on macOS. Use this to evaluate DELTA or to work on the
configuration; for anything people depend on, deploy on
[Ubuntu](ubuntu.md), [Debian](debian.md) or [AlmaLinux](almalinux.md).

## Before you start: Apple silicon

**The DELTA image is published for `linux/amd64` only.** There is no arm64
build, so on an Apple silicon Mac (M1 and later) it runs under emulation, which
Docker Desktop provides.

- Uncomment `platform: linux/amd64` on the `delta` service in
  `docker-compose.yml`.
- Expect it to be noticeably slower, especially the first start.
- This combination is **untested** — we have no evidence of DELTA running
  correctly under emulation. Treat it as exploratory.
- `postgis/postgis` and `nginx` both publish arm64 images, so only the DELTA
  container is emulated.

On an **Intel** Mac all images are native and no `platform:` line is needed.

Check which you have with `uname -m` — `arm64` for Apple silicon, `x86_64` for
Intel.

You need a supported version of macOS (Docker supports the current release and
the two previous majors) and at least 4 GB of RAM.

## 1. Install Docker Desktop

Download and install from
<https://docs.docker.com/desktop/setup/install/mac-install/>, choosing the build
for your chip.

Docker Desktop requires a paid subscription for organisations above Docker's
published size thresholds — check whether that applies to you.

## 2. Start Docker Desktop

Launch it and wait for the whale icon in the menu bar to stop animating.

## 3. Verify

In **Terminal**:

```bash
docker --version
docker compose version
docker run --rm hello-world
```

**Expected:** a Docker version; `Docker Compose version v2.20` or newer; and
*"Hello from Docker!"*.

If `docker compose version` is not found but `docker-compose --version` works,
you have the old v1 tool and need the Compose v2 plugin.

---

**Docker is ready. Continue to [Install DELTA](../index.md#install-delta).**
