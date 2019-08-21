#!/bin/sh

. /etc/profile

xrdb -merge /etc/X11/Xresources
xrdb -merge ~/.Xresources

~/.xsession

exec $@
