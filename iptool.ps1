$ErrorActionPreference = "Stop"

$AppName = "IPTool"
$ProfileTemplate = @"
; Copy this file in the same directory and adjust it.
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
"@

function Clear-IpToolScreen {
    Clear-Host
}

function Write-Header {
    Write-Host "IPTool"
    Write-Host "======"
    Write-Host ""
}

function Pause-IpTool {
    [void](Read-Host "Press Enter to continue")
}

function Get-ProfileDirectory {
    $appData = [Environment]::GetFolderPath("ApplicationData")
    return Join-Path $appData "$AppName\profiles"
}

function Initialize-ProfileDirectory {
    param([string]$ProfileDirectory)

    if (-not (Test-Path -LiteralPath $ProfileDirectory)) {
        New-Item -Path $ProfileDirectory -ItemType Directory -Force | Out-Null
    }

    $templatePath = Join-Path $ProfileDirectory "template.ini"
    if (-not (Test-Path -LiteralPath $templatePath)) {
        Set-Content -LiteralPath $templatePath -Value $ProfileTemplate -Encoding UTF8
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-NetworkAdapters {
    $adapters = @()
    try {
        $lines = & netsh interface show interface 2>$null
        foreach ($line in $lines) {
            if ($line -match "^\s*(?<Admin>\S+)\s+(?<State>\S+)\s+(?<Type>\S+)\s+(?<Name>.+?)\s*$") {
                if ($Matches.Admin -in @("Admin", "---------")) {
                    continue
                }

                $adapters += [pscustomobject]@{
                    Name = $Matches.Name.Trim()
                    AdminState = $Matches.Admin.Trim()
                    State = $Matches.State.Trim()
                    Type = $Matches.Type.Trim()
                }
            }
        }
    } catch {
        return @()
    }

    return @($adapters | Sort-Object -Property Name)
}

function Select-Adapter {
    $adapters = Get-NetworkAdapters

    while ($true) {
        Clear-IpToolScreen
        Write-Header
        Write-Host "Choose adapter"
        Write-Host ""

        if ($adapters.Count -gt 0) {
            for ($i = 0; $i -lt $adapters.Count; $i++) {
                $adapter = $adapters[$i]
                Write-Host ("{0}. {1} ({2}, {3}, {4})" -f ($i + 1), $adapter.Name, $adapter.AdminState, $adapter.State, $adapter.Type)
            }
        } else {
            Write-Host "No adapters were detected automatically."
        }

        Write-Host ""
        Write-Host "M. Manually enter adapter name"
        Write-Host "R. Refresh adapter list"
        Write-Host "Q. Quit"
        Write-Host ""

        $selection = (Read-Host "Selection").Trim()
        if ([string]::IsNullOrWhiteSpace($selection)) {
            continue
        }

        $normalized = $selection.ToLowerInvariant()
        if ($normalized -eq "q") {
            return $null
        }
        if ($normalized -eq "r") {
            $adapters = Get-NetworkAdapters
            continue
        }
        if ($normalized -eq "m") {
            $name = (Read-Host "Adapter name").Trim()
            if ($name) {
                return [pscustomobject]@{ Name = $name }
            }
            continue
        }

        $index = 0
        if ([int]::TryParse($selection, [ref]$index) -and $index -ge 1 -and $index -le $adapters.Count) {
            return $adapters[$index - 1]
        }

        Write-Host "Invalid selection."
        Pause-IpTool
    }
}

function Read-IniFile {
    param([string]$Path)

    $data = @{}
    $section = ""

    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith(";") -or $trimmed.StartsWith("#")) {
            continue
        }

        if ($trimmed -match "^\[(?<Section>[^\]]+)\]$") {
            $section = $Matches.Section.Trim().ToLowerInvariant()
            if (-not $data.ContainsKey($section)) {
                $data[$section] = @{}
            }
            continue
        }

        if ($trimmed -match "^(?<Key>[^=]+?)\s*=\s*(?<Value>.*)$" -and $section) {
            $key = $Matches.Key.Trim().ToLowerInvariant()
            $value = $Matches.Value.Trim()
            $data[$section][$key] = $value
        }
    }

    return $data
}

function Get-IniValue {
    param(
        [hashtable]$Data,
        [string]$Section,
        [string]$Key,
        [string]$Default = ""
    )

    $normalizedSection = $Section.ToLowerInvariant()
    $normalizedKey = $Key.ToLowerInvariant()

    if (-not $Data.ContainsKey($normalizedSection)) {
        return $Default
    }
    if (-not $Data[$normalizedSection].ContainsKey($normalizedKey)) {
        return $Default
    }

    return [string]$Data[$normalizedSection][$normalizedKey]
}

function Get-Profiles {
    param([string]$ProfileDirectory)

    $profiles = @()
    $files = @(Get-ChildItem -LiteralPath $ProfileDirectory -File | Sort-Object -Property Name)

    foreach ($file in $files) {
        try {
            $ini = Read-IniFile -Path $file.FullName
            $method = Get-IniValue -Data $ini -Section "ipv4" -Key "method"
            $method = $method.Trim().ToLowerInvariant()

            if ($method -notin @("static", "dhcp")) {
                Write-Host ("Skipping {0}: ipv4.method must be static or dhcp" -f $file.Name)
                continue
            }

            $address = (Get-IniValue -Data $ini -Section "ipv4" -Key "address").Trim()
            $mask = (Get-IniValue -Data $ini -Section "ipv4" -Key "mask").Trim()
            if ($method -eq "static" -and (-not $address -or -not $mask)) {
                Write-Host ("Skipping {0}: static profiles require ipv4.address and ipv4.mask" -f $file.Name)
                continue
            }

            $displayName = (Get-IniValue -Data $ini -Section "profile" -Key "name").Trim()
            if (-not $displayName) {
                $displayName = [IO.Path]::GetFileNameWithoutExtension($file.Name)
            }

            $dns = @()
            $dnsText = (Get-IniValue -Data $ini -Section "ipv4" -Key "dns").Trim()
            if ($dnsText) {
                $dns = @($dnsText -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            }

            $profiles += [pscustomobject]@{
                Path = $file.FullName
                FileName = $file.Name
                DisplayName = $displayName
                Description = (Get-IniValue -Data $ini -Section "profile" -Key "description").Trim()
                Method = $method
                Address = $address
                Mask = $mask
                Gateway = (Get-IniValue -Data $ini -Section "ipv4" -Key "gateway").Trim()
                DnsServers = $dns
            }
        } catch {
            Write-Host ("Skipping {0}: {1}" -f $file.Name, $_.Exception.Message)
        }
    }

    return $profiles
}

function Select-ProfileOrAction {
    param(
        [string]$ProfileDirectory,
        [array]$Profiles
    )

    Write-Host "Config directory: $ProfileDirectory"
    Write-Host ""
    Write-Host "Profiles"
    Write-Host ""

    if ($Profiles.Count -gt 0) {
        for ($i = 0; $i -lt $Profiles.Count; $i++) {
            $profile = $Profiles[$i]
            $description = ""
            if ($profile.Description) {
                $description = " - $($profile.Description)"
            }
            Write-Host ("{0}. {1}: {2}{3}" -f ($i + 1), $profile.FileName, $profile.DisplayName, $description)
        }
    } else {
        Write-Host "No valid profile files found."
    }

    Write-Host ""
    Write-Host "N. Create profile in TUI"
    Write-Host "F. Open config folder"
    Write-Host "R. Refresh profiles"
    Write-Host "Q. Quit"
    Write-Host ""

    while ($true) {
        $selection = (Read-Host "Selection").Trim()
        switch ($selection.ToLowerInvariant()) {
            "q" { return "quit" }
            "r" { return "refresh" }
            "n" { return "new" }
            "f" { return "folder" }
        }

        $index = 0
        if ([int]::TryParse($selection, [ref]$index) -and $index -ge 1 -and $index -le $Profiles.Count) {
            return $Profiles[$index - 1]
        }

        Write-Host "Invalid selection."
    }
}

function New-ProfileInteractive {
    param([string]$ProfileDirectory)

    Write-Host ""
    Write-Host "Create profile"
    Write-Host ""

    $fileName = (Read-Host "File name without extension").Trim()
    if (-not $fileName) {
        Write-Host "No profile created."
        return
    }

    $safeName = ($fileName -replace "[^A-Za-z0-9 _-]", "").Trim()
    if (-not $safeName) {
        Write-Host "Profile name contains no usable filename characters."
        return
    }

    $path = Join-Path $ProfileDirectory "$safeName.ini"
    if (Test-Path -LiteralPath $path) {
        Write-Host "$safeName.ini already exists."
        return
    }

    $displayName = (Read-Host "Display name").Trim()
    if (-not $displayName) {
        $displayName = $safeName
    }

    $description = (Read-Host "Description").Trim()

    do {
        $method = (Read-Host "Method (static/dhcp)").Trim().ToLowerInvariant()
    } while ($method -notin @("static", "dhcp"))

    $address = ""
    $mask = ""
    $gateway = ""
    if ($method -eq "static") {
        $address = (Read-Host "IPv4 address").Trim()
        $mask = (Read-Host "Subnet mask").Trim()
        $gateway = (Read-Host "Gateway (optional)").Trim()
    }
    $dns = (Read-Host "DNS servers, comma-separated (optional)").Trim()

    $content = @"
[profile]
name = $displayName
description = $description

[ipv4]
method = $method
address = $address
mask = $mask
gateway = $gateway
dns = $dns
"@

    Set-Content -LiteralPath $path -Value $content -Encoding UTF8
    Write-Host ""
    Write-Host "Created $path"
}

function Invoke-Profile {
    param(
        [object]$Adapter,
        [object]$Profile
    )

    Clear-IpToolScreen
    Write-Header
    Write-Host "Adapter: $($Adapter.Name)"
    Write-Host "Profile: $($Profile.FileName) ($($Profile.DisplayName))"
    Write-Host "Method: $($Profile.Method)"

    if ($Profile.Method -eq "static") {
        Write-Host "Address: $($Profile.Address)"
        Write-Host "Mask: $($Profile.Mask)"
        if ($Profile.Gateway) {
            Write-Host "Gateway: $($Profile.Gateway)"
        } else {
            Write-Host "Gateway: (none)"
        }
    }

    if ($Profile.DnsServers.Count -gt 0) {
        Write-Host "DNS: $($Profile.DnsServers -join ', ')"
    } else {
        Write-Host "DNS: (dhcp/default)"
    }

    Write-Host ""
    $confirm = (Read-Host "Apply this profile? (y/N)").Trim().ToLowerInvariant()
    if ($confirm -ne "y") {
        Write-Host "Cancelled."
        return
    }

    if (-not (Test-IsAdministrator)) {
        Write-Host "Administrator privileges are required to change adapter settings."
        return
    }

    $nameArgument = "name=$($Adapter.Name)"

    try {
        if ($Profile.Method -eq "dhcp") {
            & netsh interface ipv4 set address $nameArgument source=dhcp | Out-Host
        } else {
            $gatewayArgument = "gateway=none"
            if ($Profile.Gateway) {
                $gatewayArgument = "gateway=$($Profile.Gateway)"
            }

            & netsh interface ipv4 set address $nameArgument source=static "address=$($Profile.Address)" "mask=$($Profile.Mask)" $gatewayArgument gwmetric=1 | Out-Host
        }

        if ($Profile.DnsServers.Count -gt 0) {
            & netsh interface ipv4 set dnsservers $nameArgument source=static "address=$($Profile.DnsServers[0])" register=primary | Out-Host

            for ($i = 1; $i -lt $Profile.DnsServers.Count; $i++) {
                $index = $i + 1
                & netsh interface ipv4 add dnsservers $nameArgument "address=$($Profile.DnsServers[$i])" "index=$index" | Out-Host
            }
        } else {
            & netsh interface ipv4 set dnsservers $nameArgument source=dhcp | Out-Host
        }

        Write-Host ""
        Write-Host "Profile applied."
    } catch {
        Write-Host ""
        Write-Host "Failed to apply profile: $($_.Exception.Message)"
    }
}

$profileDirectory = Get-ProfileDirectory
Initialize-ProfileDirectory -ProfileDirectory $profileDirectory

$adapter = Select-Adapter
if ($null -eq $adapter) {
    exit 0
}

while ($true) {
    Clear-IpToolScreen
    Write-Header
    Write-Host "Adapter: $($adapter.Name)"
    Write-Host ""

    $profiles = @(Get-Profiles -ProfileDirectory $profileDirectory)
    $choice = Select-ProfileOrAction -ProfileDirectory $profileDirectory -Profiles $profiles

    if ($choice -eq "quit") {
        exit 0
    }
    if ($choice -eq "refresh") {
        continue
    }
    if ($choice -eq "new") {
        New-ProfileInteractive -ProfileDirectory $profileDirectory
        Pause-IpTool
        continue
    }
    if ($choice -eq "folder") {
        Write-Host ""
        Write-Host "Config directory: $profileDirectory"
        Invoke-Item -LiteralPath $profileDirectory
        Pause-IpTool
        continue
    }

    Invoke-Profile -Adapter $adapter -Profile $choice
    Pause-IpTool
}
