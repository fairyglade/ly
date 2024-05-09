# Zig Rewrite (Version 1.0.0)

## Config Options

res/config.ini contains all of the available config options and their default values.

### Additions

+ `border_fg` has been introduced to change the color of the borders.
+ `term_restore_cursor_cmd` should restore the cursor to it's usual state.
+ `vi_mode` to enable vi keybindings.
+ `sleep_key` and `sleep_cmd`.

Note: `sleep_cmd` is unset by default, meaning it's hidden and has no effect. 

### Changes

+ xinitrc can be set to null to hide it.
+ `blank_password` has been renamed to `clear_password`.
+ `save_file` has been deprecated and will be removed in a future version.

### Removals

+ `wayland_specifier` has been removed.

## Save File

The save file is now in .ini format and stored in the same directory as the config.
Older save files will be migrated to the new format.

Example:

```ini
user = ash
session_index = 0
```

## Misc

+ Display server name added next to selected session.
+ getty@tty2 has been added as a conflict in res/ly.service, so if it is running, ly should still be able to start.
+ `XDG_CURRENT_DESKTOP` is now set by ly.
+ LANG is no longer set by ly.
+ X Server PID is fetched from /tmp/X{d}.lock to be able to kill the process since it detaches.
+ Non .desktop files are now ignored in sessions directory.
+ PAM auth is now done in a child process. (Fixes some issues with logging out and back in).
+ When ly receives SIGTERM, the terminal is now cleared and existing child processes are cleaned up.
