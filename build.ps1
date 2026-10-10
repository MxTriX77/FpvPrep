# Makes the releases and the mock, and tests them before calling them done.
#   .\build.ps1                         every language in lang\, onto the Desktop
#   .\build.ps1 -OutRoot D:\release     the same, somewhere else
#   .\build.ps1 -Lang en                one language only
# What it makes:
#   one release per language   the console for a real drone over USB. Its folder and launcher
#                              names come from the language file ("release" entry).
#   one mock                   MOCK\MOCK.cmd, the same console against a pretend drone, with
#                              nothing on screen marking it as a mock, in the
#                              language given by -MockLang (ru if there is one, else the first).
# Nothing is released untested:
#   1. tests\sim.ps1 must pass for a language, or nothing is built for it;
#   2. after building, each launcher is opened in a real (hidden) console window, typed into and
#      read back by tests\console.ps1.
#   .\build.ps1 -MockOnly -MockFolder X -MockLauncher Y.cmd    only the mock, under other names
#   .\build.ps1 -Lang en -To D:\some\folder    one language's release straight into that folder
#                                              (its saved settings and logs are left alone), no mock
param([string[]]$Lang, [string]$MockLang, [string]$OutRoot = [Environment]::GetFolderPath('Desktop'),
      [string]$MockFolder = 'MOCK', [string]$MockLauncher = 'MOCK.cmd', [switch]$MockOnly, [string]$To)

$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
if (-not $Lang) { $Lang = @(Get-ChildItem (Join-Path $src 'lang') -Filter '*.ps1' | ForEach-Object BaseName) }
if (-not $MockLang) { $MockLang = $Lang[0]; if ($Lang -contains 'ru') { $MockLang = 'ru' } }
if ($MockOnly) { $Lang = @($MockLang) }
if ($To) { if ($Lang.Count -ne 1 -or $MockOnly) { throw '-To needs exactly one -Lang and no -MockOnly' }; $MockLang = '' }
$ps = 'powershell.exe'; $psArgs = '-NoProfile', '-ExecutionPolicy', 'Bypass'

# Opens one launcher in its own console, types the lines, returns the screen text
function Try-Launcher([string]$cmd, [string[]]$type, [string]$exitWord) {
    $out = Join-Path $env:TEMP "fpvprep_screen_$PID.txt"
    if (Test-Path $out) { [IO.File]::Delete($out) }
    $typed = ($type | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ','
    $line = "& '$(Join-Path $src 'tests\console.ps1')' -Launcher '$cmd' -Type $typed -Exit '$exitWord' -Out '$out'"
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($line))
    $h = Start-Process $ps -ArgumentList ($psArgs + '-EncodedCommand', $enc) -WindowStyle Hidden -PassThru
    [void]$h.WaitForExit(90000)
    $text = ''; if (Test-Path $out) { $text = (Get-Content $out -Encoding UTF8) -join "`n"; [IO.File]::Delete($out) }
    return $text
}
# The files every folder needs: the console itself, one language, the standard settings
function Copy-Core([string]$to, [string]$l) {
    foreach ($d in '', 'lang', 'presets') { New-Item -ItemType Directory -Force (Join-Path $to $d) | Out-Null }
    Copy-Item (Join-Path $src 'fpv.ps1'), (Join-Path $src 'bf.ps1') -Destination $to -Force
    Copy-Item (Join-Path $src "lang\$l.ps1") -Destination (Join-Path $to 'lang') -Force
    Copy-Item (Join-Path $src 'presets\_default.txt') -Destination (Join-Path $to 'presets') -Force
}
function Write-Launcher([string]$file, [string]$title, [string]$script, [string]$l, [string]$more = '') {
    [IO.File]::WriteAllText($file, "@echo off`r`ncolor 0A`r`ntitle $title`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0$script`" -Lang $l $more%*`r`n", [Text.Encoding]::ASCII)
}

$failed = @()
foreach ($l in $Lang) {
    if (-not (Test-Path (Join-Path $src "lang\$l.ps1"))) { throw "no language file lang\$l.ps1" }
    $txt = & (Join-Path $src "lang\$l.ps1"); $w = $txt['test_words']
    $rel = Join-Path $OutRoot $txt['release'].folder; if ($To) { $rel = $To }
    $launcher = Join-Path $rel $txt['release'].launcher
    if (Test-Path $rel -PathType Leaf) { throw "$rel is a file, not a folder" }
    "== $($l.ToUpper())"

    # 1. the simulator test decides whether anything is built for this language
    $sim = & $ps @psArgs -File (Join-Path $src 'tests\sim.ps1') -Lang $l
    $simOk = ($LASTEXITCODE -eq 0)
    "   simulator test: " + (($sim | Where-Object { $_ -match 'passed' }) -join '').Trim()
    if (-not $simOk) { $sim | Where-Object { $_ -match 'FAIL' }; $failed += "$l simulator test"; "   NOT BUILT"; continue }

    # 2. the release
    if (-not $MockOnly) {
        Copy-Core $rel $l
        Write-Launcher $launcher 'FPV PREP' 'fpv.ps1' $l
        "   release: $launcher"
        $s = Try-Launcher $launcher @($w.help) $w.exit
        $ok = $s.Contains('closed-on-exit-word=True') -and $s.Contains($txt['r_help']) -and $s.Contains($txt['warn_bf'])
        "   release in a real window (start screen, help, exit): " + $(if ($ok) { 'OK' } else { 'FAILED' })
        if (-not $ok) { $failed += "$l release" }
    }

    # 3. the mock, for one language only
    if ($l -eq $MockLang) {
        $mock = Join-Path $OutRoot $MockFolder; $mockCmd = Join-Path $mock $MockLauncher
        if (Test-Path $mock -PathType Leaf) { throw "$mock is a file, not a folder" }
        Copy-Core $mock $l
        New-Item -ItemType Directory -Force (Join-Path $mock 'mock') | Out-Null
        Copy-Item (Join-Path $src 'tests\mock.ps1'), (Join-Path $src 'tests\simfc.ps1') -Destination (Join-Path $mock 'mock') -Force
        # the mock looks exactly like the release on screen: only its folder and file name say what it is
        Write-Launcher $mockCmd 'FPV PREP' 'mock\mock.ps1' $l '-Plain '
        "   mock:    $mockCmd"
        $s = Try-Launcher $mockCmd @("$($w.bind) $($w.odd_name)", $w.status, $w.status, $w.status) $w.exit
        $ok = $s.Contains('closed-on-exit-word=True') -and $s.Contains($txt['good_status']) -and $s.Contains(($txt['v_warn'] -f '', '').Trim(' /')) -and $s.Contains(($txt['v_fail'] -f '', '').Trim(' /'))
        "   mock in a real window (bind, status x3: green, yellow, red, exit): " + $(if ($ok) { 'OK' } else { 'FAILED' })
        if (-not $ok) { $failed += "$l mock" }
    }
}
if ($failed.Count) { throw "NOT GOOD: $($failed -join '; ')" }
'ALL BUILT AND CHECKED'
