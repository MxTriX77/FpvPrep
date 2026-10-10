# Mock of the console: the REAL fpv.ps1 and language file, connected to the pretend flight
# controller in simfc.ps1 instead of USB. Nothing is read from or written to any port, and
# settings and copies go to a temporary folder. Because the code is the same, the mock always
# shows exactly what the build next to it does.
#   powershell -ExecutionPolicy Bypass -File mock.ps1 -Lang en
# Expects fpv.ps1 one folder up and simfc.ps1 beside this file (true in tests\ and in a build).
# (the parameter is -Lines, not -Run: dot-sourcing fpv.ps1 below resets its own $Run here)
# -Plain: show nothing that marks it as a mock; the start screen is then the real one's.
param([string]$Lang = 'en', [string]$Lines, [switch]$Plain)

$ErrorActionPreference = 'Stop'
$base = Split-Path $PSScriptRoot
$data = Join-Path $env:TEMP "fpvprep_mock_$PID"
New-Item -ItemType Directory -Force (Join-Path $data 'presets') | Out-Null
Copy-Item (Join-Path $base 'presets\*.txt') (Join-Path $data 'presets')

. (Join-Path $PSScriptRoot 'simfc.ps1')
. (Join-Path $base 'fpv.ps1') -Lang $Lang -DataRoot $data -NoMain

# The drone's health goes round on EVERY status: healthy, with remarks, faulty.
# A named bind gives a new healthy drone and starts the round again.
$script:scenario = 0
function Set-Scenario([int]$n) {
    $f = $script:fc
    $f.volts = 3381; $f.cells = 8; $f.flags = 'CLI'; $f.gyro = 'ICM42688P'; $f.master.acc_calibration = '58,7,-6,1'
    $f.escErr = @(0, 0, 0, 0); $f.rpm = @(1200, 1195, 1188, 1210)
    if ($n -eq 2) { $f.volts = 2960; $f.flags = 'RXLOSS CLI'; $f.master.acc_calibration = '0,0,0,0'; $f.rpm = @(1200, 1195, 950, 1210) }
    if ($n -eq 3) { $f.flags = 'ARMSWITCH THROTTLE CLI'; $f.escErr = @(0, 0, 100, 0); $f.rpm = @(1200, 1195, 0, 1210) }
}
function Next-Drone([string]$name) {
    $id = -join ((1..24) | ForEach-Object { '0123456789abcdef'[(Get-Random -Maximum 16)] })
    $script:fc = New-FC $id "$($name.ToUpper())20"
    # a builder's throttle curve hung from the top, the same in every rate profile
    $script:fc.rates.thr_mid = '100'; $script:fc.rates.thr_expo = '100'; $script:fc.otherThr = @('100', '100')
    $script:scenario = 0
}
$script:fc = New-FC

function Wait-Port([int]$seconds = 15) { return $true }
function Run-BF([string[]]$commands, [bool]$save) { for ($i = 0; $i -lt 7; $i++) { Tick; if ($fancy) { Start-Sleep -Milliseconds 90 } }; return (Sim-FC $commands $save) }
if (-not $fancy) { function Busy([int]$ms) { } }

function Mock-Line([string]$line) {
    $low = $line.ToLower().Trim()
    if ($low -match $script:STR['rx_bind']) {
        $r = Parse-Target $line.Trim().Substring($Matches[0].Length)
        if ($r.name) { Next-Drone $r.name }
    }
    elseif ($low -match $script:STR['rx_status']) { $script:scenario = ($script:scenario % 3) + 1; Set-Scenario $script:scenario }
    Dispatch $line
}

if ($Lines) { foreach ($l in ($Lines -split '\s*;;\s*')) { Mock-Line $l }; return }
Clear-Host
Banner
if ($Plain) {
    Kv (T 'kv_saved') ((Get-ChildItem $presets -Filter '*.txt' | ForEach-Object { if ($_.BaseName -eq '_default') { T 'preset_std' } else { $_.BaseName } }) -join ', ')
} else {
    Bar (T 'mock_bar') 'Yellow'
    Write-Host ('  ' + (T 'mock_note')) -ForegroundColor DarkGray
}
Write-Host ''
Write-Host "$IND$(T 'warn_bf')" -ForegroundColor Yellow
Note (T 'note_help')
Write-Host ''
while ($true) {
    Write-Host '  FPV' -ForegroundColor Cyan -NoNewline
    Write-Host ':\> ' -ForegroundColor Green -NoNewline
    $line = $Host.UI.ReadLine()
    if ($null -eq $line -or $line.Trim() -match $script:STR['rx_exit']) { break }
    Mock-Line $line
}
