# Talks to a Betaflight flight controller over its USB serial CLI.
#   .\bf.ps1 -Commands 'diff all' -OutFile quad1.txt      read config
#   .\bf.ps1 -Commands (Get-Content base.txt) -Save        apply settings and save
# The FC reboots at the end either way (that is how Betaflight leaves CLI mode).
param(
    [string]$Port,
    [string[]]$Commands = @('status'),
    [string]$OutFile,
    [switch]$Save
)

$ErrorActionPreference = 'Stop'

# Hard limit: this tool changes flight feel only. Anything that could alter switches, channels,
# output pins, receiver or failsafe behaviour is refused before the port is even opened.
$forbidden = '^(defaults|aux|adjrange|rxrange|rxfail|map|resource|serial|feature|servo|smix|mmix|timer|dma|vtx|vtxtable|led|color|flash_erase|msc|bind_rx|bl|escprog)\b' +
             '|^beacon\s+[^-\s]|^beeper\s+(?!-|ALL\s*$)\S' +   # beeps: off by name (-NAME), or the buzzer back on as a whole (beeper ALL); the motor beacon only off
             '|^set\s+(failsafe|pinio|serialrx|rx_|rssi|max_aux|servo|channel_forwarding|gps_rescue|box_user)'
$blocked = @($Commands | ForEach-Object { $_.Trim() } | Where-Object { $_ -match $forbidden })
if ($blocked.Count) { throw "Refused, not a flight-feel setting: $($blocked -join ' | ')" }

if (-not $Port) {
    # Windows can list the same port twice right after the FC reboots
    $ports = @([System.IO.Ports.SerialPort]::GetPortNames() | Select-Object -Unique)
    if ($ports.Count -eq 0) { throw 'No serial port found. Is the drone plugged in by USB?' }
    if ($ports.Count -gt 1) { throw "Several ports found ($($ports -join ', ')). Pass -Port COMx." }
    $Port = $ports[0]
}

$sp = New-Object System.IO.Ports.SerialPort $Port, 115200, 'None', 8, 'One'
$sp.DtrEnable = $true
$sp.RtsEnable = $true
$sp.ReadTimeout = 200
$sp.NewLine = "`n"
try { $sp.Open() }
catch { throw "$Port is busy. Press Disconnect in Betaflight Configurator (the app can stay open), then retry." }

# Read until the line has been quiet for $idleMs
function Read-Reply([int]$idleMs = 600, [int]$maxMs = 30000) {
    $sb = New-Object System.Text.StringBuilder
    $total = [Diagnostics.Stopwatch]::StartNew()
    $idle = [Diagnostics.Stopwatch]::StartNew()
    while ($idle.ElapsedMilliseconds -lt $idleMs -and $total.ElapsedMilliseconds -lt $maxMs) {
        if ($sp.BytesToRead -gt 0) {
            [void]$sb.Append($sp.ReadExisting())
            $idle.Restart()
        } else {
            Start-Sleep -Milliseconds 20
        }
    }
    $sb.ToString()
}

try {
    Start-Sleep -Milliseconds 300
    $sp.DiscardInBuffer()
    $sp.Write('#')
    $banner = Read-Reply
    if ($banner -notmatch 'CLI') { throw "No CLI answer on $Port. Close Betaflight Configurator if it is open, then retry." }

    $log = New-Object System.Text.StringBuilder
    $problems = @()
    foreach ($c in $Commands) {
        $c = $c.Trim()
        if (-not $c -or $c.StartsWith('#') -or $c -eq 'save' -or $c -eq 'exit') { continue }
        $sp.WriteLine($c)
        $idleMs = 600
        if ($c -match '^(diff|dump)') { $idleMs = 1500 }
        $reply = Read-Reply $idleMs
        [void]$log.Append($reply)
        if ($reply -match '(?i)###\s*ERROR|invalid (name|value|argument)|unknown command|parse error|not allowed|out of range') { $problems += $c }
    }

    if ($Save) { $sp.WriteLine('save') } else { $sp.WriteLine('exit') }
    Start-Sleep -Milliseconds 500

    $text = $log.ToString()
    if ($OutFile) { Set-Content -Path $OutFile -Value $text -Encoding utf8 }
    $text
    if ($problems.Count) {
        Write-Output "`n### REJECTED BY THE FC ($($problems.Count)):"
        $problems | ForEach-Object { Write-Output "   $_" }
    }
    if ($Save) { Write-Output "`n### Saved. FC is rebooting." } else { Write-Output "`n### Nothing saved. FC is rebooting." }
}
finally {
    # If a motor command was part of this run, make sure nothing is left spinning
    if ($sp.IsOpen -and ($Commands -match '^\s*motor\s')) { try { $sp.WriteLine('motor 255 1000') } catch {} }
    # The FC is already rebooting here, so the port can vanish under us; that is fine
    try { if ($sp.IsOpen) { $sp.Close() } } catch {}
}
