#!/bin/sh

. /etc/profile
. ~/.profile
. /etc/xprofile
. ~/.xprofile

xrdb -merge /etc/X11/Xresources
xrdb -merge ~/.Xresources

xinitdir="/etc/X11/xinit/xinitrc.d"
for script in $xinitdir/*; do
    . "$script"
done

~/.xsession

exec $@
