[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$ImagePath,
  [int]$DiskNumber = 2,
  [string]$DriveLetter = "E",
  [string]$SshPublicKeyPath = (Join-Path $HOME ".ssh\greylock_radio_ed25519.pub"),
  [switch]$Force
)

$ErrorActionPreference = "Stop"
$ExpectedImageHash = "8a044f4c55feb9b0626ab2060a2eef15c3f57327dd610a0a4cac02cdb959166e"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$TranscriptPath = Join-Path $ProjectRoot "prepare-sd.log"
Start-Transcript -Path $TranscriptPath -Force | Out-Null

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw "Run this script from an Administrator PowerShell window."
}

$disk = Get-Disk -Number $DiskNumber
$partition = Get-Partition -DriveLetter $DriveLetter -ErrorAction SilentlyContinue
if ($partition -and ($partition | Get-Disk).Number -ne $DiskNumber) {
  throw "Drive ${DriveLetter}: no longer belongs to expected disk ${DiskNumber}."
}
if ($disk.IsBoot -or $disk.IsSystem -or $disk.BusType -ne "USB") {
  throw "Refusing to overwrite a boot/system disk or a disk that is not USB."
}
if ($disk.Size -lt 8GB -or $disk.Size -gt 64GB) {
  throw "The target size is outside the expected 8-64 GB SD-card range."
}
if (-not $Force) {
  throw "This erases disk ${DiskNumber} ($([math]::Round($disk.Size / 1GB, 1)) GB). Re-run with -Force."
}

$ImagePath = (Resolve-Path $ImagePath).Path
$actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ImagePath).Hash.ToLowerInvariant()
if ($actualHash -ne $ExpectedImageHash) {
  throw "Image hash mismatch. Expected $ExpectedImageHash but found $actualHash."
}

if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "hardware\tft35a.dtbo"))) {
  throw "The tft35a display overlay is missing."
}
if (-not (Test-Path -LiteralPath $SshPublicKeyPath)) {
  throw "SSH public key not found: $SshPublicKeyPath"
}
$sshPublicKey = (Get-Content -LiteralPath $SshPublicKeyPath -Raw).Trim()
if ($sshPublicKey -notmatch '^ssh-(ed25519|rsa)\s+[A-Za-z0-9+/=]+(?:\s+.*)?$') {
  throw "The SSH public key does not have a supported OpenSSH format."
}

$openssl = "C:\Program Files\Git\usr\bin\openssl.exe"
if (-not (Test-Path -LiteralPath $openssl)) {
  throw "OpenSSL was not found at $openssl."
}
$randomBytes = New-Object byte[] 18
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($randomBytes)
$rng.Dispose()
$adminPassword = [Convert]::ToBase64String($randomBytes).TrimEnd('=')
$passwordHash = (& $openssl passwd -6 $adminPassword).Trim()
if (-not $passwordHash.StartsWith('$6$')) {
  throw "Could not generate the Linux password hash."
}

Write-Host "Erasing USB disk $DiskNumber and writing Raspberry Pi OS..."
Get-Partition -DiskNumber $DiskNumber | Where-Object DriveLetter | ForEach-Object {
  $letter = $_.DriveLetter
  & mountvol.exe "${letter}:\" /p | Out-Null
}

$physicalDrive = "\\.\PhysicalDrive$DiskNumber"
& mountvol.exe /N | Out-Null
try {
  Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false
  Start-Sleep -Seconds 2
  & python (Join-Path $ProjectRoot "tools\write_image.py") $ImagePath $physicalDrive --defer-header 4194304
  if ($LASTEXITCODE -ne 0) {
    throw "Writing the operating-system image failed."
  }
} finally {
  & mountvol.exe /E | Out-Null
}

Update-HostStorageCache
Update-Disk -Number $DiskNumber
Start-Sleep -Seconds 5
$bootPartition = Get-Partition -DiskNumber $DiskNumber | Sort-Object Offset | Select-Object -First 1
if (-not $bootPartition.DriveLetter) {
  Add-PartitionAccessPath -DiskNumber $DiskNumber -PartitionNumber $bootPartition.PartitionNumber -DriveLetter $DriveLetter
  $bootPartition = Get-Partition -DiskNumber $DiskNumber -PartitionNumber $bootPartition.PartitionNumber
}
$bootRoot = "$($bootPartition.DriveLetter):\"

Copy-Item -LiteralPath (Join-Path $ProjectRoot "hardware\tft35a.dtbo") -Destination (Join-Path $bootRoot "overlays\tft35a.dtbo") -Force
$bundleRoot = Join-Path $bootRoot "greylock-radio"
New-Item -ItemType Directory -Path $bundleRoot -Force | Out-Null
foreach ($bundleDirectory in @("app", "config", "systemd", "scripts", "media")) {
  Copy-Item -LiteralPath (Join-Path $ProjectRoot $bundleDirectory) -Destination $bundleRoot -Recurse -Force
}

$configPath = Join-Path $bootRoot "config.txt"
$config = Get-Content -LiteralPath $configPath -Raw
$config = [regex]::Replace($config, '(?m)^(dtoverlay=vc4-kms-v3d.*)$', '#$1')
$displayBlock = @'

# BEGIN GREYLOCK HEADLESS
[all]
dtoverlay=disable-wifi
dtparam=spi=on
dtparam=i2c_arm=on
enable_uart=1
disable_splash=1
# END GREYLOCK HEADLESS
'@
$config = $config.TrimEnd() + $displayBlock + "`n"
Set-Content -LiteralPath $configPath -Value $config -Encoding ascii -NoNewline

function ConvertTo-Base64([string]$Value) {
  return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
}

$firstRunTemplate = Get-Content -LiteralPath (Join-Path $ProjectRoot "scripts\firstrun.template.sh") -Raw
$firstRun = $firstRunTemplate.Replace('__PASSWORD_HASH_B64__', (ConvertTo-Base64 $passwordHash))
$firstRun = $firstRun.Replace('__SSH_PUBLIC_KEY_B64__', (ConvertTo-Base64 $sshPublicKey))
$utf8NoBom = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $bootRoot "firstrun.sh"), $firstRun, $utf8NoBom)

$cmdlinePath = Join-Path $bootRoot "cmdline.txt"
$cmdline = (Get-Content -LiteralPath $cmdlinePath -Raw).Trim() -replace '(?:^|\s)quiet(?=\s|$)', ''
$cmdline = ($cmdline -replace '\s+', ' ').Trim()
$cmdline += " systemd.run=/boot/firmware/firstrun.sh systemd.run_success_action=reboot systemd.unit=kernel-command-line.target"
Set-Content -LiteralPath $cmdlinePath -Value ($cmdline + "`n") -Encoding ascii -NoNewline

New-Item -ItemType File -Path (Join-Path $bootRoot "ssh") -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $bootRoot "userconf.txt"), "radio:$passwordHash`n", $utf8NoBom)

$credentialsPath = Join-Path ([Environment]::GetFolderPath('Desktop')) "Greylock-Radio-Credentials.txt"
$credentials = @"
Greylock Radio Raspberry Pi
Username: radio
Password: $adminPassword
Web: http://greylock-radio.local:8080
SSH: ssh radio@greylock-radio.local
SSH key: $SshPublicKeyPath
Ethernet DHCP: connect the Pi to the router
Direct Ethernet: 192.168.137.2
Wi-Fi: disabled
"@
[IO.File]::WriteAllText($credentialsPath, $credentials, $utf8NoBom)

Write-Host "SD card prepared successfully."
Write-Host "Credentials saved to: $credentialsPath"
Write-Host "Safely eject the card, insert it into the Pi 3B+, and power it on."
Stop-Transcript | Out-Null
