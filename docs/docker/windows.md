# Install Docker on Windows

For **Windows 10/11** and **Windows Server 2022/2025**. DELTA has been tested
with Docker Desktop on Server 2022 and 2025, and works on both; Windows 10/11
use the same steps.

> Docker's published support coverage for Docker Desktop does not include
> Windows Server, so vendor support may not be available for that combination.
> It runs, and DELTA has been tested on it.

You need administrator rights, about 20 GB free on the system volume, and
internet access to `ghcr.io` and `docker.io`.

All commands are **PowerShell, run as administrator**.

## 1. Turn on the Windows features WSL 2 needs

```powershell
Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform | Select-Object State
bcdedit /enum '{current}' | Select-String hypervisorlaunchtype
```

If `State` is `Disabled`:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart
```

If `hypervisorlaunchtype` is `Off`:

```powershell
bcdedit /set hypervisorlaunchtype Auto
```

## 2. Install WSL 2

```powershell
wsl --install --no-distribution
```

No Linux distribution is created — Docker Desktop brings its own.

## 3. Restart

```powershell
Restart-Computer
```

Required: the features above do not take effect until the machine comes back.

## 4. Install Docker Desktop

Download and run the installer from
<https://docs.docker.com/desktop/setup/install/windows-install/>, keeping the
**WSL 2 backend** selected. Restart again if it asks.

## 5. Start Docker Desktop

Launch it and wait for the whale icon to stop animating.

## 6. Verify

```powershell
docker --version
docker compose version
docker info --format '{{.OSType}}'
docker run --rm hello-world
```

**Expected:** a Docker version; `Docker Compose version v2.20` or newer;
`linux`; and *"Hello from Docker!"*.

- `docker compose version` not found but `docker-compose --version` works — you
  have the old v1 tool and need the Compose v2 plugin.
- `docker info` prints `windows` — switch to Linux containers with the tray menu
  or `docker desktop engine use linux`.
- **"Virtualization support not detected"** — see
  [troubleshooting.md](../troubleshooting.md#virtualisation-on-windows).

---

**Docker is ready. Continue to [Install DELTA](../../README.md#install-delta).**
