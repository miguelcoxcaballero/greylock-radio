[CmdletBinding()]
param(
  [string]$DriveLetter = "E",
  [string]$SshPublicKeyPath = (Join-Path $HOME ".ssh\greylock_radio_ed25519.pub")
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$bootRoot = "${DriveLetter}:\"
$configPath = Join-Path $bootRoot "config.txt"
$cmdlinePath = Join-Path $bootRoot "cmdline.txt"
$firstRunPath = Join-Path $bootRoot "firstrun.sh"
$overlayPath = Join-Path $ProjectRoot "hardware\tft35a.dtbo"

foreach ($requiredPath in @($configPath, $cmdlinePath, $firstRunPath, $overlayPath, $SshPublicKeyPath)) {
  if (-not (Test-Path -LiteralPath $requiredPath)) {
    throw "Required file not found: $requiredPath"
  }
}
if (-not (Test-Path -LiteralPath (Join-Path $bootRoot "start.elf"))) {
  throw "${DriveLetter}: does not look like a Raspberry Pi boot partition."
}

function ConvertTo-Base64([string]$Value) {
  return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
}

function Read-EmbeddedBase64([string]$Script, [string]$VariableName) {
  $pattern = [regex]::Escape($VariableName) + '="\$\(printf ''%s'' ''([^'']*)'' \| base64 -d\)"'
  $match = [regex]::Match($Script, $pattern)
  if (-not $match.Success) {
    throw "Could not preserve $VariableName from the existing first-run script."
  }
  return $match.Groups[1].Value
}

$sshPublicKey = (Get-Content -LiteralPath $SshPublicKeyPath -Raw).Trim()
if ($sshPublicKey -notmatch '^ssh-(ed25519|rsa)\s+[A-Za-z0-9+/=]+(?:\s+.*)?$') {
  throw "The SSH public key does not have a supported OpenSSH format."
}

$existingFirstRun = Get-Content -LiteralPath $firstRunPath -Raw
$passwordHashB64 = Read-EmbeddedBase64 $existingFirstRun "PASSWORD_HASH"
$wifiSsidB64 = Read-EmbeddedBase64 $existingFirstRun "WIFI_SSID"
$wifiPasswordB64 = Read-EmbeddedBase64 $existingFirstRun "WIFI_PASSWORD"

Copy-Item -LiteralPath $overlayPath -Destination (Join-Path $bootRoot "overlays\tft35a.dtbo") -Force

$config = Get-Content -LiteralPath $configPath -Raw
$config = [regex]::Replace($config, '(?m)^(dtoverlay=vc4-kms-v3d.*)$', '#$1')
$config = [regex]::Replace($config, '(?ms)\r?\n?# BEGIN GREYLOCK TFT.*?# END GREYLOCK TFT\r?\n?', "`n")
$displayBlock = @'

# BEGIN GREYLOCK TFT
[all]
dtparam=spi=on
dtparam=i2c_arm=on
enable_uart=1
dtoverlay=tft35a:rotate=90
hdmi_force_hotplug=1
hdmi_group=2
hdmi_mode=1
hdmi_mode=87
hdmi_cvt=480 320 60 6 0 0 0
hdmi_drive=2
gpu_mem=64
disable_splash=1
# END GREYLOCK TFT
'@
$config = $config.TrimEnd() + $displayBlock + "`n"
Set-Content -LiteralPath $configPath -Value $config -Encoding ascii -NoNewline

$template = Get-Content -LiteralPath (Join-Path $ProjectRoot "scripts\firstrun.template.sh") -Raw
$firstRun = $template.Replace('__PASSWORD_HASH_B64__', $passwordHashB64)
$firstRun = $firstRun.Replace('__WIFI_SSID_B64__', $wifiSsidB64)
$firstRun = $firstRun.Replace('__WIFI_PASSWORD_B64__', $wifiPasswordB64)
$firstRun = $firstRun.Replace('__SSH_PUBLIC_KEY_B64__', (ConvertTo-Base64 $sshPublicKey))
$utf8NoBom = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($firstRunPath, $firstRun, $utf8NoBom)

$cmdline = (Get-Content -LiteralPath $cmdlinePath -Raw).Trim()
$cmdline = $cmdline -replace '(?:^|\s)quiet(?=\s|$)', ''
$cmdline = $cmdline -replace '(?:^|\s)fbcon=map:\S+', ''
$cmdline = $cmdline -replace '(?:^|\s)fbcon=font:\S+', ''
$cmdline = ($cmdline -replace '\s+', ' ').Trim()
$cmdline += " fbcon=map:10 fbcon=font:ProFont6x11"
Set-Content -LiteralPath $cmdlinePath -Value ($cmdline + "`n") -Encoding ascii -NoNewline

$passwordHash = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($passwordHashB64))
[IO.File]::WriteAllText((Join-Path $bootRoot "userconf.txt"), "radio:$passwordHash`n", $utf8NoBom)
New-Item -ItemType File -Path (Join-Path $bootRoot "ssh") -Force | Out-Null

$bundleRoot = Join-Path $bootRoot "greylock-radio"
New-Item -ItemType Directory -Path $bundleRoot -Force | Out-Null
foreach ($bundleDirectory in @("app", "config", "systemd", "scripts", "media")) {
  Copy-Item -LiteralPath (Join-Path $ProjectRoot $bundleDirectory) -Destination $bundleRoot -Recurse -Force
}

$repairNote = @"
Greylock Radio SD recovery applied: $(Get-Date -Format o)
Display: SuziePi/GoodTFT LCD35, ILI9486 + ADS7846, 480x320, rotation 90
SSH: radio@greylock-radio.local
"@
[IO.File]::WriteAllText((Join-Path $bootRoot "greylock-repair.txt"), $repairNote, $utf8NoBom)

Write-Host "Drive ${DriveLetter}: repaired without reflashing."
Write-Host "SSH will be available as radio@greylock-radio.local after first boot finishes."
