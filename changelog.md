# Zig Rewrite

## Config Options

res/config.ini contains all of the available config options and their default values.

### Additions

+ border\_fg has been introduced to change the color of the borders.
+ term\_restore\_cursor\_cmd should restore the cursor to it's usual state.
+ log\_path is used to store ly.log and ly.log.old for debugging purposes (pretty much nothing is logged currently).
+ enable\_vi\_mode to enable vi keybindings.
+ sleep\_key and sleep\_cmd.

Note: sleep\_cmd is unset by default, meaning it's hidden and has no effect. 

### Changes

+ xinitrc can be set to null to hide it.
+ blank\_password has been renamed to clear\_password.

### Removals

+ wayland\_specifier has been removed.

## Save File

The save file is now in .ini format.

Example:

```ini
user = ash
session_index = 0
```

## Misc

+ getty@tty2 has been added as a conflict in res/ly.service, so if it is running, ly should still be able to start.
+ XDG\_CURRENT\_DESKTOP is now set by ly.
+ LANG is no longer set by ly.
+ X Server PID is fetched from /tmp/X{d}.lock to be able to kill the process since it detaches.
