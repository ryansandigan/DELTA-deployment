# Install Docker on AlmaLinux

## What is and is not supported

**Docker does not list AlmaLinux as a supported platform.** Docker's
installation index names CentOS, Debian, Fedora, Raspberry Pi OS, RHEL and
Ubuntu, and nothing else.

- AlmaLinux is a RHEL-compatible rebuild, and the procedure below is **Docker's
  RHEL procedure** pointed at Docker's RHEL repository. In practice that is how
  Docker CE is installed on AlmaLinux.
- That is a **community practice, not a vendor-supported path.** If Docker
  support matters to your organisation, use [Ubuntu](ubuntu.md) or
  [Debian](debian.md), which Docker does support, or RHEL proper.
- We have found no AlmaLinux-published Docker CE installation guide to cite, so
  nothing below is presented as AlmaLinux's own recommendation.

> **Podman is not a substitute.** AlmaLinux ships Podman by default, and
> `podman-compose` is not Docker Compose v2. This deployment expects Docker
> Engine and the Compose v2 plugin.

You need AlmaLinux 8, 9 or 10 (matching RHEL 8, 9, 10, which is what Docker's
repository targets), and `sudo` rights.

Docker's RHEL page is the reference for these commands:
<https://docs.docker.com/engine/install/rhel/>

## 1. Remove conflicting packages

AlmaLinux installs Podman and its compatibility shims by default, and they
conflict with Docker Engine.

```bash
sudo dnf remove podman buildah runc containerd
```

**Expected:** the packages are removed, or `dnf` reports there is nothing to
remove. Either is fine.

> If other software on this host uses Podman, stop and reconsider rather than
> removing it. Deploy DELTA on a host not already committed to Podman.

## 2. Add Docker's repository

```bash
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
```

**Expected:** the repository file is written to
`/etc/yum.repos.d/docker-ce.repo`.

> Docker's RHEL repository uses the major version from the host. On AlmaLinux
> this normally resolves correctly. If `dnf` reports no packages found for your
> release, that resolution is what to check first.

## 3. Install Docker Engine and the Compose plugin

```bash
sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

You will be asked to accept Docker's GPG key. Verify the fingerprint is

```
060A 61C5 1B55 8A7F 742B 77AA C52F EB6B 621E 9F35
```

before accepting.

## 4. Start Docker and enable it at boot

Unlike the Debian and Ubuntu packages, this one does not start the service for
you.

```bash
sudo systemctl enable --now docker
systemctl status docker
```

**Expected:** `active (running)`, and `enabled` so it survives a reboot.

## 5. Run Docker without sudo

```bash
sudo usermod -aG docker $USER
newgrp docker
```

Log out and back in if `docker version` still needs `sudo`.

> Adding a user to the `docker` group grants root-equivalent access to this
> host: <https://docs.docker.com/engine/install/linux-postinstall/>

## 6. Verify

```bash
docker --version
docker compose version
docker run --rm hello-world
```

**Expected:** a Docker version; `Docker Compose version v2.20` or newer; and
*"Hello from Docker!"*.

> **SELinux and firewalld are enabled by default.** Docker manages its own
> SELinux labelling for the named volumes this deployment uses, so no `:z` or
> `:Z` mount flags are needed. Firewall rules are covered at the exposure step
> of the [installation guide](../../README.md#allowing-network-access), not here.

---

**Docker is ready. Continue to [Install DELTA](../../README.md#install-delta).**
