### Ly - a TUI display manager
[![CodeFactor](https://www.codefactor.io/repository/github/cylgom/ly/badge/master)](https://www.codefactor.io/repository/github/cylgom/ly/overview/master)
![ly screenshot](https://user-images.githubusercontent.com/5473047/42466218-8cb53d3c-83ae-11e8-8e53-bae3669f959c.png "ly on st")

Ly is a lightweight, TUI (ncurses-like) display manager for linux.

### Dependencies
Make sure all the following packages are properly installed and configured
on your linux distribution before going further:
- a c99 compiler (tested with gcc and tcc)
- a c standard library
- make
- linux-pam
- xorg
- xorg-xinit
- xorg-xauth
- mcookie
- tput
- shutdown

### Cloning and Compiling
This repository uses submodules, so you must clone it like so
```
git clone --recurse-submodules https://github.com/cylgom/ly.git
```

To compile you just need to launch make in the created folder
```
make
```

Check if it works on the tty you configured (default is tty2). You can
also run it in terminal emulators, but desktop environments won't start
```
sudo make run
```

Then, install Ly and the systemd service file
```
sudo make install
```

Now enable the systemd service to make it spawn on startup
```
sudo systemctl enable ly.service
```

If you need to switch between ttys after Ly's start you also have to
disable getty on Ly's tty to prevent "login" from spawning on top of it
```
sudo systemctl disable getty@tty2.service
```

If messages from other services pop over the login prompt,
edit open the configuration and make sure `force_update` is enabled
```
[box_main]
force_update=1
```

### Configuration
All the configuration takes place in `/etc/ly/config.ini`.
A complete reference is available on the wiki.

### Controls
Use the up and down arrow keys to change the current field, and the
left and right arrow keys to change the target desktop environment
while on the desktop field (above the login field).

### Tips
The numlock and capslock state is printed in the top-right corner.
Use the F1 and F2 keys to respectively shutdown and reboot.

### Additionnal informations
The name "Ly" is a tribute to the fairy from the game Rayman.
Ly was tested by oxodao, who is some seriously awesome dude.
I wish to thank linux-pam, X11 and systemd developers for not
providing anything close to a reference or documentation.
