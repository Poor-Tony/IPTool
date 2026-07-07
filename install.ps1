$ErrorActionPreference = "Stop"

$AppName = "IPTool"
$InstallDirectory = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "$AppName\bin"
$SourceDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path

New-Item -Path $InstallDirectory -ItemType Directory -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $SourceDirectory "iptool.ps1") -Destination $InstallDirectory -Force
Copy-Item -LiteralPath (Join-Path $SourceDirectory "iptool.cmd") -Destination $InstallDirectory -Force

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathParts = @()
if ($userPath) {
    $pathParts = @($userPath -split ";" | Where-Object { $_ })
}

$alreadyOnPath = $false
foreach ($part in $pathParts) {
    if ($part.TrimEnd("\") -ieq $InstallDirectory.TrimEnd("\")) {
        $alreadyOnPath = $true
        break
    }
}

if (-not $alreadyOnPath) {
    $newPath = (($pathParts + $InstallDirectory) -join ";")
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
}

Write-Host "Installed IPTool to $InstallDirectory"
if ($alreadyOnPath) {
    Write-Host "The install directory is already on the user PATH."
} else {
    Write-Host "Added the install directory to the user PATH."
    Write-Host "Open a new terminal before running iptool from any directory."
}
