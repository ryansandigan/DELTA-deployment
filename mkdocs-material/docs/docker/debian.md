# Install Docker on Debian

Docker Engine plus the Compose plugin, from Docker's own repository. Debian is
an officially supported Docker Engine platform. Only the repository setup
differs from [Ubuntu](ubuntu.md).

You need 64-bit Debian 13 (Trixie) or Debian 12 (Bookworm), and `sudo` rights.

Docker's own page is the reference:
<https://docs.docker.com/engine/install/debian/>

> Do not install `docker.io` or `docker-compose` from Debian's archive. They are
> older, packaged differently, and the Compose version may be below what this
> deployment needs.

## 1. Add Docker's repository

```bash
sudo apt update
sudo apt install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
```

**Expected:** `apt update` completes with no error about the Docker repository.

> On Debian **testing**, or a derivative such as Kali Linux, `$VERSION_CODENAME`
> does not name a Docker release. Replace it with the Debian release the system
> is based on — `trixie`, for example.

## 2. Install Docker Engine and the Compose plugin

```bash
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

The package starts and enables Docker for you.

## 3. Run Docker without sudo

```bash
sudo usermod -aG docker $USER
newgrp docker
```

Log out and back in if `docker version` still needs `sudo`.

> Adding a user to the `docker` group grants root-equivalent access to this
> host: <https://docs.docker.com/engine/install/linux-postinstall/>

## 4. Verify

```bash
docker --version
docker compose version
docker run --rm hello-world
```

**Expected:** a Docker version; `Docker Compose version v2.20` or newer; and
*"Hello from Docker!"*.

---

**Docker is ready. Continue to [Install DELTA](../index.md#install-delta).**
