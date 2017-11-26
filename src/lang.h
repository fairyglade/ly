#ifndef _LANG_H_
#define _LANG_H_

/* UI strings */
#define LY_LANG_GREETING "Welcome to ly !"
#define LY_LANG_VALID_CREDS "Logged In"
#define LY_LANG_LOGOUT "Logged out"
#define LY_LANG_SHELL "shell"
#define LY_LANG_XINITRC "xinitrc"
#define LY_LANG_SHUTDOWN "shutdown"
#define LY_LANG_REBOOT "reboot"
#define LY_LANG_LOGIN "login : "
#define LY_LANG_PASSWORD "password : "

/* ioctl */
#define LY_ERR_FD "Failed to create the console file descriptor"
#define LY_ERR_FD_ADVICE "(ly probably wasn't run with enough privileges)"

/* pam */
#define LY_ERR_PAM_BUF "Memory buffer error"
#define LY_ERR_PAM_SYSTEM "System error"
#define LY_ERR_PAM_ABORT "Pam transaction aborted"
#define LY_ERR_PAM_AUTH "Authentication error"
#define LY_ERR_PAM_CRED_INSUFFICIENT "Insufficient credentials"
#define LY_ERR_PAM_AUTHINFO_UNAVAIL "Failed to get user info"
#define LY_ERR_PAM_MAXTRIES "Reached maximum tries limit"
#define LY_ERR_PAM_USER_UNKNOWN "Unknown user"
#define LY_ERR_PAM_ACCT_EXPIRED "Account expired"
#define LY_ERR_PAM_NEW_AUTHTOK_REQD "Token expired"
#define LY_ERR_PAM_PERM_DENIED "Permission denied"
#define LY_ERR_PAM_CRED "Failed to set credentials"
#define LY_ERR_PAM_CRED_EXPIRED "Credentials expired"
#define LY_ERR_PAM_CRED_UNAVAIL "Failed to get credentials"
#define LY_ERR_PAM_SESSION "Session error"
#define LY_ERR_PAM_SET_TTY "Failed to set tty for pam"
#define LY_ERR_PAM_SET_RUSER "Failed to set ruser for pam"

/* ncurses */
#define LY_ERR_NC_BUFFER "Failed to refresh ncurses buffer"

/* de listing */
#define LY_ERR_DELIST "Failed to open xsessions"

/* permissions */
#define LY_ERR_PERM_GROUP "Failed to downgrade group permissions"
#define LY_ERR_PERM_USER "Failed to downgrade user permissions"
#define LY_ERR_PERM_DIR "Failed to change current directory"

#endif /* _LANG_H_ */
