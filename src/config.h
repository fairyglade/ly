#ifndef H_CONFIG
#define H_CONFIG

#include "cylgom.h"

extern char* info_line;

#define LY_SYSTEMD
enum err {OK, ERR, SECURE_RAM, XSESSIONS_MISSING, XSESSIONS_READ, ERR_PERM_GROUP, ERR_PERM_USER, ERR_PERM_DIR};
enum display_server {DS_WAYLAND, DS_SHELL, DS_XINITRC, DS_XORG};

struct lang
{
	char* login;
	char* password;
	char* f1;
	char* f2;
	char* shell;
	char* xinitrc;
	char* logout;
	char* capslock;
	char* numlock;

	// errors
	char* err_pam_buf;
	char* err_pam_sys;
	char* err_pam_auth;
	char* err_pam_cred_insufficient;
	char* err_pam_authinfo_unavail;
	char* err_pam_maxtries;
	char* err_pam_user_unknown;
	char* err_pam_acct_expired;
	char* err_pam_authok_reqd;
	char* err_pam_perm_denied;
	char* err_pam_cred_err;
	char* err_pam_cred_expired;
	char* err_pam_cred_unavail;
	char* err_pam_session;
	char* err_pam_abort;
	char* err_perm_group;
	char* err_perm_user;
	char* err_perm_dir;
	char* err_console_dev;
};

struct config
{
	u32 bg;
	u32 fg;
	u16 box_main_w;
	u16 box_main_h;
	u16 margin_box_main_h;
	u16 margin_box_main_v;
	u16 input_len;
	u16 max_desktop_len;
	u16 max_login_len;
	u16 max_password_len;
	u16 min_refresh_delta;
	u16 old_min_refresh_delta;
	bool blank_box;
	bool force_update;
	bool old_force_update;
	u16 animate;
	char* xsessions;
	char* service_name;
	char* x_cmd;
	char* x_cmd_setup;
	char* mcookie_cmd;
	char* xauthority;
	char* path;
	char* shutdown_cmd;
	char* console_dev;
	u8 tty;
	bool save;
	bool load;
	char* save_file;
	bool custom_res;
	u16 res_width;
	u16 res_height;
	bool hide_x;
	char* hide_x_save_log;
	u8 auth_fails;
	char* lang;
};

extern struct lang lang;
extern struct config config;

void config_load(const char* file_config);
void config_config_free();
void config_lang_free();
void set_error(enum err error);
void pam_diagnose(int error);

#endif
