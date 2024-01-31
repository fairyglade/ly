Ly will not function properly if tty2 or the one set in config isn't disabled.
To do this edit "/etc/s6/config/tty2.conf" and set ' SPAWN="no" '
Then either reboot the system or run in order "s6-rc -d change tty2", "kill $(pgrep ly-dm)", "s6-rc -u change ly-srv".
