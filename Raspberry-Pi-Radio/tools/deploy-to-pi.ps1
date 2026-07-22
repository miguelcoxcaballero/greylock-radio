[CmdletBinding()]
param(
  [string]$SshHost = "greylock-radio"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$remoteRoot = "/tmp/greylock-radio-update-$([DateTimeOffset]::Now.ToUnixTimeSeconds())"

& ssh.exe $SshHost "mkdir -p '$remoteRoot'"
if ($LASTEXITCODE -ne 0) {
  throw "Could not connect to $SshHost."
}

$items = @("app", "config", "systemd", "scripts", "media") | ForEach-Object {
  Join-Path $ProjectRoot $_
}
& scp.exe -r @items "${SshHost}:${remoteRoot}/"
if ($LASTEXITCODE -ne 0) {
  throw "Could not copy the update to $SshHost."
}

$installCommand = "sudo bash '$remoteRoot/scripts/install.sh' && " +
  "sudo bash '$remoteRoot/scripts/install-kiosk.sh' && " +
  "rm -rf '$remoteRoot'"
& ssh.exe $SshHost $installCommand
if ($LASTEXITCODE -ne 0) {
  throw "The remote update did not finish successfully."
}

Write-Host "Greylock Radio was updated on $SshHost without reflashing the SD card."
