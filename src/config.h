#ifndef _CONFIG_H_
#define _CONFIG_H_

/* UI */
#define LY_MARGIN_H 3
#define LY_MARGIN_V 2

/* array sizes */
#define LY_LIM_LINE_FILE 256
#define LY_LIM_LINE_CONSOLE 256
#define LY_LIM_PATH 256
#define LY_LIM_CMD 256

/* behaviour */
#define LY_CFG_SAVE "/etc/ly/ly.save"
#define LY_CFG_READ_SAVE 1
#define LY_CFG_WRITE_SAVE 1
#define LY_CFG_CLR_USR 0
/* 0-10 */
#define LY_CFG_FCHANCE 7
#define LY_CFG_AUTH_TRIG 10
#define LY_CFG_FPS 60
#define LY_CFG_FMAX 100

/* commands */
#define LY_CMD_X "/usr/bin/X"
#define LY_CMD_TPUT "/usr/bin/tput"
#define LY_CMD_HALT "/sbin/shutdown"
#define LY_CMD_XINITRC ".xinitrc"
#define LY_CMD_MCOOKIE "/usr/bin/mcookie"
#define LY_XAUTHORITY ".lyxauth"

/* paths */
#define LY_PATH "/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/bin/env"
#define LY_PATH_XSESSIONS "/usr/share/xsessions"

/* console */
#define LY_CONSOLE_DEV "/dev/console"
#define LY_CONSOLE_TERM "TERM=linux"
#define LY_CONSOLE_TTY 2

/* pam breaks if you don't set the service name at "login" */
#define LY_SERVICE_NAME "login"

#endif /* _CONFIG_H_ */
