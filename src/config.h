#ifndef H_LY_CONFIG
#define H_LY_CONFIG

#include <stdbool.h>
#include <stdint.h>

enum INPUTS {
	SESSION_SWITCH,
	LOGIN_INPUT,
	PASSWORD_INPUT,
};

struct lang
{
	char* capslock;
	char* err_alloc;
	char* err_bounds;
	char* err_chdir;
	char* err_console_dev;
	char* err_dgn_oob;
	char* err_domain;
	char* err_hostname;
	char* err_mlock;
	char* err_null;
	char* err_pam;
	char* err_pam_abort;
	char* err_pam_acct_expired;
	char* err_pam_auth;
	char* err_pam_authinfo_unavail;
	char* err_pam_authok_reqd;
	char* err_pam_buf;
	char* err_pam_cred_err;
	char* err_pam_cred_expired;
	char* err_pam_cred_insufficient;
	char* err_pam_cred_unavail;
	char* err_pam_maxtries;
	char* err_pam_perm_denied;
	char* err_pam_session;
	char* err_pam_sys;
	char* err_pam_user_unknown;
	char* err_path;
	char* err_perm_dir;
	char* err_perm_group;
	char* err_perm_user;
	char* err_pwnam;
	char* err_user_gid;
	char* err_user_init;
	char* err_user_uid;
	char* err_xsessions_dir;
	char* err_xsessions_open;
	char* login;
	char* logout;
	char* numlock;
	char* password;
	char* restart;
	char* shell;
	char* shutdown;
	char* wayland;
	char* xinitrc;
};

struct config
{
	bool animate;
	uint8_t animation;
	char asterisk;
	uint8_t bg;
	bool bigclock;
	bool blank_box;
	bool blank_password;
	char* clock;
	char* console_dev;
	uint8_t default_input;
	uint8_t fg;
	bool hide_borders;
	bool hide_key_hints;
	uint8_t input_len;
	char* lang;
	bool load;
	uint8_t margin_box_h;
	uint8_t margin_box_v;
	uint8_t max_desktop_len;
	uint8_t max_login_len;
	uint8_t max_password_len;
	char* mcookie_cmd;
	uint16_t min_refresh_delta;
	char* path;
	char* restart_cmd;
	char* restart_key;
	bool save;
	char* save_file;
	char* service_name;
	char* shutdown_cmd;
	char* shutdown_key;
	char* term_reset_cmd;
	uint8_t tty;
	char* wayland_cmd;
	bool wayland_specifier;
	char* waylandsessions;
	char* x_cmd;
	char* xinitrc;
	char* x_cmd_setup;
	char* xauth_cmd;
	char* xsessions;
};

extern struct lang lang;
extern struct config config;

void config_handle_str(void* data, char** pars, const int pars_count);
void lang_load();
void config_load(const char *cfg_path);
void lang_defaults();
void config_defaults();
void lang_free();
void config_free();

#endif
