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

$interfaceText = (netsh wlan show interfaces | Out-String)
$ssidMatch = [regex]::Match($interfaceText, '(?m)^\s*SSID\s*:\s*(.+?)\s*$')
if (-not $ssidMatch.Success) {
  throw "Windows is not connected to a Wi-Fi network."
}
$wifiSsid = $ssidMatch.Groups[1].Value.Trim()
$profileText = (netsh wlan show profile name="$wifiSsid" key=clear | Out-String)
$keyMatch = [regex]::Match($profileText, '(?m)^\s*Key Content\s*:\s*(.+?)\s*$')
if (-not $keyMatch.Success) {
  throw "Could not read the saved password for Wi-Fi '$wifiSsid'."
}
$wifiPassword = $keyMatch.Groups[1].Value.Trim()

$existingFirstRun = Get-Content -LiteralPath $firstRunPath -Raw
$passwordHashB64 = Read-EmbeddedBase64 $existingFirstRun "PASSWORD_HASH"

Copy-Item -LiteralPath $overlayPath -Destination (Join-Path $bootRoot "overlays\tft35a.dtbo") -Force

$config = Get-Content -LiteralPath $configPath -Raw
$config = [regex]::Replace($config, '(?m)^(dtoverlay=vc4-kms-v3d.*)$', '#$1')
$config = [regex]::Replace($config, '(?ms)\r?\n?# BEGIN GREYLOCK (?:TFT|HEADLESS).*?# END GREYLOCK (?:TFT|HEADLESS)\r?\n?', "`n")
$displayBlock = @'

# BEGIN GREYLOCK HEADLESS
[all]
dtparam=spi=on
dtparam=i2c_arm=on
enable_uart=1
disable_splash=1
# END GREYLOCK HEADLESS
'@
$config = $config.TrimEnd() + $displayBlock + "`n"
Set-Content -LiteralPath $configPath -Value $config -Encoding ascii -NoNewline

$template = Get-Content -LiteralPath (Join-Path $ProjectRoot "scripts\firstrun.template.sh") -Raw
$firstRun = $template.Replace('__PASSWORD_HASH_B64__', $passwordHashB64)
$firstRun = $firstRun.Replace('__SSH_PUBLIC_KEY_B64__', (ConvertTo-Base64 $sshPublicKey))
$firstRun = $firstRun.Replace('__WIFI_SSID_B64__', (ConvertTo-Base64 $wifiSsid))
$firstRun = $firstRun.Replace('__WIFI_PASSWORD_B64__', (ConvertTo-Base64 $wifiPassword))
$utf8NoBom = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($firstRunPath, $firstRun, $utf8NoBom)

$cmdline = (Get-Content -LiteralPath $cmdlinePath -Raw).Trim()
$cmdline = $cmdline -replace '(?:^|\s)quiet(?=\s|$)', ''
$cmdline = $cmdline -replace '(?:^|\s)fbcon=map:\S+', ''
$cmdline = $cmdline -replace '(?:^|\s)fbcon=font:\S+', ''
$cmdline = ($cmdline -replace '\s+', ' ').Trim()
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
Boot stage: headless; TFT enables after installation
Ethernet DHCP: connect the Pi to the router
Direct Ethernet: radio@192.168.137.2
Wi-Fi: $wifiSsid
"@
[IO.File]::WriteAllText((Join-Path $bootRoot "greylock-repair.txt"), $repairNote, $utf8NoBom)

Write-Host "Drive ${DriveLetter}: repaired without reflashing."
Write-Host "SSH will be available over Wi-Fi or Ethernet during first boot."
