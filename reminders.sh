#!/usr/bin/env bash
# Standalone random reminder script
# Place in same folder as image/audio files. Run: bash reminders.sh

# ============ Configuration Area (Directly modify file names and URLs) ============
# Note: Audio must be .wav (PowerShell native support), images can be jpg/png/bmp (will auto-convert)
R1_NAME="Heavens Gate";    R1_IMG="image1.jpg"; R1_AUD="audio1.wav"; R1_URL="https://heavensgate.com/"
R2_NAME="Lunch";      R2_IMG="image2.jpg"; R2_AUD="audio2.wav"; R2_URL="https://example.com/lunch"
R3_NAME="Workout";    R3_IMG="image3.jpg"; R3_AUD="audio3.wav"; R3_URL="https://example.com/workout"
R4_NAME="Break";      R4_IMG="image4.jpg"; R4_AUD="audio4.wav"; R4_URL="https://example.com/break"
R5_NAME="Review";     R5_IMG="image5.jpg"; R5_AUD="audio5.wav"; R5_URL="https://example.com/review"
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="$SCRIPT_DIR/.tmp_reminder"
mkdir -p "$TEMP_DIR"

# Array of reminder names for random selection
NAMES=("$R1_NAME" "$R2_NAME" "$R3_NAME" "$R4_NAME" "$R5_NAME")

log() { echo "[$(date +%H:%M:%S)] $*"; }

# --- Volume (uses built-in Windows nircmd alternative: PowerShell simulated volume up key) ---
set_volume_max() {
    # Without external exe, use PowerShell to send volume up key many times (unreliable but dependency-free)
    # Better method: Use a tiny embedded VBS to send volume up 50 times, ensuring max
    powershell -c "1..50 | ForEach-Object { (New-Object -ComObject WScript.Shell).SendKeys([char]175) }" 2>/dev/null
    log "  🔊 Volume maxed"
}

# --- Audio (PowerShell SoundPlayer, .wav native support) ---
play_sound() {
    local f="$1"
    [[ ! -f "$f" ]] && { log "  ⚠️ Audio not found: $f"; return; }
    local wp; wp=$(cygpath -w "$f" 2>/dev/null || echo "$f")
    powershell -c "(New-Object Media.SoundPlayer '$wp').PlaySync();" 2>/dev/null
    log "  🎵 Audio played"
}

# --- Webpage (start command) ---
open_url() {
    local u="$1"
    [[ -z "$u" ]] && return
    start "" "$u" 2>/dev/null
    log "  🌐 URL opened"
}

# --- Wallpaper (Converts to BMP then modifies registry) ---
set_wallpaper() {
    local f="$1"
    [[ ! -f "$f" ]] && { log "  ⚠️ Image not found: $f"; return; }
    local bmp="$TEMP_DIR/wall.bmp"
    local abs; abs=$(cygpath -w "$f" 2>/dev/null || echo "$f")
    local bmp_w; bmp_w=$(cygpath -w "$bmp" 2>/dev/null || echo "$bmp")

    # Use PowerShell to convert any format to BMP
    powershell -c "Add-Type -AssemblyName System.Drawing; \$i=[System.Drawing.Image]::FromFile('$abs'); \$i.Save('$bmp_w',[System.Drawing.Imaging.ImageFormat]::Bmp); \$i.Dispose()" 2>/dev/null

    # Write registry and refresh
    reg add "HKEY_CURRENT_USER\Control Panel\Desktop" /v Wallpaper /t REG_SZ /d "$bmp_w" /f >/dev/null 2>&1
    RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters >/dev/null 2>&1
    log "  🖼️ Wallpaper set"
}

# --- Trigger ---
trigger() {
    local idx=$1
    local name="${NAMES[$idx]}"
    local img_var="R$((idx+1))_IMG"; local img="${!img_var}"
    local aud_var="R$((idx+1))_AUD"; local aud="${!aud_var}"
    local url_var="R$((idx+1))_URL"; local url="${!url_var}"

    log "=== Trigger: $name ==="
    set_volume_max
    play_sound "$SCRIPT_DIR/$aud"
    open_url "$url"
    set_wallpaper "$SCRIPT_DIR/$img"
    log "=== Done ==="
}

# --- Main Loop ---
# In Git Bash, script runs in foreground. For background operation, run via VBS wrapper (see below)
log "Reminder daemon started. 5 tasks loaded. Ctrl+C to stop."

while true; do
    # Random 10 seconds to 180 seconds (3 minutes)
    delay=$(( (RANDOM % 171) + 10 ))
    idx=$(( RANDOM % 5 ))
    log "Next: ${NAMES[$idx]} in ${delay}s"
    sleep "$delay"
    trigger "$idx"
done
