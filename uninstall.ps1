# Removes the Task Reminder completely: running copy, autostart, Win+R phrase, cached files.
$ErrorActionPreference = 'SilentlyContinue'
$TaskName = 'TaskReminder'
$Cache    = Join-Path $env:TEMP 'TaskReminder'
$Ctl      = Join-Path $env:LOCALAPPDATA 'TaskReminderCtl'

# 1. Stop any running copy (this also releases the input freeze)
$pidFile = Join-Path $Cache 'pid.txt'
if (Test-Path $pidFile) {
    $p = [int](Get-Content $pidFile | Select-Object -First 1)
    if ($p -and $p -ne $PID) { Stop-Process -Id $p -Force }
}
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'reminders\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Seconds 1

# 2. Remove autostart (scheduled task + registry fallback)
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $TaskName

# 3. Remove the Win+R phrase(s): known names, plus anything pointing at our uninstaller folder
foreach ($n in 'stopreminders', 'removereminders') {
    Remove-Item "HKCU:\Software\Classes\$n" -Recurse -Force
}
Get-ChildItem 'HKCU:\Software\Classes' | ForEach-Object {
    $cmd = (Get-ItemProperty "$($_.PSPath)\shell\open\command").'(default)'
    if ($cmd -match 'TaskReminderCtl') { Remove-Item $_.PSPath -Recurse -Force }
}

# 4. Remove cached files and the uninstaller folder
Remove-Item $Cache -Recurse -Force
Remove-Item $Ctl   -Recurse -Force

# 5. Report
$left = @()
if (Get-ScheduledTask -TaskName $TaskName)                     { $left += 'scheduled task (may need an admin PowerShell to remove)' }
if (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $TaskName) { $left += 'registry Run entry' }
if (Test-Path $Cache)                                          { $left += 'cache folder (a copy may still be running)' }
if (Test-Path $Ctl)                                            { $left += 'uninstaller folder' }

if ($left.Count -eq 0) { $msg = 'Deflocked sucessfuly: stopped, autostart removed, cached files deleted.' }
else { $msg = "Mostly uninstalled, but these are still present:`n- " + ($left -join "`n- ") }

Add-Type -AssemblyName System.Windows.Forms
[void][System.Windows.Forms.MessageBox]::Show($msg, 'Palanatir Enrolement')
