capslock: []const u8 = "capslock",
err_alloc: []const u8 = "failed memory allocation",
err_bounds: []const u8 = "out-of-bounds index",
err_chdir: []const u8 = "failed to open home folder",
err_console_dev: []const u8 = "failed to access console",
err_dgn_oob: []const u8 = "log message",
err_domain: []const u8 = "invalid domain",
err_hostname: []const u8 = "failed to get hostname",
err_mlock: []const u8 = "failed to lock password memory",
err_null: []const u8 = "null pointer",
err_pam: []const u8 = "pam transaction failed",
err_pam_abort: []const u8 = "pam transaction aborted",
err_pam_acct_expired: []const u8 = "account expired",
err_pam_auth: []const u8 = "authentication error",
err_pam_authinfo_unavail: []const u8 = "failed to get user info",
err_pam_authok_reqd: []const u8 = "token expired",
err_pam_buf: []const u8 = "memory buffer error",
err_pam_cred_err: []const u8 = "failed to set credentials",
err_pam_cred_expired: []const u8 = "credentials expired",
err_pam_cred_insufficient: []const u8 = "insufficient credentials",
err_pam_cred_unavail: []const u8 = "failed to get credentials",
err_pam_maxtries: []const u8 = "reached maximum tries limit",
err_pam_perm_denied: []const u8 = "permission denied",
err_pam_session: []const u8 = "session error",
err_pam_sys: []const u8 = "system error",
err_pam_user_unknown: []const u8 = "unknown user",
err_path: []const u8 = "failed to set path",
err_perm_dir: []const u8 = "failed to change current directory",
err_perm_group: []const u8 = "failed to downgrade group permissions",
err_perm_user: []const u8 = "failed to downgrade user permissions",
err_pwnam: []const u8 = "failed to get user info",
err_user_gid: []const u8 = "failed to set user GID",
err_user_init: []const u8 = "failed to initialize user",
err_user_uid: []const u8 = "failed to set user UID",
err_xsessions_dir: []const u8 = "failed to find sessions folder",
err_xsessions_open: []const u8 = "failed to open sessions folder",
insert: []const u8 = "insert",
login: []const u8 = "login:",
logout: []const u8 = "logged out",
normal: []const u8 = "normal",
numlock: []const u8 = "numlock",
other: []const u8 = "other",
password: []const u8 = "password:",
restart: []const u8 = "reboot",
shell: []const u8 = "shell",
shutdown: []const u8 = "shutdown",
sleep: []const u8 = "sleep",
wayland: []const u8 = "wayland",
xinitrc: []const u8 = "xinitrc",
x11: []const u8 = "x11",
