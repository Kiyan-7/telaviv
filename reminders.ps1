# ============================================================
#  reminders.ps1  — zero-prerequisite random reminder daemon
#  Downloads its own media to %TEMP%\reminder-app on first run.
# ============================================================

$ErrorActionPreference = 'SilentlyContinue'

# ---------- CONFIG ----------
$RawBase = 'https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main'
$WorkDir = Join-Path $env:TEMP 'reminder-app'
$MinDelaySec = 10
$MaxDelaySec = 180

$Reminders = @(
  @{ Name='Meeting'; Img='image1.jpg'; Aud='audio1.wav'; Url='https://example.com/meeting' }
  @{ Name='Lunch';   Img='image2.jpg'; Aud='audio2.wav'; Url='https://example.com/lunch'   }
  @{ Name='Workout'; Img='image3.jpg'; Aud='audio3.wav'; Url='https://example.com/workout' }
  @{ Name='Break';   Img='image4.jpg'; Aud='audio4.wav'; Url='https://example.com/break'   }
  @{ Name='Review';  Img='image5.jpg'; Aud='audio5.wav'; Url='https://example.com/review'  }
)
# ----------------------------

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# ---------- Media fetch ----------
function Get-Media {
  param([string]$File)
  $dest = Join-Path $WorkDir $File
  if (-not (Test-Path $dest)) {
    try {
      Invoke-WebRequest -Uri "$RawBase/$File" -OutFile $dest -UseBasicParsing -TimeoutSec 30
    } catch {
      Write-Host "  [!] Failed to fetch $File"
    }
  }
  return $dest
}

foreach ($r in $Reminders) {
  $r.ImgPath = Get-Media $r.Img
  $r.AudPath = Get-Media $r.Aud
}

# ---------- Volume to 100% (embedded C#, no modules) ----------
Add-Type -Language CSharp @"
using System;
using System.Runtime.InteropServices;
public class Vol {
    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioEndpointVolume {
        int _0(); int _1(); int _2(); int _3();
        int SetMasterVolumeLevelScalar(float f, Guid g);
        int _5(); int _6(); int _7(); int _8();
    }
    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o);
    }
    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        int _0(); int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice dev);
    }
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    class MMDeviceEnumeratorComObject { }
    public static void Max() {
        var en = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
        IMMDevice dev; en.GetDefaultAudioEndpoint(0, 1, out dev);
        Guid iid = typeof(IAudioEndpointVolume).GUID;
        object o; dev.Activate(ref iid, 23, IntPtr.Zero, out o);
        ((IAudioEndpointVolume)o).SetMasterVolumeLevelScalar(1.0f, Guid.Empty);
    }
}
"@

function Set-VolumeMax {
  try { [Vol]::Max(); Write-Host '  🔊 Volume maxed' }
  catch { Write-Host '  [!] Volume set failed' }
}

# ---------- Play WAV ----------
function Play-Sound {
  param([string]$Path)
  if (-not (Test-Path $Path)) { Write-Host "  [!] Missing audio: $Path"; return }
  try { (New-Object Media.SoundPlayer $Path).PlaySync(); Write-Host '  🎵 Audio played' }
  catch { Write-Host "  [!] Audio failed: $_" }
}

# ---------- Open URL ----------
function Open-Url {
  param([string]$Url)
  if ($Url) { Start-Process $Url; Write-Host "  🌐 Opened $Url" }
}

# ---------- Set wallpaper ----------
Add-Type @"
using System.Runtime.InteropServices;
public class WP {
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern int SystemParametersInfo(int a, int b, string c, int d);
}
"@

function Set-Wallpaper {
  param([string]$Path)
  if (-not (Test-Path $Path)) { Write-Host "  [!] Missing image: $Path"; return }
  try {
    # Convert to BMP via System.Drawing (works for jpg/png)
    Add-Type -AssemblyName System.Drawing
    $bmp = Join-Path $WorkDir 'wall.bmp'
    $img = [System.Drawing.Image]::FromFile($Path)
    $img.Save($bmp, [System.Drawing.Imaging.ImageFormat]::Bmp)
    $img.Dispose()
    [WP]::SystemParametersInfo(0x0014, 0, $bmp, 0x01 -bor 0x02) | Out-Null
    Write-Host '  🖼️ Wallpaper set'
  } catch { Write-Host "  [!] Wallpaper failed: $_" }
}

# ---------- Trigger ----------
function Invoke-Reminder {
  param($R)
  Write-Host ''
  Write-Host "=== $(Get-Date -Format HH:mm:ss) — $($R.Name) ==="
  Set-VolumeMax
  Play-Sound $R.AudPath
  Open-Url   $R.Url
  Set-Wallpaper $R.ImgPath
  Write-Host '=== Done ==='
  Write-Host ''
}

# ---------- Main loop ----------
Write-Host "Reminder daemon started. 5 reminders, delays 10s–180s. Ctrl+C to stop."
while ($true) {
  $r = $Reminders | Get-Random
  $delay = Get-Random -Minimum $MinDelaySec -Maximum ($MaxDelaySec + 1)
  $eta = (Get-Date).AddSeconds($delay).ToString('HH:mm:ss')
  Write-Host ("Next: {0} in {1}s (around {2})" -f $r.Name, $delay, $eta)
  Start-Sleep -Seconds $delay
  Invoke-Reminder $r
}