# IPTool

IPTool is a small terminal UI for applying preconfigured IPv4 settings to Windows network adapters.

## Run

```powershell
python iptool.py
```

Changing adapter settings requires an elevated terminal on Windows.

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
