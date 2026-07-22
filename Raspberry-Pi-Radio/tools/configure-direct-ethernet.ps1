[CmdletBinding()]
param(
  [string]$AdapterName = ""
)

$ErrorActionPreference = "Stop"
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw "Run this script from an Administrator PowerShell window."
}

if ($AdapterName) {
  $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction Stop
} else {
  $candidates = @(Get-NetAdapter -Physical | Where-Object {
    $_.InterfaceDescription -notmatch 'Wi-?Fi|Wireless|Bluetooth'
  })
  if ($candidates.Count -ne 1) {
    $names = ($candidates | Select-Object -ExpandProperty Name) -join ', '
    throw "Connect one physical Ethernet adapter and pass -AdapterName. Found: $names"
  }
  $adapter = $candidates[0]
}

$existing = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object IPAddress -eq '192.168.137.1'
if (-not $existing) {
  New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress 192.168.137.1 -PrefixLength 24 | Out-Null
}

Write-Host "Direct Ethernet ready on '$($adapter.Name)'."
Write-Host "Connect the cable and run: ssh greylock-radio-direct"
