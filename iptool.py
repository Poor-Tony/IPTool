"""Small Windows TUI for applying preconfigured IPv4 adapter profiles."""

from __future__ import annotations

import configparser
import ctypes
import os
import platform
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path


APP_NAME = "IPTool"
PROFILE_TEMPLATE = """; Copy this file in the same directory and adjust it.
; Every profile file in this directory is shown in IPTool, sorted alphabetically.

[profile]
name = Example static office network
description = Static IPv4 address with DNS servers

[ipv4]
; method can be "static" or "dhcp"
method = static
address = 192.168.10.50
mask = 255.255.255.0
gateway = 192.168.10.1
dns = 1.1.1.1, 8.8.8.8
"""


@dataclass(frozen=True)
class Adapter:
    name: str
    admin_state: str = ""
    state: str = ""
    kind: str = ""


@dataclass(frozen=True)
class Profile:
    path: Path
    display_name: str
    description: str
    method: str
    address: str
    mask: str
    gateway: str
    dns_servers: tuple[str, ...]


def main() -> int:
    clear_screen()
    print_header()

    if not is_windows():
        print("This tool changes Windows network settings via netsh.")
        print("You can still create and inspect profiles on this system.\n")

    config_dir = get_config_dir()
    ensure_config_dir(config_dir)

    adapter = choose_adapter()
    if adapter is None:
        return 0

    while True:
        clear_screen()
        print_header()
        print(f"Adapter: {adapter.name}\n")

        profiles = load_profiles(config_dir)
        choice = choose_profile_or_action(config_dir, profiles)

        if choice == "quit":
            return 0
        if choice == "refresh":
            continue
        if choice == "new":
            create_profile_interactively(config_dir)
            pause()
            continue
        if choice == "folder":
            open_config_folder(config_dir)
            pause()
            continue
        if isinstance(choice, Profile):
            apply_profile_flow(adapter, choice)
            pause()


def print_header() -> None:
    print("IPTool")
    print("======\n")


def clear_screen() -> None:
    os.system("cls" if os.name == "nt" else "clear")


def pause() -> None:
    input("\nPress Enter to continue...")


def is_windows() -> bool:
    return platform.system().lower() == "windows"


def get_config_dir() -> Path:
    if is_windows():
        base = os.environ.get("APPDATA")
        if base:
            return Path(base) / APP_NAME / "profiles"
        return Path.home() / "AppData" / "Roaming" / APP_NAME / "profiles"
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "iptool" / "profiles"


def ensure_config_dir(config_dir: Path) -> None:
    config_dir.mkdir(parents=True, exist_ok=True)
    template_path = config_dir / "template.ini"
    if not template_path.exists():
        template_path.write_text(PROFILE_TEMPLATE, encoding="utf-8")


def choose_adapter() -> Adapter | None:
    adapters = list_adapters()

    while True:
        clear_screen()
        print_header()
        print("Choose adapter\n")

        if adapters:
            for index, adapter in enumerate(adapters, start=1):
                details = ", ".join(part for part in (adapter.admin_state, adapter.state, adapter.kind) if part)
                suffix = f" ({details})" if details else ""
                print(f"{index}. {adapter.name}{suffix}")
        else:
            print("No adapters were detected automatically.")

        print("\nM. Manually enter adapter name")
        print("R. Refresh adapter list")
        print("Q. Quit")

        raw = input("\nSelection: ").strip()
        if not raw:
            continue
        if raw.lower() == "q":
            return None
        if raw.lower() == "r":
            adapters = list_adapters()
            continue
        if raw.lower() == "m":
            name = input("Adapter name: ").strip()
            if name:
                return Adapter(name=name)
            continue
        if raw.isdigit():
            index = int(raw)
            if 1 <= index <= len(adapters):
                return adapters[index - 1]

        print("Invalid selection.")
        pause()


def list_adapters() -> list[Adapter]:
    if not is_windows():
        return []

    result = run_command(["netsh", "interface", "show", "interface"], check=False)
    if result.returncode != 0:
        return []

    adapters: list[Adapter] = []
    for line in result.stdout.splitlines():
        parts = [part.strip() for part in line.split(None, 3)]
        if len(parts) != 4:
            continue
        if parts[0].lower() in {"admin", "---------"}:
            continue
        adapters.append(Adapter(name=parts[3], admin_state=parts[0], state=parts[1], kind=parts[2]))

    return sorted(adapters, key=lambda adapter: adapter.name.lower())


def load_profiles(config_dir: Path) -> list[Profile]:
    profiles: list[Profile] = []
    for path in sorted((item for item in config_dir.iterdir() if item.is_file()), key=lambda item: item.name.lower()):
        try:
            profiles.append(load_profile(path))
        except ValueError as exc:
            print(f"Skipping {path.name}: {exc}")
    return profiles


def load_profile(path: Path) -> Profile:
    parser = configparser.ConfigParser()
    try:
        with path.open("r", encoding="utf-8") as profile_file:
            parser.read_file(profile_file)
    except (OSError, configparser.Error) as exc:
        raise ValueError(str(exc)) from exc

    method = parser.get("ipv4", "method", fallback="").strip().lower()
    if method not in {"static", "dhcp"}:
        raise ValueError("ipv4.method must be static or dhcp")

    address = parser.get("ipv4", "address", fallback="").strip()
    mask = parser.get("ipv4", "mask", fallback="").strip()
    gateway = parser.get("ipv4", "gateway", fallback="").strip()
    dns = tuple(
        server.strip()
        for server in parser.get("ipv4", "dns", fallback="").replace("\n", ",").split(",")
        if server.strip()
    )

    if method == "static" and (not address or not mask):
        raise ValueError("static profiles require ipv4.address and ipv4.mask")

    return Profile(
        path=path,
        display_name=parser.get("profile", "name", fallback=path.stem).strip() or path.stem,
        description=parser.get("profile", "description", fallback="").strip(),
        method=method,
        address=address,
        mask=mask,
        gateway=gateway,
        dns_servers=dns,
    )


def choose_profile_or_action(config_dir: Path, profiles: list[Profile]) -> Profile | str:
    print(f"Config directory: {config_dir}\n")
    print("Profiles\n")

    if profiles:
        for index, profile in enumerate(profiles, start=1):
            description = f" - {profile.description}" if profile.description else ""
            print(f"{index}. {profile.path.name}: {profile.display_name}{description}")
    else:
        print("No valid profile files found.")

    print("\nN. Create profile in TUI")
    print("F. Open config folder")
    print("R. Refresh profiles")
    print("Q. Quit")

    while True:
        raw = input("\nSelection: ").strip()
        if raw.lower() == "q":
            return "quit"
        if raw.lower() == "r":
            return "refresh"
        if raw.lower() == "n":
            return "new"
        if raw.lower() == "f":
            return "folder"
        if raw.isdigit():
            index = int(raw)
            if 1 <= index <= len(profiles):
                return profiles[index - 1]
        print("Invalid selection.")


def create_profile_interactively(config_dir: Path) -> None:
    print("\nCreate profile\n")
    filename = input("File name without extension: ").strip()
    if not filename:
        print("No profile created.")
        return

    safe_name = "".join(char for char in filename if char.isalnum() or char in {"-", "_", " "}).strip()
    if not safe_name:
        print("Profile name contains no usable filename characters.")
        return

    path = config_dir / f"{safe_name}.ini"
    if path.exists():
        print(f"{path.name} already exists.")
        return

    display_name = input("Display name: ").strip() or safe_name
    description = input("Description: ").strip()

    method = ""
    while method not in {"static", "dhcp"}:
        method = input("Method (static/dhcp): ").strip().lower()

    address = mask = gateway = dns = ""
    if method == "static":
        address = input("IPv4 address: ").strip()
        mask = input("Subnet mask: ").strip()
        gateway = input("Gateway (optional): ").strip()
    dns = input("DNS servers, comma-separated (optional): ").strip()

    content = build_profile_content(display_name, description, method, address, mask, gateway, dns)
    path.write_text(content, encoding="utf-8")
    print(f"\nCreated {path}")


def build_profile_content(
    display_name: str,
    description: str,
    method: str,
    address: str,
    mask: str,
    gateway: str,
    dns: str,
) -> str:
    return (
        "[profile]\n"
        f"name = {display_name}\n"
        f"description = {description}\n\n"
        "[ipv4]\n"
        f"method = {method}\n"
        f"address = {address}\n"
        f"mask = {mask}\n"
        f"gateway = {gateway}\n"
        f"dns = {dns}\n"
    )


def open_config_folder(config_dir: Path) -> None:
    print(f"\nConfig directory: {config_dir}")
    if not is_windows():
        print("Open this directory with your file manager to edit profiles externally.")
        return

    try:
        os.startfile(config_dir)  # type: ignore[attr-defined]
        print("Opened config folder.")
    except OSError as exc:
        print(f"Could not open config folder: {exc}")


def apply_profile_flow(adapter: Adapter, profile: Profile) -> None:
    clear_screen()
    print_header()
    print(f"Adapter: {adapter.name}")
    print(f"Profile: {profile.path.name} ({profile.display_name})")
    print(f"Method: {profile.method}")
    if profile.method == "static":
        print(f"Address: {profile.address}")
        print(f"Mask: {profile.mask}")
        print(f"Gateway: {profile.gateway or '(none)'}")
    print(f"DNS: {', '.join(profile.dns_servers) if profile.dns_servers else '(dhcp/default)'}")

    if input("\nApply this profile? (y/N): ").strip().lower() != "y":
        print("Cancelled.")
        return

    if not is_windows():
        print("Cannot apply settings: this system is not Windows.")
        return

    if not is_admin():
        print("Administrator privileges are required to change adapter settings.")
        return

    commands = build_netsh_commands(adapter.name, profile)
    for command in commands:
        result = run_command(command, check=False)
        if result.returncode != 0:
            print(f"\nCommand failed: {' '.join(command)}")
            print(result.stderr.strip() or result.stdout.strip())
            return

    print("\nProfile applied.")


def is_admin() -> bool:
    if not is_windows():
        return False
    try:
        return bool(ctypes.windll.shell32.IsUserAnAdmin())  # type: ignore[attr-defined]
    except OSError:
        return False


def build_netsh_commands(adapter_name: str, profile: Profile) -> list[list[str]]:
    commands: list[list[str]] = []

    if profile.method == "dhcp":
        commands.append(["netsh", "interface", "ipv4", "set", "address", f"name={adapter_name}", "source=dhcp"])
    else:
        commands.append(
            [
                "netsh",
                "interface",
                "ipv4",
                "set",
                "address",
                f"name={adapter_name}",
                "source=static",
                f"address={profile.address}",
                f"mask={profile.mask}",
                f"gateway={profile.gateway or 'none'}",
                "gwmetric=1",
            ]
        )

    if profile.dns_servers:
        primary, *secondary = profile.dns_servers
        commands.append(
            [
                "netsh",
                "interface",
                "ipv4",
                "set",
                "dnsservers",
                f"name={adapter_name}",
                "source=static",
                f"address={primary}",
                "register=primary",
            ]
        )
        for index, server in enumerate(secondary, start=2):
            commands.append(
                [
                    "netsh",
                    "interface",
                    "ipv4",
                    "add",
                    "dnsservers",
                    f"name={adapter_name}",
                    f"address={server}",
                    f"index={index}",
                ]
            )
    else:
        commands.append(["netsh", "interface", "ipv4", "set", "dnsservers", f"name={adapter_name}", "source=dhcp"])

    return commands


def run_command(command: list[str], check: bool) -> subprocess.CompletedProcess[str]:
    executable = shutil.which(command[0])
    if executable is None:
        return subprocess.CompletedProcess(command, 1, "", f"{command[0]} was not found")
    return subprocess.run(
        [executable, *command[1:]],
        check=check,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\nCancelled.")
        raise SystemExit(130)
