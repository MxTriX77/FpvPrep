# FPV PREP console engine. Started by FPV.cmd.
#   bind "NAME"                 find the drone on USB and show what it is. Writes nothing.
#   status                      full check: health and rates. Writes nothing.
#   motors [-N]                 motor check, N seconds
#   set controls / set sound    write the type's saved stick settings / switch beeps off
#   set name X                  change the name the drone shows on its OSD
#   set sticks on|off           show or hide the stick pictures on the OSD
#   yaw more, pitch roll less   adjust the bound drone; the change is remembered for the type
# All text and command words come from lang\<Lang>.ps1; this file holds only the logic.
# Every exchange with the drone goes through bf.ps1, which refuses anything about switches,
# channels, receiver, failsafe or pins before the port is opened.
param(
    [string]$Lang = 'en',
    [string]$Run,
    [string]$DataRoot,      # where presets\ and quads\ live; defaults to this folder
    [switch]$NoMain         # define everything but do not start: used by tests\sim.ps1
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (-not $DataRoot) { $DataRoot = $root }
$bf = Join-Path $root 'bf.ps1'
$quads = Join-Path $DataRoot 'quads'
$presets = Join-Path $DataRoot 'presets'
foreach ($dir in $quads, $presets) { if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null } }

$script:STR = & (Join-Path $root "lang\$Lang.ps1")
function T([string]$key) {
    $s = $script:STR[$key]
    if ($null -eq $s) { return "<$key>" }
    if ($args.Count) { return ($s -f $args) }
    return $s
}

$WIDTH = 72
$fancy = -not [Console]::IsOutputRedirected
if (-not $fancy) { [Console]::OutputEncoding = [Text.Encoding]::UTF8 }

# ---------------------------------------------------------------- screen
# Glyphs are built from code points so this file stays plain ASCII.
$LIT = [string][char]0x2593; $SHD = [string][char]0x2591; $BLK = [string][char]0x2588
$TEE = [string][char]0x251C + [string][char]0x2500
$IND = ' ' * 5       # sub-lines sit under the step text
$script:pending = $false; $script:col = 62; $script:frame = 0
$script:cur = $null       # the drone bound in this window: id, name, craft
$script:motorLog = ''

# A step line stays open while its work runs; the next thing printed closes it with a mark
function Close-Pending([string]$status = 'OK') {
    if (-not $script:pending) { return }
    $script:pending = $false
    $color = @{ OK = 'Green'; WARN = 'Yellow'; FAIL = 'Red' }[$status]
    $text = @{ OK = (T 'st_ok'); WARN = (T 'st_warn'); FAIL = (T 'st_fail') }[$status]
    if ($fancy) { [Console]::CursorLeft = $script:col; Write-Host (' ' * 9) -NoNewline; [Console]::CursorLeft = $script:col }
    Write-Host ' [' -ForegroundColor DarkGray -NoNewline
    Write-Host $text -ForegroundColor $color -NoNewline
    Write-Host ']' -ForegroundColor DarkGray
}
function Tick {
    if (-not ($fancy -and $script:pending)) { return }
    $w = 6; $p = $script:frame % (2 * $w - 2); if ($p -ge $w) { $p = 2 * $w - 2 - $p }; $script:frame++
    $s = ''; for ($k = 0; $k -lt $w; $k++) { if ($k -eq $p) { $s += $LIT } else { $s += $SHD } }
    [Console]::CursorLeft = $script:col
    Write-Host " [$s]" -ForegroundColor Cyan -NoNewline
}
function Busy([int]$ms) {
    if (-not $fancy) { Start-Sleep -Milliseconds $ms; return }
    for ($t = 0; $t -lt $ms; $t += 90) { Tick; Start-Sleep -Milliseconds 90 }
}
function Type-Out([string]$t, [string]$color) {
    if (-not $fancy) { Write-Host $t -ForegroundColor $color -NoNewline; return }
    for ($k = 0; $k -lt $t.Length; $k += 4) { Write-Host $t.Substring($k, [Math]::Min(4, $t.Length - $k)) -ForegroundColor $color -NoNewline; Start-Sleep -Milliseconds 8 }
}
function Step([string]$t, [switch]$Plain) {
    Close-Pending
    Write-Host '  >> ' -ForegroundColor Cyan -NoNewline
    Type-Out $t 'White'
    if ($Plain) { Write-Host ''; return }
    $d = $script:col - 5 - $t.Length - 1; if ($d -lt 2) { $d = 2 }
    Write-Host (' ' + ('.' * $d)) -ForegroundColor DarkGray -NoNewline
    if ($fancy) { $script:col = [Console]::CursorLeft }
    $script:pending = $true
}
function Item([string]$t) { Close-Pending; Write-Host "$IND$TEE " -ForegroundColor DarkCyan -NoNewline; Write-Host $t -ForegroundColor Gray }
function Ok([string]$t)   { Close-Pending; Write-Host "$IND[+] $t" -ForegroundColor Green }
function Note([string]$t) { Close-Pending; Write-Host "$IND[i] $t" -ForegroundColor DarkGray }
function Warn([string]$t) { Close-Pending 'WARN'; Write-Host "$IND[!] $t" -ForegroundColor Yellow }
function Fail([string]$t) { Close-Pending 'FAIL'; Write-Host "$IND[x] $t" -ForegroundColor Red }
function Kv([string]$l, [string]$r, [string]$color = 'Cyan') {
    Close-Pending
    $d = $WIDTH - $IND.Length - $l.Length - $r.Length - 2; if ($d -lt 2) { $d = 2 }
    Write-Host "$IND$l " -ForegroundColor Gray -NoNewline
    Write-Host ('.' * $d) -ForegroundColor DarkGray -NoNewline
    Write-Host " $r" -ForegroundColor $color
}
# Everything healthy is packed tight: label grey, value green, about four to a line
function Chips([string[]]$pairs) {
    Close-Pending
    if ($pairs.Count -eq 0) { return }
    $x = 0; Write-Host $IND -NoNewline
    for ($i = 0; $i -lt $pairs.Count; $i += 2) {
        $len = $pairs[$i].Length + 1 + $pairs[$i + 1].Length + 3
        if ($x + $len - 3 -gt ($WIDTH - $IND.Length + 3) -and $x -gt 0) { Write-Host ''; Write-Host $IND -NoNewline; $x = 0 }
        Write-Host "$($pairs[$i]) " -ForegroundColor Gray -NoNewline
        Write-Host "$($pairs[$i + 1])   " -ForegroundColor Green -NoNewline
        $x += $len
    }
    Write-Host ''
}
function Bar([string]$text, [string]$bg) {
    Close-Pending
    $t = "  $text"; if ($t.Length -lt $WIDTH) { $t = $t + (' ' * ($WIDTH - $t.Length)) }
    Write-Host '  ' -NoNewline; Write-Host $t -ForegroundColor Black -BackgroundColor $bg
}
function Rule([string]$label) { Close-Pending; Write-Host ''; Bar $label 'DarkCyan' }
function Read-Answer { return $Host.UI.ReadLine() }
function Ask([string]$q) {
    Close-Pending
    Write-Host "$IND[?] $q $(T 'yn') " -ForegroundColor Yellow -NoNewline
    return "$(Read-Answer)" -match (T 'yes_rx')
}
function Took($clock) { return ((T 'sec') -f $clock.Elapsed.TotalSeconds) }

# ---------------------------------------------------------------- verdict
# Severity everywhere: 0 fine, 1 remarks, 2 do not fly.
function Verdict([int]$sev, [string]$who, [string]$good, $clock) {
    Write-Host ''
    if ($sev -ge 2) { Bar (T 'v_fail' $who (Took $clock)) 'Red' }
    elseif ($sev -eq 1) { Bar (T 'v_warn' $who (Took $clock)) 'Yellow' }
    else { Bar (T 'v_good' $who $good (Took $clock)) 'Green' }
}
function Log([string]$t) {
    Add-Content -Path (Join-Path $quads 'log.txt') -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $t) -Encoding utf8
}

# bf.ps1 speaks English; its errors are mapped to the console's language here
function Local-Error([string]$m) {
    foreach ($e in $script:STR['errors']) { if ($m -match $e[0]) { return ($e[1] -f $m) } }
    return $m
}

# ---------------------------------------------------------------- drone I/O
function Wait-Port([int]$seconds = 15) {
    for ($i = 0; $i -lt $seconds * 10; $i++) {
        if ([System.IO.Ports.SerialPort]::GetPortNames().Count -gt 0) { return $true }
        Tick; Start-Sleep -Milliseconds 100
    }
    return $false
}

# bf.ps1 runs on a second thread so the scanner on the open step line keeps moving
function Run-BF([string[]]$commands, [bool]$save) {
    $ps = [powershell]::Create()
    try {
        [void]$ps.AddCommand($bf).AddParameter('Commands', $commands)
        if ($save) { [void]$ps.AddParameter('Save', $true) }
        $h = $ps.BeginInvoke()
        while (-not $h.IsCompleted) { Tick; Start-Sleep -Milliseconds 90 }
        $res = $ps.EndInvoke($h)
        if ($ps.Streams.Error.Count) { throw $ps.Streams.Error[0].Exception }
        return ($res | ForEach-Object { "$_" }) -join "`n"
    } finally { $ps.Dispose() }
}

# One bf.ps1 session. Every session ends with the drone restarting, so wait for it first.
function Talk([string[]]$commands, [switch]$Save, [switch]$AfterReboot) {
    if ($AfterReboot) { Busy 2000 }
    if (-not (Wait-Port 15)) { throw 'No drone on USB.' }
    if ($AfterReboot) { Busy 3000 }
    for ($try = 1; $try -le 6; $try++) {
        try { return (Run-BF $commands ([bool]$Save)) }
        catch {
            if ("$($_.Exception.Message) $($_.Exception.InnerException.Message)" -notmatch 'busy|No serial|not functioning|port is closed') { throw }
            if ($try -eq 6) { throw }
            Busy 2000
        }
    }
}

function Lines([string]$text) { $text -split "`r?`n" | ForEach-Object { $_.Trim() } }

# Reads the drone in one session:
#   status, dshot_telemetry_info   health facts (only with -Health)
#   diff all                       what goes to disk, plus id, name, firmware
#   dump                           the real current values, including ones still at firmware
#                                  default, which diff does not list
# Values come from the active PID profile and the active rate profile.
function Read-Drone([switch]$AfterReboot, [switch]$Health) {
    $cmds = @('diff all', 'dump'); if ($Health) { $cmds = @('status', 'dshot_telemetry_info') + $cmds }
    $raw = Talk $cmds -AfterReboot:$AfterReboot
    $all = @($raw -split "`r?`n")
    $iDiff = -1; $iDump = -1
    for ($i = 0; $i -lt $all.Count; $i++) {
        if ($iDiff -lt 0 -and $all[$i] -match '^(#\s*)?diff all\s*$') { $iDiff = $i }
        if ($all[$i] -match '^(#\s*)?dump\s*$') { $iDump = $i }
    }
    if ($iDiff -lt 0) { $iDiff = 0 }
    $head = ''; if ($iDiff -gt 0) { $head = ($all[0..($iDiff - 1)] -join "`n") }
    $diff = $raw; $dump = @()
    if ($iDump -gt $iDiff) { $diff = ($all[$iDiff..($iDump - 1)] -join "`n"); $dump = $all[$iDump..($all.Count - 1)] }

    $master = @{}; $prof = @{}; $rate = @{}; $sec = 'm'; $n = '0'; $actP = $null; $actR = $null; $restore = ''
    foreach ($l in $dump) {
        $l = $l.Trim()
        if ($l -match '^# restore original (rate)?profile') { $restore = 'p'; if ($Matches[1]) { $restore = 'r' }; continue }
        if ($l -match '^profile (\d+)$') { if ($restore -eq 'p') { $actP = $Matches[1]; $restore = '' } else { $sec = 'p'; $n = $Matches[1]; if (-not $prof[$n]) { $prof[$n] = @{} } }; continue }
        if ($l -match '^rateprofile (\d+)$') { if ($restore -eq 'r') { $actR = $Matches[1]; $restore = '' } else { $sec = 'r'; $n = $Matches[1]; if (-not $rate[$n]) { $rate[$n] = @{} } }; continue }
        if ($l -match '^set (\w+) = (.*)$') {
            if ($sec -eq 'm') { $master[$Matches[1]] = $Matches[2].Trim() }
            elseif ($sec -eq 'p') { $prof[$n][$Matches[1]] = $Matches[2].Trim() }
            else { $rate[$n][$Matches[1]] = $Matches[2].Trim() }
        }
    }
    if ($null -eq $actP) { $actP = @($prof.Keys | Sort-Object)[0] }
    if ($null -eq $actR) { $actR = @($rate.Keys | Sort-Object)[0] }
    $vals = @{}
    foreach ($k in $master.Keys) { $vals[$k] = $master[$k] }
    if ($actP -and $prof[$actP]) { foreach ($k in $prof[$actP].Keys) { $vals[$k] = $prof[$actP][$k] } }
    if ($actR -and $rate[$actR]) { foreach ($k in $rate[$actR].Keys) { $vals[$k] = $rate[$actR][$k] } }

    # The throttle curve of every OTHER rate profile, from the diff (a value it does not list is the
    # firmware default: mid 50, expo 0). Used to recover a curve an old version of this tool overwrote
    # in the active profile.
    $thr = @{}; $rp = $null; $actDiff = '0'; $restoring = $false
    foreach ($line in ($diff -split "`r?`n")) {
        $line = $line.Trim()
        if ($line -match '^# restore original rateprofile') { $restoring = $true; continue }
        if ($line -match '^rateprofile (\d+)$') {
            if ($restoring) { $actDiff = $Matches[1]; $restoring = $false; $rp = $null } else { $rp = $Matches[1]; $thr[$rp] = @{ mid = '50'; expo = '0' } }
            continue
        }
        if ($rp -and $line -match '^set thr_mid = (\d+)') { $thr[$rp].mid = $Matches[1] }
        if ($rp -and $line -match '^set thr_expo = (\d+)') { $thr[$rp].expo = $Matches[1] }
    }
    $otherThr = @($thr.Keys | Where-Object { $_ -ne $actDiff } | ForEach-Object { "$($thr[$_].mid)/$($thr[$_].expo)" } | Sort-Object -Unique)

    return @{
        head  = $head; diff = $diff; vals = $vals; otherThr = $otherThr
        id    = ([regex]::Match($diff, 'mcu_id (\w{8})')).Groups[1].Value
        craft = ([regex]::Match($diff, 'craft_name = (\S+)')).Groups[1].Value
        fw    = ([regex]::Match($diff, 'Betaflight / \S+ \(\S+\) (\S+)')).Groups[1].Value
    }
}

# ---------------------------------------------------------------- saved settings
# presets\<NAME>.txt holds a quad type's settings; presets\drones\<id>.txt one drone's tweaks.
# Both are lines of "set key = value".
function Read-Settings([string]$file) {
    $h = [ordered]@{}
    if (Test-Path $file) { foreach ($l in (Get-Content $file -Encoding UTF8)) { if ($l -match '^\s*set (\w+) = (.+?)\s*$') { $h[$Matches[1]] = $Matches[2] } } }
    return $h
}
function Write-Settings([string]$file, $add, [string[]]$header) {
    $cur = @($header); if (Test-Path $file) { $cur = @(Get-Content $file -Encoding UTF8) }
    $cur = @($cur | Where-Object { -not ($_ -match '^\s*set (\w+) = ' -and $add.Contains($Matches[1])) })
    Set-Content $file ($cur + @($add.Keys | ForEach-Object { "set $_ = $($add[$_])" })) -Encoding utf8
}
function Pairs($h) { return (($h.Keys | ForEach-Object { "$_=$($h[$_])" }) -join '; ') }
function Save-Preset([string]$name, $add) {
    $h = @("# Saved settings for '$name'. Created by FPV PREP on $(Get-Date -Format 'yyyy-MM-dd').")
    $file = Join-Path $presets "$name.txt"
    if (-not (Test-Path $file)) {
        # a new type starts from the standard set, so its file is complete on its own
        $all = Read-Settings $stdFile; foreach ($k in $add.Keys) { $all[$k] = $add[$k] }; $add = $all
    }
    Write-Settings $file $add $h
    Log "$name preset updated: $(Pairs $add)"
}
# What this drone should have: its type's settings with its own tweaks on top. A type with no
# file of its own gets the standard set (presets\_default.txt), flagged as std.
$stdFile = Join-Path $presets '_default.txt'
function Wanted([string]$name, [string]$id) {
    $want = [ordered]@{}
    $src = Join-Path $presets "$name.txt"
    $std = (-not (Test-Path $src)) -and (Test-Path $stdFile)
    if ($std) { $src = $stdFile }
    $p = Read-Settings $src; foreach ($k in $p.Keys) { $want[$k] = $p[$k] }
    $o = Read-Settings (Join-Path $presets "drones\$id.txt"); foreach ($k in $o.Keys) { $want[$k] = $o[$k] }
    return @{ want = $want; own = $o; hasPreset = (Test-Path $src); std = $std }
}
# A confirmed change always becomes part of the type's saved settings: no question asked
function Remember([string]$name, $add) {
    Save-Preset $name $add
    Ok (T 'ok_remembered' $name.ToUpper())
}
# Writes a set of values (plus extra raw commands), then reads back. True when all are in.
function Write-And-Verify([string]$name, [string]$id, $set, [string[]]$more) {
    $cmds = @($set.Keys | ForEach-Object { "set $_ = $($set[$_])" }) + @($more)
    Step (T 's_write')
    $out = Talk $cmds -Save -AfterReboot
    if ($out -match 'REJECTED') {
        Fail (T 'f_rejected')
        (Lines $out) | Where-Object { $_ -match '^(set|beeper|beacon) ' } | Select-Object -Last 5 | ForEach-Object { Item $_ }
        Log "$name $id REJECTED"; return $false
    }
    Step (T 's_verify')
    $after = Read-Drone -AfterReboot
    Set-Content (Join-Path $quads "$(Get-Date -Format 'yyyy-MM-dd')_${name}_${id}_after.txt") $after.diff -Encoding utf8
    $missing = @($set.Keys | Where-Object { "$($after.vals[$_])" -ne "$($set[$_])" })
    if ($missing.Count) { Fail (T 'f_missing' $missing.Count); $missing | ForEach-Object { Item (T 'i_missing' $_ $set[$_] $after.vals[$_]) }; return $false }
    if ($set.Count) { Ok (T 'ok_confirmed' $set.Count) }
    if ($more -match '^beeper') {
        $wantOff = [bool]($more -match '^beeper -'); $isOff = [bool]((Lines $after.diff) -match '^beeper -')
        if ($wantOff -ne $isOff) { Warn (T 'w_snd_unconf') } elseif ($isOff) { Ok (T 'ok_snd') } else { Ok (T 'ok_snd_on') }
    }
    return $true
}

# ---------------------------------------------------------------- health check
# Reads only what the same session already fetched: the "status" block, the ESC telemetry
# table with motors at rest, and the config values. Returns the severity.
function Health($d) {
    Step (T 'h_step')
    $h = $d.head; $chips = @(); $sev = 0
    $problems = @()   # each: severity, line to print

    $gyro = ([regex]::Match($h, 'GYRO=(\w+)')).Groups[1].Value
    $acc = ([regex]::Match($h, 'ACC=(\w+)')).Groups[1].Value
    if (-not $gyro -or $gyro -eq 'NONE') { $problems += , @(2, (T 'h_nogyro')) }
    elseif (-not $acc -or $acc -eq 'NONE') { $problems += , @(1, (T 'h_noacc')) }
    elseif ("$($d.vals['acc_calibration'])" -match ',0$') { $problems += , @(1, (T 'h_acc_uncal')) }
    else { $chips += (T 'chip_sensors'), (T 'chip_ok') }

    if ($h -match 'CPU:(\d+)%') { if ([int]$Matches[1] -gt 75) { $problems += , @(1, (T 'h_cpu' $Matches[1])) } else { $chips += (T 'chip_cpu'), "$($Matches[1])%" } }
    if ($h -match 'I2C Errors: (\d+)' -and [int]$Matches[1] -gt 0) { $problems += , @(1, (T 'h_i2c' $Matches[1])) }
    if ($h -match 'Core temp=(\d+)' -and [int]$Matches[1] -gt 85) { $problems += , @(1, (T 'h_temp' $Matches[1])) }

    $hasBatt = $false
    if ($h -match 'Voltage: (\d+) \* 0\.01V \((\d+)S battery') {
        $cells = [int]$Matches[2]; $volts = [int]$Matches[1] / 100
        if ($cells -gt 0 -and $volts -gt 5) {
            $hasBatt = $true; $per = $volts / $cells; $perTxt = $per.ToString('0.00', [Globalization.CultureInfo]::InvariantCulture)
            if ($per -lt 3.3) { $problems += , @(2, (T 'h_batt_crit' $cells $perTxt)) }
            elseif ($per -lt 4.05) { $problems += , @(1, (T 'h_batt_low' $cells $perTxt)) }
            else { $chips += (T 'chip_batt'), "${cells}S $perTxt $(T 'unit_v')" }
        }
    }
    if (-not $hasBatt) { $problems += , @(1, (T 'h_nobatt')) }

    $flags = @(); if ($h -match 'Arming disable flags:\s*(.*)') { $flags = @($Matches[1].Trim() -split '\s+' | Where-Object { $_ }) }
    if ($flags -contains 'RXLOSS') { $problems += , @(1, (T 'h_radio_off')) } else { $chips += (T 'chip_radio'), (T 'chip_linked') }

    # ESCs at rest. Only meaningful with the battery in; a silent ESC is a caution here and a
    # hard failure only when a motor run confirms it.
    $rows = @([regex]::Matches($h, '(?m)^\s*([1-4])\s+\S+\s+(\d+)\s+(\d+)\s+(\d+)\s+([\d.]+)%'))
    if ($hasBatt -and $rows.Count -ge 4) {
        $dead = @($rows | Where-Object { [double]$_.Groups[5].Value -ge 50 } | ForEach-Object { $_.Groups[1].Value })
        if ($dead.Count) { foreach ($m in $dead) { $problems += , @(1, (T 'h_esc' $m)) } }
        else { $chips += (T 'chip_escs'), '4/4' }
    }

    # Why it would refuse to arm. Transient and bench-normal reasons are left out.
    $ignore = @('CLI', 'MSP', 'RXLOSS', 'BOOTGRACE', 'CALIB', 'NOPREARM', 'NOGYRO')
    if (-not $hasBatt) { $ignore += 'RPMFILTER', 'DSHOT_TELEM', 'DSHOT_BBANG' }
    $blockers = @()
    foreach ($f in $flags) {
        if ($ignore -contains $f) { continue }
        if ($f -eq 'ARMSWITCH') { $problems += , @(2, (T 'arm_ARMSWITCH')); continue }
        $txt = $script:STR["arm_$f"]; if (-not $txt) { $txt = $f }
        $blockers += $txt
    }
    if ($blockers.Count) { $problems += , @(1, (T 'h_arm' ($blockers -join '; '))) }

    foreach ($p in $problems) { if ($p[0] -gt $sev) { $sev = $p[0] } }
    Close-Pending (@('OK', 'WARN', 'FAIL')[$sev])
    Chips $chips
    foreach ($p in $problems) { if ($p[0] -ge 2) { Fail $p[1] } else { Warn $p[1] } }
    return $sev
}

# ---------------------------------------------------------------- motor check
# All four together at the lowest throttle that turns them. Props on or off is the pilot's call; the run is the same. Returns the severity.
# $secs: how long they turn, 1 to 10. The run lasts as long as the speed readings in between take,
# about three quarters of a second each, so the time is approximate.
function Motor-Check([int]$secs = 1, [switch]$AfterReboot) {
    $secs = [Math]::Min(10, [Math]::Max(1, $secs))
    Step (T 'm_step' $secs)
    $cmds = @('status', 'motor 255 1050', 'dshot_telemetry_info')
    for ($n = [int][Math]::Round($secs / 0.75) - 1; $n -gt 0; $n--) { $cmds += 'dshot_telemetry_info' }
    $cmds += 'motor 255 1000'
    $out = Talk $cmds -AfterReboot:$AfterReboot
    $rows = @([regex]::Matches($out, '(?m)^\s*([1-4])\s+\S+\s+(\d+)\s+(\d+)\s+(\d+)\s+([\d.]+)%'))
    if ($rows.Count -ge 4) { $rows = $rows[($rows.Count - 4)..($rows.Count - 1)] }
    if ($rows.Count -lt 4) { Fail (T 'm_noread'); $script:motorLog = 'motors: no readout'; return 1 }

    $rpm = @($rows | ForEach-Object { [int]$_.Groups[3].Value })
    $max = ($rpm | Measure-Object -Maximum).Maximum; $min = ($rpm | Measure-Object -Minimum).Minimum
    $dead = @(); $noisy = @()
    foreach ($m in $rows) {
        if ([int]$m.Groups[3].Value -eq 0) { $dead += $m.Groups[1].Value }
        elseif ([double]$m.Groups[5].Value -ge 1) { $noisy += $m.Groups[1].Value }
    }
    $avg = ($rpm | Measure-Object -Average).Average
    $spread = 0; if ($avg -gt 0 -and -not $dead.Count) { $spread = ($max - $min) / $avg * 100 }
    $stopped = $out -match 'all motors: 0'
    $sev = 0; if ($noisy.Count -or $spread -gt 15 -or -not $stopped) { $sev = 1 }; if ($dead.Count) { $sev = 2 }
    Close-Pending (@('OK', 'WARN', 'FAIL')[$sev])

    foreach ($m in $rows) {
        $v = [int]$m.Groups[3].Value; $err = [double]$m.Groups[5].Value
        $on = 0; if ($max -gt 0) { $on = [int][Math]::Round(20 * $v / ($max * 1.1)) }
        Write-Host "$IND$(T 'm_row' $m.Groups[1].Value)  " -ForegroundColor Gray -NoNewline
        Write-Host ($LIT * $on) -ForegroundColor Green -NoNewline
        Write-Host ($SHD * (20 - $on)) -ForegroundColor DarkGray -NoNewline
        Write-Host ("  {0,5} {1}" -f $v, (T 'unit_rpm')) -ForegroundColor Cyan -NoNewline
        $ec = 'DarkGray'; if ($err -ge 1) { $ec = 'Yellow' }
        Write-Host ("   " + (T 'm_err' $err)) -ForegroundColor $ec
    }
    foreach ($n in $dead) { Fail (T 'm_dead' $n) }
    foreach ($n in $noisy) { Warn (T 'm_noisy' $n) }
    if ($spread -gt 15) { Warn (T 'm_spread' ([int]$spread)) }
    if (-not $stopped) { Warn (T 'm_nostop') }
    if ($sev -eq 0) { Chips (T 'chip_motors'), (T 'chip_even'), (T 'chip_after'), (T 'chip_stopped') }
    $script:motorLog = "motors sev=$sev rpm=$min-$max"
    return $sev
}

# ---------------------------------------------------------------- request parsing
# Splits what follows a command word into: quad name, motor mode, leftover words.
# Name: the first word after the command, in any letters and any case; quotes only if it has spaces.
function Parse-Target([string]$rest) {
    $low = $rest.ToLower()
    $motor = 'none'
    if ($low -match $script:STR['rx_quiet_flag']) { $motor = 'silent' }
    if ($low -match $script:STR['rx_full_flag']) { $motor = 'full' }
    $clean = $rest -replace ('(?i)' + $script:STR['rx_flag_strip']), ' '
    $name = ''
    if ($clean -match '^\s*["«]([^"»]+)["»]') { $name = $Matches[1]; $clean = $clean.Substring($Matches[0].Length) }
    elseif ($clean -match '^\s*(\S+)(\s|$)') { $name = $Matches[1]; $clean = $clean.Substring($Matches[0].Length) }
    return @{ name = $name; motor = $motor; free = @($clean -split '\s+' | Where-Object { $_ }) }
}
function Last-Name {
    $f = Join-Path $quads 'last.txt'
    if (Test-Path $f) { return "$(Get-Content $f -TotalCount 1 -Encoding UTF8)".Trim() }
    return ''
}
# The type name for a drone that is plugged in now: the one bound in this window, else the last
function Name-For([string]$id) {
    if ($script:cur -and $script:cur.id -eq $id) { return $script:cur.name }
    return (Last-Name)
}
function Acquire {
    Step (T 's_find')
    if (-not (Wait-Port 15)) { Fail (T 'f_nousb'); return $false }
    return $true
}

# ---------------------------------------------------------------- bind
# Find the drone on USB and show what it is. Nothing more: the check is "status", and nothing
# is written to the drone.
function Do-Bind([string]$rest) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $r = Parse-Target $rest
    if ($r.name -match $script:STR['rx_radio_name']) { Do-Radio; return }
    $name = $r.name; if (-not $name) { $name = Last-Name }
    if (-not $name) { Fail (T 'f_which'); return }
    $NAME = $name.ToUpper()

    Rule (T 'r_bind' $NAME)
    if (-not (Acquire)) { return }
    Step (T 's_read')
    $d = Read-Drone
    $id = $d.id
    if (-not $id) { Fail (T 'f_noread'); return }
    $seen = @(Get-ChildItem $quads -Filter "*_${id}_*").Count -gt 0
    # the first copy of a drone is the record of how it arrived; a later bind must not overwrite it
    if (-not @(Get-ChildItem $quads -Filter "*_${id}_before.txt").Count) {
        Set-Content (Join-Path $quads "$(Get-Date -Format 'yyyy-MM-dd')_${name}_${id}_before.txt") $d.diff -Encoding utf8
    }
    Set-Content (Join-Path $quads 'last.txt') $name -Encoding utf8
    $script:cur = @{ id = $id; name = $name; craft = $d.craft }

    Kv (T 'kv_id') $id
    Kv (T 'kv_craft') $d.craft
    Kv (T 'kv_fw') $d.fw
    if ($seen) { Kv (T 'kv_seen') (T 'seen_yes') 'Yellow' } else { Kv (T 'kv_seen') (T 'seen_no') }
    if ($r.free.Count) { Note (T 'n_skipped' ($r.free -join ' ')) }
    if ($r.motor -ne 'none') { Note (T 'n_bindmotor') }
    Log "$name $id bind"
    Write-Host ''
    Bar (T 'b_bound' "$NAME $id" (Took $clock)) 'Green'
}

# ---------------------------------------------------------------- set
# set controls: write the type's saved stick settings (plus this drone's own tweaks).
# set sound: switch the buzzer and the motor beacon off. Both can be asked at once.
# set name X: see Do-Name. ("fix" is still accepted as the old word for "set".)
function Do-Fix([string]$rest) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $low = $rest.ToLower()
    $ctl = $low -match $script:STR['rx_ctl']; $snd = $low -match $script:STR['rx_snd']
    if (-not ($ctl -or $snd)) { Note (T 'n_fixwhat'); return }
    $what = @(); if ($ctl) { $what += (T 'w_ctl') }; if ($snd) { $what += (T 'w_snd') }

    Rule (T 'r_fix' ($what -join ' + '))
    if (-not (Acquire)) { return }
    Step (T 's_readdrone')
    $d = Read-Drone
    $id = $d.id
    if (-not $id) { Fail (T 'f_noread'); return }
    $name = Name-For $id
    if (-not $name) { Fail (T 'f_bindfirst'); return }
    $NAME = $name.ToUpper()
    $script:cur = @{ id = $id; name = $name; craft = $d.craft }
    Kv (T 'kv_drone') "$NAME $id"

    $todo = [ordered]@{}
    if ($ctl) {
        $w = Wanted $name $id
        if (-not $w.hasPreset) { Fail (T 'f_nopreset' $NAME); return }
        # Always written in full, whether or not the drone already has the values: the command is
        # the decision (user, 2026-10-09: "write and apply rates regardless").
        foreach ($k in $w.want.Keys) { $todo[$k] = $w.want[$k] }
        # A version of this tool up to 2026-10-09 wrote its own throttle curve (mid 45, expo 40) over
        # the builder's, in the active rate profile only. Where that exact pair is still in the
        # drone and nothing saved says otherwise, put back what its other rate profiles hold.
        if ("$($d.vals['thr_mid'])" -eq '45' -and "$($d.vals['thr_expo'])" -eq '40' -and -not $todo.Contains('thr_mid') -and -not $todo.Contains('thr_expo')) {
            if ($d.otherThr.Count -eq 1 -and $d.otherThr[0] -ne '45/40') {
                $mid, $expo = $d.otherThr[0] -split '/'
                $todo['thr_mid'] = $mid; $todo['thr_expo'] = $expo
                Kv (T 'kv_thr_back') "45 / 40 -> $mid / $expo" 'Yellow'
            } else { Warn (T 'w_thr_unknown') }
        }
        $level = Stiff-Level $name
        if ($level -ne 0 -and $null -ne $d.vals['p_roll']) {
            $pw = Pid-Wanted (Pid-Base $d $name) $level
            foreach ($k in $pw.Keys) { $todo[$k] = $pw[$k] }
            Kv (T 'kv_level') (Signed $level) 'Yellow'
        }
        $stk = Sticks-Saved $name
        if ($stk) { $sp = Sticks-Plan $d ($stk -eq 'on'); if ($sp) { foreach ($k in $sp.Keys) { $todo[$k] = $sp[$k] } } }
        $hor = Mark-Saved $name 'horizon'
        if ($hor) { $hp = Horizon-Plan $d ($hor -eq 'on'); if ($hp) { foreach ($k in $hp.Keys) { $todo[$k] = $hp[$k] } } }
        Step (T 's_ctl' $todo.Count) -Plain; foreach ($k in $todo.Keys) { Item "$k = $($todo[$k])" }
    }
    # sound: asked for now, or the choice kept with the type ("# sound: on|off") when writing controls.
    # On is the buzzer as a whole; the motor beacon is only ever switched off (bf.ps1 refuses it on).
    $sndWant = ''
    if ($snd) { $sndWant = 'off'; if ($low -match $script:STR['rx_on']) { $sndWant = 'on' } } elseif ($ctl) { $sndWant = Mark-Saved $name 'sound' }
    $sound = @()
    if ($sndWant -eq 'off') { $sound = @('beeper -ALL', 'beacon -RX_LOST', 'beacon -RX_SET'); Step (T 's_snd' (T 'w_off').ToLower()) -Plain }
    if ($sndWant -eq 'on') { $sound = @('beeper ALL'); Step (T 's_snd' (T 'w_on').ToLower()) -Plain }

    $done = @(); if ($ctl) { $done += (T 'done_ctl') }; if ($snd) { $done += (T 'done_snd') }
    $ok = Write-And-Verify $name $id $todo $sound
    if ($ok -and $snd) { Set-Mark-Saved $name 'sound' $sndWant }
    Log "$name $id fix $($done -join '+') ok=$ok"
    Write-Host ''
    if ($ok) { Bar (T 'b_fixed' "$NAME $id" ($done -join ', ') (Took $clock)) 'Green' }
    else { Bar (T 'b_problems') 'Yellow' }
}

# set name X: change the name the drone shows on its OSD (Betaflight's craft_name).
# Plain Latin only, because that is all the OSD font has; 16 characters is the firmware's limit.
function Do-Name([string]$new) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $new = $new.Trim().Trim('"').Trim()
    if (-not $new) { Note (T 'n_namewhat'); return }
    Rule (T 'r_name')
    if ($new.Length -gt 16 -or $new -notmatch '^[A-Za-z0-9 _.\-]+$') { Fail (T 'f_badname'); return }
    if (-not (Acquire)) { return }
    Step (T 's_readdrone')
    $d = Read-Drone
    $id = $d.id
    if (-not $id) { Fail (T 'f_noread'); return }
    Kv (T 'kv_osdname') "$($d.craft) -> $new"
    $pos = $d.vals['osd_craft_name_pos']
    if ($null -ne $pos -and (([int]$pos) -band 0x3800) -eq 0) { Warn (T 'w_name_hidden') }
    $type = Name-For $id; if (-not $type) { $type = 'drone' }
    if (-not (Write-And-Verify $type $id ([ordered]@{ craft_name = $new }) @())) {
        Log "$id name NOT CONFIRMED"
        Write-Host ''; Bar (T 'b_problems') 'Yellow'; return
    }
    if ($script:cur -and $script:cur.id -eq $id) { $script:cur.craft = $new }
    Log "$id name '$($d.craft)' -> '$new'"
    Write-Host ''
    Bar (T 'b_named' "$new $id" (Took $clock)) 'Green'
}
# set sticks on / off: the two small stick pictures on the OSD (Betaflight's stick overlay), side
# by side at the bottom centre. Their size is fixed by the firmware: 7 x 5 characters each.
# Written to the plugged-in drone and kept with its quad type. Drawn for a Mode 2 radio.
# What to write for the stick pictures on this drone's screen; $null if its firmware has none
function Sticks-Plan($d, [bool]$on) {
    $lp = $d.vals['osd_stick_overlay_left_pos']; $rp = $d.vals['osd_stick_overlay_right_pos']
    if ($null -eq $lp -or $null -eq $rp) { return $null }
    $plan = [ordered]@{}
    if (-not $on) {
        # hidden in every OSD profile, position kept
        $plan['osd_stick_overlay_left_pos'] = ([int]$lp) -band (-bnot 0x3800)
        $plan['osd_stick_overlay_right_pos'] = ([int]$rp) -band (-bnot 0x3800)
        return $plan
    }
    # screen size in characters: analog is 30 wide with 13 rows sure to be visible
    $cols = 30; $rows = 13
    if ("$($d.vals['vcd_video_system'])" -eq 'PAL') { $rows = 16 }
    if ("$($d.vals['vcd_video_system'])" -eq 'HD' -and [int]$d.vals['osd_canvas_width'] -gt 30) { $cols = [int]$d.vals['osd_canvas_width']; $rows = [int]$d.vals['osd_canvas_height'] }
    $y = $rows - 6; $mid = [int]($cols / 2)
    $place = { param([int]$x, $old) ($x -band 0x1F) -bor (($x -band 0x20) -shl 5) -bor (($y -band 0x1F) -shl 5) -bor 0x3800 -bor (([int]$old) -band 0xC000) }
    $plan['osd_stick_overlay_left_pos'] = & $place ($mid - 8) $lp
    $plan['osd_stick_overlay_right_pos'] = & $place ($mid + 1) $rp
    if ($null -ne $d.vals['osd_stick_overlay_radio_mode']) { $plan['osd_stick_overlay_radio_mode'] = 2 }
    return $plan
}
# A choice kept with the quad type as a "# key: value" line in its settings file
function Mark-Saved([string]$name, [string]$key) {
    $file = Join-Path $presets "$name.txt"
    if (Test-Path $file) { $m = (Get-Content $file -Encoding UTF8 | Select-String -Pattern "^# ${key}:\s*(\w+)" | Select-Object -First 1); if ($m) { return $m.Matches[0].Groups[1].Value } }
    return ''
}
function Set-Mark-Saved([string]$name, [string]$key, [string]$val) {
    $file = Join-Path $presets "$name.txt"
    if (-not (Test-Path $file)) { Save-Preset $name ([ordered]@{}) }
    $cur = @(Get-Content $file -Encoding UTF8 | Where-Object { $_ -notmatch "^# ${key}:" })
    $head = @($cur | Where-Object { $_ -match '^#' }); $rest = @($cur | Where-Object { $_ -notmatch '^#' })
    Set-Content $file ($head + "# ${key}: $val" + $rest) -Encoding utf8
    Log "$name $key $val"
}
# The sticks choice ("# sticks: on") is one of them: set controls gives it to every drone of the type.
function Sticks-Saved([string]$name) { return (Mark-Saved $name 'sticks') }
function Set-Sticks-Saved([string]$name, [bool]$on) { $val = 'off'; if ($on) { $val = 'on' }; Set-Mark-Saved $name 'sticks' $val }
function Do-Sticks([string]$rest) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $on = $rest -match $script:STR['rx_on']; $off = $rest -match $script:STR['rx_off']
    if (-not ($on -or $off)) { Note (T 'n_stickswhat'); return }
    $word = (T 'w_on'); if ($off) { $word = (T 'w_off') }
    Rule (T 'r_sticks' $word)
    if (-not (Acquire)) { return }
    Step (T 's_readdrone')
    $d = Read-Drone
    $id = $d.id
    if (-not $id) { Fail (T 'f_noread'); return }
    $plan = Sticks-Plan $d $on
    if ($null -eq $plan) { Fail (T 'f_nosticks'); return }
    Kv (T 'kv_sticks') $word.ToLower()
    $type = Name-For $id
    if (-not $type) { Fail (T 'f_unknown'); return }
    if (-not (Write-And-Verify $type $id $plan @())) {
        Log "$id sticks NOT CONFIRMED"
        Write-Host ''; Bar (T 'b_problems') 'Yellow'; return
    }
    Set-Sticks-Saved $type ([bool]$on)
    Ok (T 'ok_remembered' $type.ToUpper())
    Write-Host ''
    Bar (T 'b_sticks' $id $word (Took $clock)) 'Green'
}
# set horizon on / off: the artificial horizon line on the OSD. Only its visibility changes; it
# stays where the drone has it (the screen centre unless the builder moved it). Kept with the type.
function Horizon-Plan($d, [bool]$on) {
    $pos = $d.vals['osd_ah_pos']
    if ($null -eq $pos) { return $null }
    $v = ([int]$pos) -band (-bnot 0x3800); if ($on) { $v = ([int]$pos) -bor 0x3800 }
    return [ordered]@{ osd_ah_pos = $v }
}
function Do-Horizon([string]$rest) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $on = $rest -match $script:STR['rx_on']; $off = $rest -match $script:STR['rx_off']
    if (-not ($on -or $off)) { Note (T 'n_horizonwhat'); return }
    $word = (T 'w_on'); if ($off) { $word = (T 'w_off') }
    Rule (T 'r_horizon' $word)
    if (-not (Acquire)) { return }
    Step (T 's_readdrone')
    $d = Read-Drone
    $id = $d.id
    if (-not $id) { Fail (T 'f_noread'); return }
    $plan = Horizon-Plan $d $on
    if ($null -eq $plan) { Fail (T 'f_nohorizon'); return }
    Kv (T 'kv_horizon') $word.ToLower()
    $type = Name-For $id
    if (-not $type) { Fail (T 'f_unknown'); return }
    if (-not (Write-And-Verify $type $id $plan @())) {
        Log "$id horizon NOT CONFIRMED"
        Write-Host ''; Bar (T 'b_problems') 'Yellow'; return
    }
    $val = 'off'; if ($on) { $val = 'on' }
    Set-Mark-Saved $type 'horizon' $val
    Ok (T 'ok_remembered' $type.ToUpper())
    Write-Host ''
    Bar (T 'b_horizon' $id $word (Took $clock)) 'Green'
}
# ---------------------------------------------------------------- yaw / pitch / roll  more / less
# Steps: roll and pitch 10 deg/s at centre and 30 at full stick, yaw 10 and 40, $times over
# (the direction word said twice is two steps). Only for drones whose rates are in the ACTUAL format.
# Throttle is not an axis here; it has its own command below.
function Do-Tune([string[]]$axes, [int]$dir, [int]$times) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $word = (T 'w_more'); if ($dir -lt 0) { $word = (T 'w_less') }
    Rule (T 'r_tune' (($axes | ForEach-Object { T "ax_$_" }) -join ' + ') $word)
    if (-not (Acquire)) { return }
    Step (T 's_readrates')
    $d = Read-Drone
    $id = $d.id
    if (-not $id) { Fail (T 'f_noread'); return }
    $name = Name-For $id
    if (-not $name) { Fail (T 'f_unknown'); return }
    $NAME = $name.ToUpper()
    Kv (T 'kv_drone') "$NAME $id"
    if ("$($d.vals['rates_type'])" -ne 'ACTUAL') { Fail (T 'f_notactual' $d.vals['rates_type']); return }

    $plan = [ordered]@{}
    foreach ($a in $axes) {
        if ($null -eq $d.vals["${a}_rc_rate"] -or $null -eq $d.vals["${a}_srate"]) { Fail (T 'f_noaxis' $a); return }
        $base = 3; if ($a -eq 'yaw') { $base = 4 }
        $c0 = [int]$d.vals["${a}_rc_rate"]; $m0 = [int]$d.vals["${a}_srate"]
        $c1 = [Math]::Min(30, [Math]::Max(1, $c0 + $dir * $times))
        $m1 = [Math]::Min(100, [Math]::Max($c1 + 1, $m0 + $dir * $base * $times))
        $label = (T "ax_$a").ToLower()
        if ($c1 -ne $c0) { $plan["${a}_rc_rate"] = $c1; Kv (T 'kv_centre' $label) "$($c0 * 10) -> $($c1 * 10) $(T 'unit_dps')" }
        if ($m1 -ne $m0) { $plan["${a}_srate"] = $m1; Kv (T 'kv_full' $label) "$($m0 * 10) -> $($m1 * 10) $(T 'unit_dps')" }
        if ($c1 -eq $c0 -and $m1 -eq $m0) { Note (T 'n_limit' $label) }
    }
    if ($plan.Count -eq 0) { Note (T 'n_nochange'); return }

    # no question here: the command itself is the decision, and the opposite word undoes it
    $script:cur = @{ id = $id; name = $name; craft = $d.craft }
    if (-not (Write-And-Verify $name $id $plan @())) {
        Log "$name $id tune NOT CONFIRMED"
        Write-Host ''; Bar (T 'b_problems') 'Yellow'; return
    }
    Remember $name $plan
    Log "$name $id tune $(Pairs $plan)"
    Write-Host ''
    Bar (T 'b_done' "$NAME $id" (Took $clock)) 'Green'
}

# ---------------------------------------------------------------- set controls -m: rates by hand
# A full-screen editor over the console (the alternate screen, so what was on screen comes back
# when it closes). It opens on the values the drone holds now. Up/down move between values,
# digits type, left/right step a value or switch where it is written: this drone only, or this
# drone and the type's profile. Enter writes, Esc leaves without writing.
# Edit-Screen is the keyboard part alone, so tests can stand in for it.
function Edit-Screen($fields, [string]$who, [string]$NAME, [string]$title = (T 'ed_title')) {
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { return $null }
    try {
        Add-Type -Namespace FpvPrep -Name Vt -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n); [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m); [DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);' -ErrorAction SilentlyContinue
        $hOut = [FpvPrep.Vt]::GetStdHandle(-11); $mode = 0; [void][FpvPrep.Vt]::GetConsoleMode($hOut, [ref]$mode); [void][FpvPrep.Vt]::SetConsoleMode($hOut, $mode -bor 4)
    } catch { }
    $esc = [char]27; $row = 0; $fresh = $true; $toProfile = $true; $msg = ''; $result = $null
    $fg = [Console]::ForegroundColor; $bg = [Console]::BackgroundColor
    [Console]::Write("$esc[?1049h$esc[2J"); [Console]::CursorVisible = $false
    try {
        while ($true) {
            [Console]::SetCursorPosition(0, 0)
            $put = { param([string]$text, [string]$color = 'Gray', [switch]$Sel)
                [Console]::ForegroundColor = $color; if ($Sel) { [Console]::BackgroundColor = 'DarkCyan'; [Console]::ForegroundColor = 'White' }
                [Console]::Write($text); [Console]::BackgroundColor = $bg }
            $end = { [Console]::Write("$esc[K`n") }
            & $end
            & $put "  $title" 'White'; & $put "  //  $who" 'Cyan'; & $end
            & $put ('  ' + ('-' * $WIDTH)) 'DarkGray'; & $end; & $end
            # the row being edited: a marker in front, a lit box, and the real cursor after its digits
            $curX = -1; $curY = 0
            for ($i = 0; $i -lt $fields.Count; $i++) {
                $f = $fields[$i]; $here = ($i -eq $row)
                if ($i -gt 0 -and $f.group -ne $fields[$i - 1].group) { & $end }
                if ($here) { & $put '  >> ' 'Yellow'; & $put ("{0,-28}" -f $f.label) 'White' } else { & $put ("     {0,-28}" -f $f.label) 'Gray' }
                if ($here) {
                    & $put '[' 'Yellow'; & $put (" {0,4}" -f $f.text) 'White' -Sel
                    $curX = [Console]::CursorLeft; $curY = [Console]::CursorTop
                    & $put ' ' 'White' -Sel; & $put ']' 'Yellow'
                    & $put " $($f.unit)" 'Gray'; & $put "   $(T 'ed_range' $f.min $f.max)" 'DarkGray'
                } else { & $put ("[ {0,4} ]" -f $f.text) 'Cyan'; & $put " $($f.unit)" 'DarkGray' }
                & $end
            }
            & $end
            # where to write: two choices side by side, the chosen one marked
            $here = ($row -eq $fields.Count)
            if ($here) { & $put '  >> ' 'Yellow'; & $put ("{0,-28}" -f (T 'ed_target')) 'White' } else { & $put ("     {0,-28}" -f (T 'ed_target')) 'Gray' }
            foreach ($opt in @(@($true, (T 'ed_profile' $NAME)), @($false, (T 'ed_drone')))) {
                $on = ($opt[0] -eq $toProfile); $mark = '( )'; if ($on) { $mark = '(*)' }
                if ($on -and $here) { & $put "$mark $($opt[1])" 'White' -Sel } elseif ($on) { & $put "$mark $($opt[1])" 'Yellow' } else { & $put "$mark $($opt[1])" 'DarkGray' }
                & $put '    '
            }
            & $end; & $end
            & $put "     $msg" 'Red'; & $end; & $end
            & $put ('  ' + ('-' * $WIDTH)) 'DarkGray'; & $end
            & $put "  $(T 'ed_keys')" 'DarkGray'; & $end
            [Console]::Write("$esc[J")
            if ($curX -ge 0) { [Console]::SetCursorPosition($curX, $curY); [Console]::CursorVisible = $true } else { [Console]::CursorVisible = $false }

            $k = [Console]::ReadKey($true); $msg = ''
            $onField = $row -lt $fields.Count
            $code = [int]$k.KeyChar   # typed-in keys can arrive as a character with no key name
            if ($k.Key -eq 'Escape' -or $code -eq 27) { break }
            if ($k.Key -eq 'Enter' -or $code -eq 13 -or ($k.Key -eq 'S' -and ($k.Modifiers -band [ConsoleModifiers]::Control))) {
                $msg = Edit-Check $fields
                if (-not $msg) { $result = @{ toProfile = $toProfile }; break }
                continue
            }
            if ($k.Key -eq 'UpArrow') { $row = ($row + $fields.Count) % ($fields.Count + 1); $fresh = $true; continue }
            if ($k.Key -eq 'DownArrow' -or $k.Key -eq 'Tab' -or $code -eq 9) { $row = ($row + 1) % ($fields.Count + 1); $fresh = $true; continue }
            if ($k.Key -eq 'LeftArrow' -or $k.Key -eq 'RightArrow') {
                $sign = 1; if ($k.Key -eq 'LeftArrow') { $sign = -1 }
                if (-not $onField) { $toProfile = -not $toProfile; continue }
                $f = $fields[$row]; $v = 0; [void][int]::TryParse($f.text, [ref]$v)
                $f.text = "$([Math]::Min($f.max, [Math]::Max($f.min, $v + $sign * $f.step)))"; $fresh = $true; continue
            }
            if ($onField -and $k.Key -eq 'Backspace') { $f = $fields[$row]; if ($f.text.Length) { $f.text = $f.text.Substring(0, $f.text.Length - 1) }; $fresh = $false; continue }
            if ($onField -and $k.KeyChar -match '^\d$') {
                $f = $fields[$row]; if ($fresh) { $f.text = '' }
                if ($f.text.Length -lt 4) { $f.text += $k.KeyChar }; $fresh = $false; continue
            }
        }
    } finally {
        [Console]::ForegroundColor = $fg; [Console]::BackgroundColor = $bg
        [Console]::CursorVisible = $true; [Console]::Write("$esc[?1049l")
    }
    return $result
}
# '' when every value is usable, else what is wrong with the first one that is not
function Edit-Check($fields) {
    foreach ($f in $fields) {
        $v = 0
        if (-not [int]::TryParse($f.text, [ref]$v) -or $v -lt $f.min -or $v -gt $f.max) { return (T 'ed_bad' $f.label $f.min $f.max) }
    }
    foreach ($a in 'roll', 'pitch', 'yaw') {
        $c = $fields | Where-Object { $_.key -eq "${a}_rc_rate" }; $m = $fields | Where-Object { $_.key -eq "${a}_srate" }
        if ($c -and $m -and [int]$m.text -le [int]$c.text) { return (T 'ed_bad_full' $m.label) }
    }
    return ''
}
function Do-Edit {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    Rule (T 'r_edit')
    if (-not (Acquire)) { return }
    Step (T 's_readrates')
    $d = Read-Drone
    $id = $d.id
    if (-not $id) { Fail (T 'f_noread'); return }
    $name = Name-For $id
    if (-not $name) { Fail (T 'f_unknown'); return }
    $NAME = $name.ToUpper()
    Kv (T 'kv_drone') "$NAME $id"
    if ("$($d.vals['rates_type'])" -ne 'ACTUAL') { Fail (T 'f_notactual' $d.vals['rates_type']); return }
    $fields = @()
    foreach ($a in 'roll', 'pitch', 'yaw') {
        $label = (T "ax_$a").ToLower()
        if ($null -eq $d.vals["${a}_rc_rate"] -or $null -eq $d.vals["${a}_srate"] -or $null -eq $d.vals["${a}_expo"]) { Fail (T 'f_noaxis' $a); return }
        # rates are stored in tens of degrees a second and shown in degrees a second
        $fields += @{ key = "${a}_rc_rate"; group = $a; label = (T 'kv_centre' $label); unit = (T 'unit_dps'); mul = 10; step = 10; min = 10; max = 500; text = "$([int]$d.vals["${a}_rc_rate"] * 10)" }
        $fields += @{ key = "${a}_srate"; group = $a; label = (T 'kv_full' $label); unit = (T 'unit_dps'); mul = 10; step = 10; min = 20; max = 1000; text = "$([int]$d.vals["${a}_srate"] * 10)" }
        $fields += @{ key = "${a}_expo"; group = $a; label = (T 'ed_expo' $label); unit = ''; mul = 1; step = 5; min = 0; max = 100; text = "$([int]$d.vals["${a}_expo"])" }
    }
    $r = Edit-Screen $fields "$NAME $id" $NAME
    if ($null -eq $r) { Note (T 'n_nothing'); return }
    $plan = [ordered]@{}
    foreach ($f in $fields) {
        $v = [int][Math]::Round([int]$f.text / $f.mul)
        $shown = "$([int]$d.vals[$f.key] * $f.mul)"; $now = "$($v * $f.mul)"
        $plan[$f.key] = $v
        if ($shown -ne $now) { Kv $f.label "$shown -> $now $($f.unit)".TrimEnd() }
    }
    $script:cur = @{ id = $id; name = $name; craft = $d.craft }
    if (-not (Write-And-Verify $name $id $plan @())) {
        Log "$name $id edit NOT CONFIRMED"
        Write-Host ''; Bar (T 'b_problems') 'Yellow'; return
    }
    if ($r.toProfile) { Remember $name $plan } else { Ok (T 'ok_drone_only') }
    Log "$name $id edit profile=$($r.toProfile) $(Pairs $plan)"
    Write-Host ''
    Bar (T 'b_done' "$NAME $id" (Took $clock)) 'Green'
}
# ---------------------------------------------------------------- throttle softer / sharper
# "Softer" has one meaning (user, 2026-10-10): softer when the stick is worked at lift-off AND in
# flight. Betaflight's throttle has no sensitivity setting of its own: how much power a small
# stick movement adds is the steepness of the curve at that point. So the command measures, on
# the same 11-point table the firmware builds, how much stick travel lies between lift-off power
# and cruise power of a loaded quad, and moves thr_expo the way that widens it: down for a curve
# hung from the top, up for one bent around the middle. It stops where that stretch is widest,
# because past it lift-off would get softer only at the price of flight, and it never leaves a
# nearly dead part inside the stretch. thr_mid is not moved: it decides where on the stick the
# top of the power sits, and that stays the builder's. One step is 10 of expo, $times over.
# The starting point is the profile's curve when it names one, otherwise the drone's own.
# The standard set still holds no throttle curve: a type gets one only through this command.
$thrLift = 500; $thrCruise = 850   # of 1000: where a loaded 10-13 inch quad lifts off, and cruises
# The firmware's throttle table (same integer maths): power 0..1000 at stick 0, 10, .. 100 %
function Thr-Table([int]$mid, [int]$expo) {
    $tbl = @()
    for ($i = 0; $i -le 10; $i++) {
        $tmp = 10 * $i - $mid; $y = 1
        if ($tmp -gt 0) { $y = 100 - $mid } elseif ($tmp -lt 0) { $y = $mid }
        $tbl += 10 * $mid + [Math]::Truncate($tmp * (100 - $expo + [Math]::Truncate($expo * ($tmp * $tmp) / ($y * $y))) / 10)
    }
    return $tbl
}
# Stick position, in %, where a table reaches a power
function Thr-Stick($tbl, [double]$power) {
    for ($i = 0; $i -lt 10; $i++) {
        if ($tbl[$i + 1] -ge $power) {
            $rise = $tbl[$i + 1] - $tbl[$i]
            if ($rise -le 0) { return 10.0 * $i }
            return 10.0 * $i + 10.0 * ($power - $tbl[$i]) / $rise
        }
    }
    return 100.0
}
# Stick travel between lift-off and cruise power: the wider, the softer
function Thr-Travel([int]$mid, [int]$expo) {
    $tbl = Thr-Table $mid $expo
    return (Thr-Stick $tbl $thrCruise) - (Thr-Stick $tbl $thrLift)
}
# True when some part of that stretch hardly answers the stick (under 3 % power per 10 % stick)
function Thr-Dead([int]$mid, [int]$expo) {
    $tbl = Thr-Table $mid $expo
    for ($i = 0; $i -lt 10; $i++) { if ($tbl[$i + 1] -gt $thrLift -and $tbl[$i] -lt $thrCruise -and ($tbl[$i + 1] - $tbl[$i]) -lt 30) { return $true } }
    return $false
}
# The expo that gives this thr_mid its widest stretch
function Thr-Softest([int]$mid) {
    $best = 0; $widest = -1.0
    for ($e = 0; $e -le 100; $e++) { $trav = Thr-Travel $mid $e; if ($trav -gt $widest + 1e-9) { $widest = $trav; $best = $e } }
    return $best
}
function Do-Throttle([int]$dir, [int]$times) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $word = (T 'w_softer'); if ($dir -lt 0) { $word = (T 'w_stiffer') }
    Rule (T 'r_thr' $word)
    if (-not (Acquire)) { return }
    Step (T 's_readthr')
    $d = Read-Drone
    $id = $d.id
    if (-not $id) { Fail (T 'f_noread'); return }
    $name = Name-For $id
    if (-not $name) { Fail (T 'f_unknown'); return }
    $NAME = $name.ToUpper()
    Kv (T 'kv_drone') "$NAME $id"
    if ($null -eq $d.vals['thr_mid'] -or $null -eq $d.vals['thr_expo']) { Fail (T 'f_nothr'); return }

    $has = "$($d.vals['thr_mid']) / $($d.vals['thr_expo'])"
    $mid = [int]$d.vals['thr_mid']; $expo = [int]$d.vals['thr_expo']
    $saved = (Wanted $name $id).want
    if ($saved.Contains('thr_mid') -and $saved.Contains('thr_expo')) { $mid = [int]$saved['thr_mid']; $expo = [int]$saved['thr_expo'] }
    elseif ($has -eq '45 / 40' -and $d.otherThr.Count -eq 1 -and $d.otherThr[0] -ne '45/40') {
        # an old version's own curve is not this drone's: start from what its other rate profiles hold
        $mid, $expo = $d.otherThr[0] -split '/' | ForEach-Object { [int]$_ }
    }
    $best = Thr-Softest $mid
    $step = 10 * [Math]::Max(1, $times)
    if ($dir -gt 0) {
        # softer: towards the widest stretch, never past it and never into a dead part
        $new = $expo + [Math]::Sign($best - $expo) * [Math]::Min($step, [Math]::Abs($best - $expo))
        while ($new -ne $expo -and (Thr-Dead $mid $new)) { $new -= [Math]::Sign($new - $expo) }
    } else {
        # sharper: the other way, as far as expo goes
        $away = [Math]::Sign($expo - $best); if ($away -eq 0) { $away = 1; if ($best -gt 50) { $away = -1 } }
        $new = [Math]::Min(100, [Math]::Max(0, $expo + $away * $step))
    }
    if ($new -eq $expo) { Note (T 'n_limit' (T 'kv_thr')); return }
    Kv (T 'kv_thr') "$has -> $mid / $new"

    # no question, as with the axes: the opposite word undoes it. Always both values, so the
    # profile's curve is complete on its own.
    $plan = [ordered]@{ thr_mid = $mid; thr_expo = $new }
    $script:cur = @{ id = $id; name = $name; craft = $d.craft }
    if (-not (Write-And-Verify $name $id $plan @())) {
        Log "$name $id throttle NOT CONFIRMED"
        Write-Host ''; Bar (T 'b_problems') 'Yellow'; return
    }
    Remember $name $plan
    Log "$name $id throttle $(Pairs $plan)"
    Write-Host ''
    Bar (T 'b_done' "$NAME $id" (Took $clock)) 'Green'
}

# ---------------------------------------------------------------- pid stiffer / pid softer
# Scales roll and pitch P, I and D together, 10 % of the drone's ORIGINAL values per level,
# between -2 and +3. Why relative and not calculated outright: an absolute PID worked out from
# assumed inertia and thrust lands a factor of 2-3 away from a real tune, but the change a
# payload makes is bounded: 40-100 % more inertia against about 35 % more motor gain at the
# higher hover throttle leaves the loop 4-32 % weaker than when the drone was tuned empty.
# The level is kept per quad type ("# stiffness: N" in its settings file); each drone's original
# values are recorded the first time it is touched, so levels never compound.
$pidKeys = 'p_roll', 'i_roll', 'd_roll', 'd_min_roll', 'p_pitch', 'i_pitch', 'd_pitch', 'd_min_pitch'
function Pid-Base($d, [string]$type = '') {
    if ($type) {
        # PID values typed into the type's profile (pid -m) come first: levels scale from those
        $own = Read-Settings (Join-Path $presets "$type.txt"); $typed = [ordered]@{}
        foreach ($k in $pidKeys) { if ($own.Contains($k)) { $typed[$k] = $own[$k] } }
        if ($typed.Count) { return $typed }
    }
    $file = Join-Path $quads "pid0_$($d.id).txt"
    if (-not (Test-Path $file)) {
        $h = [ordered]@{}; foreach ($k in $pidKeys) { if ($null -ne $d.vals[$k]) { $h[$k] = $d.vals[$k] } }
        Write-Settings $file $h @('# PID values this drone had when first seen')
    }
    return (Read-Settings $file)
}
function Pid-Wanted($base, [int]$level) {
    $h = [ordered]@{}
    foreach ($k in $base.Keys) { $h[$k] = [int][Math]::Round([int]$base[$k] * (1 + 0.1 * $level), [MidpointRounding]::AwayFromZero) }
    return $h
}
function Stiff-Level([string]$name) {
    $file = Join-Path $presets "$name.txt"
    if (Test-Path $file) { $m = (Get-Content $file -Encoding UTF8 | Select-String -Pattern '^# stiffness:\s*(-?\d+)' | Select-Object -First 1); if ($m) { return [int]$m.Matches[0].Groups[1].Value } }
    return 0
}
function Set-Stiff-Level([string]$name, [int]$level) {
    $file = Join-Path $presets "$name.txt"
    if (-not (Test-Path $file)) { Save-Preset $name ([ordered]@{}) }
    $cur = @(Get-Content $file -Encoding UTF8 | Where-Object { $_ -notmatch '^# stiffness:' })
    $head = @($cur | Where-Object { $_ -match '^#' }); $rest = @($cur | Where-Object { $_ -notmatch '^#' })
    Set-Content $file ($head + "# stiffness: $level" + $rest) -Encoding utf8
    Log "$name stiffness level $level"
}
function Signed([int]$n) { if ($n -gt 0) { return "+$n" }; return "$n" }

# pid -m: the same editor on the PID values the drone holds now (roll and pitch P, I, D, D min;
# yaw P and I). The pilot's own numbers, written as typed. Saved to the profile they become what
# every drone of the type gets and what pid stiffer / softer scales from, and the level goes back to 0.
function Do-PidEdit {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    Rule (T 'r_pidedit')
    if (-not (Acquire)) { return }
    Step (T 's_readpid')
    $d = Read-Drone
    $id = $d.id
    if (-not $id) { Fail (T 'f_noread'); return }
    $name = Name-For $id
    if (-not $name) { Fail (T 'f_unknown'); return }
    $NAME = $name.ToUpper()
    Kv (T 'kv_drone') "$NAME $id"
    if ($null -eq $d.vals['p_roll'] -or $null -eq $d.vals['p_pitch']) { Fail (T 'f_nopid'); return }
    [void](Pid-Base $d)   # keep the record of how the drone arrived before anything is typed over it
    $fields = @()
    foreach ($a in 'roll', 'pitch', 'yaw') {
        $parts = @(@('p', 'P'), @('i', 'I'), @('d', 'D'), @('d_min', 'D min')); if ($a -eq 'yaw') { $parts = @(@('p', 'P'), @('i', 'I')) }
        foreach ($pt in $parts) {
            $key = "$($pt[0])_$a"
            if ($null -eq $d.vals[$key]) { continue }
            $fields += @{ key = $key; group = $a; label = "$((T "ax_$a").ToLower()) $($pt[1])"; unit = ''; mul = 1; step = 1; min = 0; max = 250; text = "$([int]$d.vals[$key])" }
        }
    }
    $r = Edit-Screen $fields "$NAME $id" $NAME (T 'ed_pidtitle')
    if ($null -eq $r) { Note (T 'n_nothing'); return }
    $plan = [ordered]@{}
    foreach ($f in $fields) {
        $plan[$f.key] = [int]$f.text
        if ("$([int]$d.vals[$f.key])" -ne "$([int]$f.text)") { Kv $f.label "$([int]$d.vals[$f.key]) -> $([int]$f.text)" }
    }
    Write-Host "$IND[!] $(T 'w_risky')" -ForegroundColor Yellow
    $script:cur = @{ id = $id; name = $name; craft = $d.craft }
    if (-not (Write-And-Verify $name $id $plan @())) {
        Log "$name $id pid edit NOT CONFIRMED"
        Write-Host ''; Bar (T 'b_problems') 'Yellow'; return
    }
    if ($r.toProfile) { Save-Preset $name $plan; Set-Stiff-Level $name 0; Ok (T 'ok_remembered' $NAME) } else { Ok (T 'ok_drone_only') }
    Log "$name $id pid edit profile=$($r.toProfile) $(Pairs $plan)"
    Write-Host ''
    Bar (T 'b_done' "$NAME $id" (Took $clock)) 'Green'
}
function Do-Stiff([int]$dir) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $word = (T 'w_stiffer'); if ($dir -lt 0) { $word = (T 'w_softer') }
    Rule (T 'r_stiff' $word)
    if (-not (Acquire)) { return }
    Step (T 's_readpid')
    $d = Read-Drone
    $id = $d.id
    if (-not $id) { Fail (T 'f_noread'); return }
    $name = Name-For $id
    if (-not $name) { Fail (T 'f_unknown'); return }
    $NAME = $name.ToUpper()
    Kv (T 'kv_drone') "$NAME $id"
    if ($null -eq $d.vals['p_roll'] -or $null -eq $d.vals['p_pitch']) { Fail (T 'f_nopid'); return }

    $base = Pid-Base $d $name
    $old = Stiff-Level $name
    $new = [Math]::Max(-2, [Math]::Min(3, $old + $dir))
    if ($new -eq $old) { Note (T 'n_stifflimit' (Signed $old)); return }
    $want = Pid-Wanted $base $new
    foreach ($a in 'roll', 'pitch') {
        Kv (T 'kv_pid' (T "ax_$a").ToLower()) "$($d.vals["p_$a"]) / $($d.vals["i_$a"]) / $($d.vals["d_$a"]) -> $($want["p_$a"]) / $($want["i_$a"]) / $($want["d_$a"])"
    }
    Kv (T 'kv_level') "$(Signed $old) -> $(Signed $new)"
    Write-Host "$IND[!] $(T 'w_risky')" -ForegroundColor Yellow
    if (-not (Ask (T 'q_apply'))) { Note (T 'n_nothing'); return }

    $todo = [ordered]@{}; foreach ($k in $want.Keys) { if ("$($d.vals[$k])" -ne "$($want[$k])") { $todo[$k] = $want[$k] } }
    $script:cur = @{ id = $id; name = $name; craft = $d.craft }
    if ($todo.Count -and -not (Write-And-Verify $name $id $todo @())) {
        Log "$name $id stiffness NOT CONFIRMED"
        Write-Host ''; Bar (T 'b_problems') 'Yellow'; return
    }
    Set-Stiff-Level $name $new
    Ok (T 'ok_remembered' $NAME)
    Write-Host ''
    Bar (T 'b_done' "$NAME $id" (Took $clock)) 'Green'
}

# ---------------------------------------------------------------- motors, status, radio, help
function Do-Motors([int]$secs = 1) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    Rule (T 'r_motors')
    if (-not (Acquire)) { return }
    $sev = Motor-Check $secs
    Log "motors only: $($script:motorLog)"
    Verdict $sev (T 'r_motors') (T 'good_motors') $clock
}

# The full check of the plugged-in drone: rates and health. Changes nothing.
function Do-Status {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    Rule (T 'r_status')
    if (-not (Acquire)) { return }
    Step (T 's_readonly')
    $d = Read-Drone -Health
    if (-not $d.id) { Fail (T 'f_noread'); return }
    $name = Name-For $d.id
    $who = $d.id; if ($name) { $who = "$($name.ToUpper()) $($d.id)" }
    Kv (T 'kv_drone') $who
    if ("$($d.vals['rates_type'])" -eq 'ACTUAL') {
        foreach ($a in 'roll', 'pitch', 'yaw') { Kv (T 'kv_rates' (T "ax_$a").ToLower()) "$([int]$d.vals["${a}_rc_rate"] * 10) / $([int]$d.vals["${a}_srate"] * 10) $(T 'unit_dps')" }
    } else { Kv (T 'kv_ratefmt') "$($d.vals['rates_type'])" 'Yellow' }
    $sev = Health $d
    Log "$who status sev=$sev"
    Verdict $sev $who (T 'good_status') $clock
}

# The radio in USB storage mode: ONLY the stick calibration is read, nothing is changed
function Do-Radio {
    Rule (T 'r_radio')
    Step (T 's_calib')
    $f = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 } | ForEach-Object { "$($_.DeviceID)\RADIO\radio.yml" } | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $f) { Fail (T 'f_noradio'); return }
    $l = Get-Content $f
    $i = ($l | Select-String -Pattern '^calib:' | Select-Object -First 1).LineNumber
    $bad = $false
    for ($k = $i; $k -lt $i + 16 -and $k -lt $l.Count - 3; $k += 4) {
        if ($l[$k] -notmatch '^\s+(Rud|Ele|Thr|Ail):') { continue }
        $axis = $Matches[1]
        $neg = [int]($l[$k + 2] -replace '\D'); $pos = [int]($l[$k + 3] -replace '\D')
        if ($neg -lt 300 -or $pos -lt 300) { $bad = $true; Kv (T 'kv_axis' $axis) "$neg / $pos" 'Red' } else { Kv (T 'kv_axis' $axis) "$neg / $pos" }
    }
    if ($bad) { Fail (T 'f_calib') } else { Ok (T 'ok_calib') }
    Log "radio check bad=$bad"
}

function Help {
    Rule (T 'r_help')
    Write-Host ''
    $wide = ($script:STR['help'] | Where-Object { $_.Count -eq 2 } | ForEach-Object { $_[0].TrimEnd().Length } | Measure-Object -Maximum).Maximum + 4
    foreach ($h in $script:STR['help']) {
        if ($h.Count -eq 0) { Write-Host ''; continue }
        if ($h.Count -eq 1) { Note $h[0]; continue }
        # the command word in cyan, its options in yellow, the brackets and bars between them dim
        $cmd = $h[0].TrimEnd().PadRight($wide); $cut = $cmd.IndexOf('['); if ($cut -lt 0) { $cut = $cmd.Length }
        Write-Host $IND -NoNewline; Write-Host $cmd.Substring(0, $cut) -ForegroundColor Cyan -NoNewline; foreach ($piece in [regex]::Split($cmd.Substring($cut), '([\[\]|])')) { $pc = 'Yellow'; if ($piece -match '^[\[\]|]$') { $pc = 'DarkGray' }; Write-Host $piece -ForegroundColor $pc -NoNewline }
        Write-Host $h[1] -ForegroundColor Gray
    }
}

# ---------------------------------------------------------------- dispatch
# A direction word said more than once is that many steps at once: "yaw more more" is two.
function Times([string]$text, [string]$key) { return [Math]::Max(1, [regex]::Matches($text, $script:STR[$key]).Count) }
function Dispatch([string]$line) {
    $low = $line.ToLower().Trim()
    try {
        if (-not $low) { return }
        if ($low -match $script:STR['rx_bind']) { Do-Bind $line.Trim().Substring($Matches[0].Length) }
        elseif ($low -match $script:STR['rx_fix']) {
            $rest = $line.Trim().Substring($Matches[0].Length)
            if ($rest.ToLower() -match $script:STR['rx_name']) { Do-Name $rest.Substring($Matches[0].Length) } elseif ($rest.ToLower() -match $script:STR['rx_sticks']) { Do-Sticks $rest.ToLower().Substring($Matches[0].Length) } elseif ($rest.ToLower() -match $script:STR['rx_ctl'] -and $rest.ToLower() -match '(^|\s)-m(\s|$)') { Do-Edit } elseif ($rest.ToLower() -match $script:STR['rx_horizon']) { Do-Horizon $rest.ToLower().Substring($Matches[0].Length) } else { Do-Fix $rest }
        }
        elseif ($low -match $script:STR['rx_fix_short']) { Do-Fix $line }   # the bare word, without "set"
        elseif ($low -match $script:STR['rx_pid']) {
            # checked before the axis words, so "pid softer" is never read as an axis command
            $rest = $low.Substring($Matches[0].Length)
            if ($rest -match '(^|\s)-m(\s|$)') { Do-PidEdit }
            elseif ($rest -match $script:STR['rx_stiffer']) { Do-Stiff (Times $rest 'rx_stiffer') } elseif ($rest -match $script:STR['rx_softer']) { Do-Stiff (-(Times $rest 'rx_softer')) } else { Note (T 'n_pidwhat') }
        }
        elseif ($low -match $script:STR['rx_thr']) {
            # its own words too, and also ahead of the axis words
            $rest = $low.Substring($Matches[0].Length)
            if ($rest -match $script:STR['rx_thr_softer']) { Do-Throttle 1 (Times $rest 'rx_thr_softer') } elseif ($rest -match $script:STR['rx_thr_sharper']) { Do-Throttle -1 (Times $rest 'rx_thr_sharper') } else { Note (T 'n_thrwhat') }
        }
        elseif ($low -match $script:STR['rx_help']) { Help }
        elseif ($low -match $script:STR['rx_status']) { Do-Status }
        elseif ($low -match $script:STR['rx_radio']) { Do-Radio }
        else {
            $axes = @()
            foreach ($a in 'yaw', 'pitch', 'roll') { if ($low -match $script:STR["rx_$a"]) { $axes += $a } }
            $dir = 0; $times = 1
            if ($low -match $script:STR['rx_more']) { $dir = 1; $times = Times $low 'rx_more' } elseif ($low -match $script:STR['rx_less']) { $dir = -1; $times = Times $low 'rx_less' }

            if ($axes.Count -and $dir) { Do-Tune $axes $dir $times }

            elseif ($low -match $script:STR['rx_motor']) { if ($low -match '(\d+)') { Do-Motors ([int]$Matches[1]) } else { Do-Motors 1 } }
            else { Fail (T 'f_unknowncmd') }
        }
    } catch { Fail (Local-Error $_.Exception.Message) }
    Close-Pending
    Write-Host ''
}

# ---------------------------------------------------------------- start
function Banner {
    $build = (Get-Item (Join-Path $root 'fpv.ps1')).LastWriteTime.ToString('yyyyMMdd')
    Write-Host ''
    foreach ($b in $script:STR['banner']) {
        for ($i = 0; $i -lt $b.Count; $i += 2) {
            Write-Host ($b[$i] -f $build) -ForegroundColor $b[$i + 1] -NoNewline:($i + 2 -lt $b.Count)
        }
    }
    Write-Host ('  ' + ('-' * $WIDTH)) -ForegroundColor DarkGray
    Write-Host ''
}

if ($NoMain) { return }
if ($Run) { foreach ($l in ($Run -split '\s*;;\s*')) { Dispatch $l }; return }

Clear-Host
Banner
$rows = @(, @((T 'kv_saved'), ((Get-ChildItem $presets -Filter '*.txt' | ForEach-Object { if ($_.BaseName -eq '_default') { T 'preset_std' } else { $_.BaseName } }) -join ', ')))
if (Last-Name) { $rows += , @((T 'kv_last'), (Last-Name)) }
foreach ($row in $rows) { Kv $row[0] $row[1]; if ($fancy) { Start-Sleep -Milliseconds 60 } }
Write-Host ''
Write-Host "$IND$(T 'warn_bf')" -ForegroundColor Yellow
Note (T 'note_help')
Write-Host ''
while ($true) {
    Write-Host '  FPV' -ForegroundColor Cyan -NoNewline
    Write-Host ':\> ' -ForegroundColor Green -NoNewline
    $line = $Host.UI.ReadLine()
    if ($null -eq $line -or $line.Trim() -match $script:STR['rx_exit']) { break }
    Dispatch $line
}
