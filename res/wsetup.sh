#!/bin/sh
# wayland-session - run as user
# Copyright (C) 2015-2016 Pier Luigi Fiorini <pierluigi.fiorini@gmail.com>

# This file is extracted from kde-workspace (kdm/kfrontend/genkdmconf.c)
# Copyright (C) 2001-2005 Oswald Buddenhagen <ossi@kde.org>

# Note that the respective logout scripts are not sourced.
case $SHELL in
  */bash)
    [ -z "$BASH" ] && exec $SHELL $0 "$@"
    set +o posix
    [ -f $CONFIG_DIRECTORY/profile ] && . $CONFIG_DIRECTORY/profile
    if [ -f $HOME/.bash_profile ]; then
      . $HOME/.bash_profile
    elif [ -f $HOME/.bash_login ]; then
      . $HOME/.bash_login
    elif [ -f $HOME/.profile ]; then
      . $HOME/.profile
    fi
    ;;
*/zsh)
    [ -z "$ZSH_NAME" ] && exec $SHELL $0 "$@"
    [ -d $CONFIG_DIRECTORY/zsh ] && zdir=$CONFIG_DIRECTORY/zsh || zdir=$CONFIG_DIRECTORY
    zhome=${ZDOTDIR:-$HOME}
    # zshenv is always sourced automatically.
    [ -f $zdir/zprofile ] && . $zdir/zprofile
    [ -f $zhome/.zprofile ] && . $zhome/.zprofile
    [ -f $zdir/zlogin ] && . $zdir/zlogin
    [ -f $zhome/.zlogin ] && . $zhome/.zlogin
    emulate -R sh
    ;;
  */csh|*/tcsh)
    # [t]cshrc is always sourced automatically.
    # Note that sourcing csh.login after .cshrc is non-standard.
    wlsess_tmp=`mktemp /tmp/wlsess-env-XXXXXX`
    $SHELL -c "if (-f $CONFIG_DIRECTORY/csh.login) source $CONFIG_DIRECTORY/csh.login; if (-f ~/.login) source ~/.login; /bin/sh -c 'export -p' >! $wlsess_tmp"
    . $wlsess_tmp
    rm -f $wlsess_tmp
    ;;
  */fish)
    [ -f $CONFIG_DIRECTORY/profile ] && . $CONFIG_DIRECTORY/profile
    [ -f $HOME/.profile ] && . $HOME/.profile
    xsess_tmp=`mktemp /tmp/xsess-env-XXXXXX`
    $SHELL --login -c "/bin/sh -c 'export -p' > $xsess_tmp"
    . $xsess_tmp
    rm -f $xsess_tmp
    ;;
  *) # Plain sh, ksh, and anything we do not know.
    [ -f $CONFIG_DIRECTORY/profile ] && . $CONFIG_DIRECTORY/profile
    [ -f $HOME/.profile ] && . $HOME/.profile
    ;;
esac

exec "$@"
