# IPTool

IPTool is a small terminal UI for applying preconfigured IPv4 settings to Windows network adapters.

It does not install Python and does not need Python.

## Run

No Python installation is required. IPTool is implemented as a PowerShell script for Windows.

From this repository:

```powershell
.\iptool.cmd
```

Changing adapter settings requires an elevated terminal on Windows.

## Install

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

The installer copies `iptool.ps1` and `iptool.cmd` to:

```text
%LOCALAPPDATA%\IPTool\bin
```

It then adds that directory to the current user's `PATH`. Open a new terminal after installation, then run IPTool from any working directory with:

```powershell
iptool
```

## How it works

On startup, IPTool first asks which adapter should be changed. It then loads every file in its profile config directory and lists valid profiles alphabetically by filename.

The profile directory is:

```text
%APPDATA%\IPTool\profiles
```

On first run, IPTool creates `template.ini` in that directory. Copy the template, rename it, and adjust the values externally, or use the `Create profile in TUI` menu action.

## Profile format

```ini
[profile]
name = Office static IP
description = Desk network

[ipv4]
method = static
address = 192.168.10.50
mask = 255.255.255.0
gateway = 192.168.10.1
dns = 1.1.1.1, 8.8.8.8
```

For DHCP, use:

```ini
[profile]
name = DHCP
description = Automatic address and DNS

[ipv4]
method = dhcp
address =
mask =
gateway =
dns =
```

## Notes

- IPTool uses Windows `netsh` commands under the hood.
- Only IPv4 profiles are supported.
- Invalid profile files are skipped and reported in the profile screen.
