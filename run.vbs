' run_reminders.vbs
' Downloads reminders.sh + all media files from GitHub, then runs it hidden in Git Bash.
' Edit the 3 config lines below, then double-click this file.

' ============ CONFIG ============
Const REPO_RAW   = "https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main"
Const WORK_DIR   = "C:\Users\YourName\reminder-app"       ' local cache folder
Const GIT_BASH   = "C:\Program Files\Git\bin\bash.exe"
' Files to fetch (must match what reminders.sh references)
Dim FILES: FILES = Array( _
    "reminders.sh", _
    "image1.jpg", "image2.jpg", "image3.jpg", "image4.jpg", "image5.jpg", _
    "audio1.wav", "audio2.wav", "audio3.wav", "audio4.wav", "audio5.wav" _
)
' =================================

Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")

' Ensure working folder exists
If Not fso.FolderExists(WORK_DIR) Then fso.CreateFolder(WORK_DIR)

' Download each file via PowerShell (Invoke-WebRequest), overwriting each launch
For Each f In FILES
    url  = REPO_RAW & "/" & f
    dest = WORK_DIR & "\" & f
    ' -UseBasicParsing + silent errors; 5s timeout per file via -TimeoutSec
    psCmd = "try { Invoke-WebRequest -Uri '" & url & "' -OutFile '" & dest & _
            "' -UseBasicParsing -TimeoutSec 20 } catch { exit 1 }"
    rc = sh.Run("powershell -NoProfile -ExecutionPolicy Bypass -Command """ & psCmd & """", 0, True)
    If rc <> 0 Then
        ' Non-fatal: keep going so a single missing asset doesn't kill the whole run
        ' (comment this line out if you want to abort on any failure)
    End If
Next

' Launch reminders.sh hidden (window style 0 = hidden, False = don't wait)
sh.CurrentDirectory = WORK_DIR
sh.Run """" & GIT_BASH & """ -c ""cd '/c/" & Replace(WORK_DIR, "C:\", "") & _
       "' && bash reminders.sh""", 0, False