# Real-console test of a launcher: opens the .cmd in its own console window exactly as a
# double-click does, types lines into it as a keyboard would (true Unicode key events), reads
# back what is on its screen, then types the exit word and checks the window closes.
# sim.ps1 cannot see this layer: there output is captured, so cursor moves, animation, the
# console's own input decoding and the .cmd file itself never run.
#   powershell -File tests\console.ps1 -Launcher C:\x\FPV.cmd -Type 'help' -Exit 'exit' -Out C:\x\screen.txt
# Must be started in a process of its own (it detaches from its console to attach to the other).
param(
    [Parameter(Mandatory)][string]$Launcher,
    [string[]]$Type = @(),
    [Parameter(Mandatory)][string]$Exit,
    [Parameter(Mandatory)][string]$Out,
    [int]$SettleMs = 9000
)

Add-Type -TypeDefinition @"
using System; using System.Text; using System.Runtime.InteropServices;
public class Con {
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool FreeConsole();
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool AttachConsole(uint pid);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr CreateFile(string name, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr tmpl);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
  [StructLayout(LayoutKind.Explicit, CharSet=CharSet.Unicode)] public struct INPUT_RECORD {
    [FieldOffset(0)] public ushort EventType; [FieldOffset(4)] public int bKeyDown; [FieldOffset(8)] public ushort wRepeatCount;
    [FieldOffset(10)] public ushort wVirtualKeyCode; [FieldOffset(12)] public ushort wVirtualScanCode; [FieldOffset(14)] public char UnicodeChar; [FieldOffset(16)] public uint dwControlKeyState; }
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool WriteConsoleInput(IntPtr h, INPUT_RECORD[] buf, uint len, out uint written);
  [StructLayout(LayoutKind.Sequential)] public struct COORD { public short X; public short Y; }
  [StructLayout(LayoutKind.Sequential)] public struct INFO { public COORD Size; public COORD Cursor; public ushort Attr; public short L, T, R, B; public COORD Max; }
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetConsoleScreenBufferInfo(IntPtr h, out INFO info);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool ReadConsoleOutputCharacter(IntPtr h, StringBuilder sb, uint len, COORD at, out uint read);

  public static string Send(uint pid, string text) {
    FreeConsole(); if (!AttachConsole(pid)) return "attach failed " + Marshal.GetLastWin32Error();
    IntPtr h = CreateFile("CONIN$", 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
    var recs = new INPUT_RECORD[text.Length * 2];
    for (int i = 0; i < text.Length; i++) { char c = text[i]; ushort vk = (ushort)(c == '\r' ? 0x0D : 0);
      recs[2*i] = new INPUT_RECORD { EventType = 1, bKeyDown = 1, wRepeatCount = 1, wVirtualKeyCode = vk, UnicodeChar = c };
      recs[2*i+1] = new INPUT_RECORD { EventType = 1, bKeyDown = 0, wRepeatCount = 1, wVirtualKeyCode = vk, UnicodeChar = c }; }
    uint w; bool ok = WriteConsoleInput(h, recs, (uint)recs.Length, out w); int err = Marshal.GetLastWin32Error(); CloseHandle(h); FreeConsole();
    return ok ? "ok" : "write failed " + err; }

  public static string Screen(uint pid) {
    FreeConsole(); if (!AttachConsole(pid)) return "attach failed " + Marshal.GetLastWin32Error();
    IntPtr h = CreateFile("CONOUT$", 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
    INFO info; if (!GetConsoleScreenBufferInfo(h, out info)) { FreeConsole(); return "no screen info " + Marshal.GetLastWin32Error(); }
    var all = new StringBuilder();
    for (short y = 0; y <= info.Cursor.Y; y++) {
      var sb = new StringBuilder(info.Size.X + 1); uint n;
      ReadConsoleOutputCharacter(h, sb, (uint)info.Size.X, new COORD { X = 0, Y = y }, out n);
      all.AppendLine(sb.ToString(0, (int)n).TrimEnd()); }
    CloseHandle(h); FreeConsole(); return all.ToString(); } }
"@

$log = @()
# Hidden, not minimised: a minimised console can still take the keyboard, and then whatever the
# person at the PC is typing lands on this prompt. A hidden console is still a real console.
$p = Start-Process cmd.exe -ArgumentList '/c', "`"$Launcher`"" -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 5
if ($p.HasExited) { Set-Content $Out @("RESULT: the window closed by itself within 5 s (exit code $($p.ExitCode))") -Encoding UTF8; return }
foreach ($l in $Type) { $log += "typed '$l': " + [Con]::Send([uint32]$p.Id, $l + "`r"); Start-Sleep -Milliseconds 700 }
Start-Sleep -Milliseconds $SettleMs
$screen = [Con]::Screen([uint32]$p.Id)
$log += "typed '$Exit': " + [Con]::Send([uint32]$p.Id, $Exit + "`r")
$closed = $p.WaitForExit(8000)
if (-not $closed) { try { & taskkill.exe /PID $p.Id /T /F | Out-Null } catch { } }
Set-Content $Out (@("RESULT: started=yes  closed-on-exit-word=$closed") + $log + '--- SCREEN ---' + $screen) -Encoding UTF8
