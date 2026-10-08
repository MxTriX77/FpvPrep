# FPV PREP console engine. Started by FPV.cmd.
#   bind "OTU"                  find the drone on USB and show what it is. Writes nothing.
#   status                      full check: health and rates. Writes nothing.
#   motors [full]               motor check, props off
#   fix controls / fix sound    write the type's saved stick settings / switch beeps off
#   yaw more, pitch roll less   adjust the bound drone, optionally remember for the type
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

    return @{
        head  = $head; diff = $diff; vals = $vals
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
function Save-Preset([string]$name, $add, [string]$craft) {
    $h = @("# Saved settings for '$name'. Created by FPV PREP on $(Get-Date -Format 'yyyy-MM-dd')."); if ($craft) { $h += "# craft: $craft" }
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
function Remember([string]$name, [string]$id, [string]$craft, $add) {
    Save-Preset $name $add $craft
    Ok (T 'ok_remembered' $name.ToUpper())
}
# The preset remembers what its drones call themselves ("# craft: X"). Without that line,
# fall back to "the drone's own name starts with NAME".
function Craft-Matches([string]$name, [string]$craft) {
    $file = Join-Path $presets "$name.txt"
    if (-not (Test-Path $file)) { return $true }
    $want = (Get-Content $file -Encoding UTF8 | Select-String -Pattern '^# craft:\s*(\S+)' | Select-Object -First 1)
    if ($want) { return ($craft -eq $want.Matches[0].Groups[1].Value) }
    return ($craft -like "$name*")
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
    if ($more -match '^beeper') { if ((Lines $after.diff) -match '^beeper -') { Ok (T 'ok_snd') } else { Warn (T 'w_snd_unconf') } }
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
# Props off. All four together at the lowest throttle that turns them. Returns the severity.
function Motor-Check([string]$mode, [switch]$AfterReboot) {
    if ($mode -eq 'full') { Step (T 'm_step_full') } else { Step (T 'm_step_quiet') }
    $cmds = @('status', 'motor 255 1050', 'dshot_telemetry_info')
    if ($mode -eq 'full') { $cmds += 'dshot_telemetry_info', 'dshot_telemetry_info', 'dshot_telemetry_info' }
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
# Name: quoted, or unquoted in Latin letters/digits or ALL CAPS right after the command.
function Parse-Target([string]$rest) {
    $low = $rest.ToLower()
    $motor = 'none'
    if ($low -match $script:STR['rx_quiet_flag']) { $motor = 'silent' }
    if ($low -match $script:STR['rx_full_flag']) { $motor = 'full' }
    $clean = $rest -replace ('(?i)' + $script:STR['rx_flag_strip']), ' '
    $name = ''
    if ($clean -match '^\s*["«]([^"»]+)["»]') { $name = $Matches[1]; $clean = $clean.Substring($Matches[0].Length) }
    elseif ($clean -cmatch '^\s*([A-Za-z0-9_-]+|[\p{Lu}0-9_-]{2,})(\s|$)') { $name = $Matches[1]; $clean = $clean.Substring($Matches[0].Length) }
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
    Set-Content (Join-Path $quads "$(Get-Date -Format 'yyyy-MM-dd')_${name}_${id}_before.txt") $d.diff -Encoding utf8
    Set-Content (Join-Path $quads 'last.txt') $name -Encoding utf8
    $script:cur = @{ id = $id; name = $name; craft = $d.craft }

    Kv (T 'kv_id') $id
    Kv (T 'kv_craft') $d.craft
    Kv (T 'kv_fw') $d.fw
    if ($seen) { Kv (T 'kv_seen') (T 'seen_yes') 'Yellow' } else { Kv (T 'kv_seen') (T 'seen_no') }
    $w = Wanted $name $id
    if ($w.hasPreset) {
        $same = @($w.want.Keys | Where-Object { "$($d.vals[$_])" -eq "$($w.want[$_])" }).Count
        $c = 'Cyan'; if ($same -lt $w.want.Count) { $c = 'Yellow' }
        if ($w.std) { Kv (T 'kv_ctl') (T 'ctl_count_std' $same $w.want.Count) $c } else { Kv (T 'kv_ctl') (T 'ctl_count' $same $w.want.Count $NAME) $c }
    } else { Kv (T 'kv_ctl') (T 'ctl_none' $NAME) 'Yellow' }
    if ($w.own.Count) { Kv (T 'kv_own') (T 'own_count' $w.own.Count) }
    if (-not (Craft-Matches $name $d.craft)) { Warn (T 'w_craft' $d.craft $NAME) }
    if ($r.free.Count) { Note (T 'n_skipped' ($r.free -join ' ')) }
    if ($r.motor -ne 'none') { Note (T 'n_bindmotor') }
    Log "$name $id bind"
    Write-Host ''
    Bar (T 'b_bound' "$NAME $id" (Took $clock)) 'Green'
}

# ---------------------------------------------------------------- fix
# fix controls: write the type's saved stick settings (plus this drone's own tweaks).
# fix sound: switch the buzzer and the motor beacon off. Both can be asked at once.
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
        if (-not (Craft-Matches $name $d.craft)) {
            Warn (T 'w_craft' $d.craft $NAME)
            if (-not (Ask (T 'q_anyway' $NAME))) { Note (T 'n_nothing'); Log "$name $id REFUSED craft=$($d.craft)"; return }
        }
        foreach ($k in $w.want.Keys) { if ("$($d.vals[$k])" -ne "$($w.want[$k])") { $todo[$k] = $w.want[$k] } }
        $level = Stiff-Level $name
        if ($level -ne 0 -and $null -ne $d.vals['p_roll']) {
            $pw = Pid-Wanted (Pid-Base $d) $level
            foreach ($k in $pw.Keys) { if ("$($d.vals[$k])" -ne "$($pw[$k])") { $todo[$k] = $pw[$k] } }
            Kv (T 'kv_level') (Signed $level) 'Yellow'
        }
        $label = $NAME; if ($w.std) { $label = (T 'preset_std') }
        if ($todo.Count -eq 0) { Ok (T 'ok_ctl_same' $label ($w.want.Count)) }
        else { Step (T 's_ctl' $label $todo.Count) -Plain; foreach ($k in $todo.Keys) { Item "$k = $($todo[$k])" } }
    }
    $sound = @(); if ($snd) { $sound = @('beeper -ALL', 'beacon -RX_LOST', 'beacon -RX_SET'); Step (T 's_snd') -Plain }

    $done = @(); if ($todo.Count) { $done += (T 'done_ctl') }; if ($snd) { $done += (T 'done_snd') }
    if (-not $done.Count) { Write-Host ''; Bar (T 'b_nofix' "$NAME $id") 'Green'; return }
    $ok = Write-And-Verify $name $id $todo $sound
    Log "$name $id fix $($done -join '+') ok=$ok"
    Write-Host ''
    if ($ok) { Bar (T 'b_fixed' "$NAME $id" ($done -join ', ') (Took $clock)) 'Green' }
    else { Bar (T 'b_problems') 'Yellow' }
}

# ---------------------------------------------------------------- yaw / pitch / roll / throttle  more / less
# Steps: roll and pitch 10 deg/s at centre and 30 at full stick, yaw 10 and 40, throttle expo 10.
# $scale halves or doubles them. Only for drones whose rates are in the ACTUAL format.
function Do-Tune([string[]]$axes, [int]$dir, [double]$scale) {
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
        if ($a -eq 'throttle') {
            # more throttle = sharper = less expo around the middle
            if ($null -eq $d.vals['thr_expo']) { Fail (T 'f_nothr'); return }
            $old = [int]$d.vals['thr_expo']; $step = [Math]::Max(1, [int][Math]::Round(10 * $scale))
            $new = [Math]::Min(100, [Math]::Max(0, $old - $dir * $step))
            $how = (T 'thr_sharper'); if ($dir -lt 0) { $how = (T 'thr_softer') }
            if ($new -eq $old) { Note (T 'n_limit' (T 'ax_throttle').ToLower()) } else { $plan['thr_expo'] = $new; Kv (T 'kv_thr') "$old -> $new  ($how)" }
            continue
        }
        if ($null -eq $d.vals["${a}_rc_rate"] -or $null -eq $d.vals["${a}_srate"]) { Fail (T 'f_noaxis' $a); return }
        $base = 3; if ($a -eq 'yaw') { $base = 4 }
        $c0 = [int]$d.vals["${a}_rc_rate"]; $m0 = [int]$d.vals["${a}_srate"]
        $c1 = [Math]::Min(30, [Math]::Max(1, $c0 + $dir * [Math]::Max(1, [int][Math]::Round(1 * $scale))))
        $m1 = [Math]::Min(100, [Math]::Max($c1 + 1, $m0 + $dir * [Math]::Max(1, [int][Math]::Round($base * $scale))))
        $label = (T "ax_$a").ToLower()
        if ($c1 -ne $c0) { $plan["${a}_rc_rate"] = $c1; Kv (T 'kv_centre' $label) "$($c0 * 10) -> $($c1 * 10) $(T 'unit_dps')" }
        if ($m1 -ne $m0) { $plan["${a}_srate"] = $m1; Kv (T 'kv_full' $label) "$($m0 * 10) -> $($m1 * 10) $(T 'unit_dps')" }
        if ($c1 -eq $c0 -and $m1 -eq $m0) { Note (T 'n_limit' $label) }
    }
    if ($plan.Count -eq 0) { Note (T 'n_nochange'); return }
    if (-not (Ask (T 'q_apply'))) { Note (T 'n_nothing'); return }

    $script:cur = @{ id = $id; name = $name; craft = $d.craft }
    if (-not (Write-And-Verify $name $id $plan @())) {
        Log "$name $id tune NOT CONFIRMED"
        Write-Host ''; Bar (T 'b_problems') 'Yellow'; return
    }
    Remember $name $id $d.craft $plan
    Log "$name $id tune $(Pairs $plan)"
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
function Pid-Base($d) {
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
function Set-Stiff-Level([string]$name, [int]$level, [string]$craft) {
    $file = Join-Path $presets "$name.txt"
    if (-not (Test-Path $file)) { Save-Preset $name ([ordered]@{}) $craft }
    $cur = @(Get-Content $file -Encoding UTF8 | Where-Object { $_ -notmatch '^# stiffness:' })
    $head = @($cur | Where-Object { $_ -match '^#' }); $rest = @($cur | Where-Object { $_ -notmatch '^#' })
    Set-Content $file ($head + "# stiffness: $level" + $rest) -Encoding utf8
    Log "$name stiffness level $level"
}
function Signed([int]$n) { if ($n -gt 0) { return "+$n" }; return "$n" }

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

    $base = Pid-Base $d
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
    Set-Stiff-Level $name $new $d.craft
    Ok (T 'ok_remembered' $NAME)
    Write-Host ''
    Bar (T 'b_done' "$NAME $id" (Took $clock)) 'Green'
}

# ---------------------------------------------------------------- motors, status, radio, help
function Do-Motors([string]$mode) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    Rule (T 'r_motors')
    if (-not (Acquire)) { return }
    $sev = Motor-Check $mode
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
    Kv (T 'kv_thr') "$($d.vals['thr_expo'])"
    foreach ($p in (Get-ChildItem $presets -Filter '*.txt')) {
        $ps = Read-Settings $p.FullName
        $label = $p.BaseName; if ($label -eq '_default') { $label = (T 'preset_std') }
        Kv (T 'kv_preset' $label) (T 'preset_count' @($ps.Keys | Where-Object { "$($d.vals[$_])" -eq "$($ps[$_])" }).Count $ps.Count)
    }
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
    foreach ($h in $script:STR['help']) {
        if ($h.Count -eq 0) { Write-Host ''; continue }
        if ($h.Count -eq 1) { Note $h[0]; continue }
        Write-Host $IND -NoNewline; Write-Host $h[0] -ForegroundColor Cyan -NoNewline; Write-Host $h[1] -ForegroundColor Gray
    }
}

# ---------------------------------------------------------------- dispatch
function Dispatch([string]$line) {
    $low = $line.ToLower().Trim()
    try {
        if (-not $low) { return }
        if ($low -match $script:STR['rx_bind']) { Do-Bind $line.Trim().Substring($Matches[0].Length) }
        elseif ($low -match $script:STR['rx_fix']) { Do-Fix $line.Trim().Substring($Matches[0].Length) }
        elseif ($low -match $script:STR['rx_fix_short']) { Do-Fix $line }   # the bare word, without "fix"
        elseif ($low -match $script:STR['rx_pid']) {
            # checked before the axis words, so "pid softer" is never read as an axis command
            $rest = $low.Substring($Matches[0].Length)
            if ($rest -match $script:STR['rx_stiffer']) { Do-Stiff 1 } elseif ($rest -match $script:STR['rx_softer']) { Do-Stiff -1 } else { Note (T 'n_pidwhat') }
        }
        elseif ($low -match $script:STR['rx_help']) { Help }
        elseif ($low -match $script:STR['rx_status']) { Do-Status }
        elseif ($low -match $script:STR['rx_radio']) { Do-Radio }
        else {
            $axes = @()
            foreach ($a in 'yaw', 'pitch', 'roll', 'throttle') { if ($low -match $script:STR["rx_$a"]) { $axes += $a } }
            $dir = 0
            if ($low -match $script:STR['rx_more']) { $dir = 1 } elseif ($low -match $script:STR['rx_less']) { $dir = -1 }
            $scale = 1.0
            if ($low -match $script:STR['rx_half']) { $scale = 0.5 }
            if ($low -match $script:STR['rx_double']) { $scale = 2.0 }

            if ($axes.Count -and $dir) { Do-Tune $axes $dir $scale }

            elseif ($low -match $script:STR['rx_motor']) { if ($low -match $script:STR['rx_full']) { Do-Motors 'full' } else { Do-Motors 'silent' } }
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
$usb = (T 'usb_none'); if ([System.IO.Ports.SerialPort]::GetPortNames().Count) { $usb = (T 'usb_found') }
$rows = @(
    @((T 'kv_workspace'), $DataRoot),
    @((T 'kv_saved'), ((Get-ChildItem $presets -Filter '*.txt' | ForEach-Object { if ($_.BaseName -eq '_default') { T 'preset_std' } else { $_.BaseName } }) -join ', ')),
    @((T 'kv_usb'), $usb)
)
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
