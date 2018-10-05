#include "config.h"
#include "cylgom.h"
#include "ini.h"
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h> // login max length
#include <security/pam_appl.h>

struct lang lang = {0};
struct config config = {0};
char* info_line = NULL;

u16 compute_box_main_width()
{
	u16 login_len = strlen(lang.login);
	u16 password_len = strlen(lang.password);
	u16 label_len = login_len > password_len ? login_len : password_len;

	return 2 * config.margin_box_main_h + config.input_len + 1 + label_len;
}

// smart-dup for config loaders
void cfg_dup(char** name, const char* value)
{
	// this is not a mistake, struct was initialized with zeros
	// empty fields are zero-valued pointers because of that
	// we probably don't care about that, but let's pretend systems
	// where NULL != 0 actually exist and are used.
	if (*name != 0)
	{
		free(*name);
	}

	*name = strdup(value);
}

int config_lang_handler(void* user, const char* section, const char* name, const char* value)
{
	(void)(user);

	if (strcmp(section, "box_main") == 0)
	{
		if (strcmp(name, "login") == 0)
		{
			cfg_dup(&lang.login, value);
		}
		else if (strcmp(name, "password") == 0)
		{
			cfg_dup(&lang.password, value);
		}
		else if (strcmp(name, "f1") == 0)
		{
			cfg_dup(&lang.f1, value);
		}
		else if (strcmp(name, "f2") == 0)
		{
			cfg_dup(&lang.f2, value);
		}
		else if (strcmp(name, "shell") == 0)
		{
			cfg_dup(&lang.shell, value);
		}
		else if (strcmp(name, "xinitrc") == 0)
		{
			cfg_dup(&lang.xinitrc, value);
		}
		else if (strcmp(name, "logout") == 0)
		{
			cfg_dup(&lang.logout, value);
		}
		else if (strcmp(name, "capslock") == 0)
		{
			cfg_dup(&lang.capslock, value);
		}
		else if (strcmp(name, "numlock") == 0)
		{
			cfg_dup(&lang.numlock, value);
		}
		else if (strcmp(name, "err_pam_buf") == 0)
		{
			cfg_dup(&lang.err_pam_buf, value);
		}
		else if (strcmp(name, "err_pam_sys") == 0)
		{
			cfg_dup(&lang.err_pam_sys, value);
		}
		else if (strcmp(name, "err_pam_auth") == 0)
		{
			cfg_dup(&lang.err_pam_auth, value);
		}
		else if (strcmp(name, "err_pam_cred_insufficient") == 0)
		{
			cfg_dup(&lang.err_pam_cred_insufficient, value);
		}
		else if (strcmp(name, "err_pam_authinfo_unavail") == 0)
		{
			cfg_dup(&lang.err_pam_authinfo_unavail, value);
		}
		else if (strcmp(name, "err_pam_maxtries") == 0)
		{
			cfg_dup(&lang.err_pam_maxtries, value);
		}
		else if (strcmp(name, "err_pam_user_unknown") == 0)
		{
			cfg_dup(&lang.err_pam_user_unknown, value);
		}
		else if (strcmp(name, "err_pam_acct_expired") == 0)
		{
			cfg_dup(&lang.err_pam_acct_expired, value);
		}
		else if (strcmp(name, "err_pam_authok_reqd") == 0)
		{
			cfg_dup(&lang.err_pam_authok_reqd, value);
		}
		else if (strcmp(name, "err_pam_perm_denied") == 0)
		{
			cfg_dup(&lang.err_pam_perm_denied, value);
		}
		else if (strcmp(name, "err_pam_cred_err") == 0)
		{
			cfg_dup(&lang.err_pam_cred_err, value);
		}
		else if (strcmp(name, "err_pam_cred_expired") == 0)
		{
			cfg_dup(&lang.err_pam_cred_expired, value);
		}
		else if (strcmp(name, "err_pam_cred_unavail") == 0)
		{
			cfg_dup(&lang.err_pam_cred_unavail, value);
		}
		else if (strcmp(name, "err_pam_session") == 0)
		{
			cfg_dup(&lang.err_pam_session, value);
		}
		else if (strcmp(name, "err_pam_abort") == 0)
		{
			cfg_dup(&lang.err_pam_abort, value);
		}
		else if (strcmp(name, "err_perm_group") == 0)
		{
			cfg_dup(&lang.err_perm_group, value);
		}
		else if (strcmp(name, "err_perm_user") == 0)
		{
			cfg_dup(&lang.err_perm_user, value);
		}
		else if (strcmp(name, "err_perm_dir") == 0)
		{
			cfg_dup(&lang.err_perm_dir, value);
		}
		else if (strcmp(name, "err_console_dev") == 0)
		{
			cfg_dup(&lang.err_console_dev, value);
		}
	}

	return 1;
}

void config_lang_patch()
{
	if (lang.login == 0)
	{
		lang.login = strdup("login:");
	}
	if (lang.password == 0)
	{
		lang.password = strdup("password:");
	}
	if (lang.f1 == 0)
	{
		lang.f1 = strdup("F1 shutdown");
	}
	if (lang.f2 == 0)
	{
		lang.f2 = strdup("F2 reboot");
	}
	if (lang.shell == 0)
	{
		lang.shell = strdup("shell");
	}
	if (lang.xinitrc == 0)
	{
		lang.xinitrc = strdup("xinitrc");
	}
	if (lang.logout == 0)
	{
		lang.logout = strdup("logout");
	}
	if (lang.capslock == 0)
	{
		lang.capslock = strdup("capslock");
	}
	if (lang.numlock == 0)
	{
		lang.numlock = strdup("numlock");
	}
	if (lang.err_pam_buf == 0)
	{
		lang.err_pam_buf = strdup("memory buffer error");
	}
	if (lang.err_pam_sys == 0)
	{
		lang.err_pam_sys = strdup("system error");
	}
	if (lang.err_pam_auth == 0)
	{
		lang.err_pam_auth = strdup("authentication error");
	}
	if (lang.err_pam_cred_insufficient == 0)
	{
		lang.err_pam_cred_insufficient = strdup("insufficient credentials");
	}
	if (lang.err_pam_authinfo_unavail == 0)
	{
		lang.err_pam_authinfo_unavail = strdup("failed to get user info");
	}
	if (lang.err_pam_maxtries == 0)
	{
		lang.err_pam_maxtries = strdup("reached maximum tries limit");
	}
	if (lang.err_pam_user_unknown == 0)
	{
		lang.err_pam_user_unknown = strdup("unknown user");
	}
	if (lang.err_pam_acct_expired == 0)
	{
		lang.err_pam_acct_expired = strdup("account expired");
	}
	if (lang.err_pam_authok_reqd == 0)
	{
		lang.err_pam_authok_reqd = strdup("token expired");
	}
	if (lang.err_pam_perm_denied == 0)
	{
		lang.err_pam_perm_denied = strdup("permission denied");
	}
	if (lang.err_pam_cred_err == 0)
	{
		lang.err_pam_cred_err = strdup("failed to set credentials");
	}
	if (lang.err_pam_cred_expired == 0)
	{
		lang.err_pam_cred_expired = strdup("credentials expired");
	}
	if (lang.err_pam_cred_unavail == 0)
	{
		lang.err_pam_cred_unavail = strdup("failed to get credentials");
	}
	if (lang.err_pam_session == 0)
	{
		lang.err_pam_session = strdup("session error");
	}
	if (lang.err_pam_abort == 0)
	{
		lang.err_pam_abort = strdup("pam transaction aborted");
	}
	if (lang.err_perm_group == 0)
	{
		lang.err_perm_group = strdup("failed to downgrade group permissions");
	}
	if (lang.err_perm_user == 0)
	{
		lang.err_perm_user = strdup("failed to downgrade user permissions");
	}
	if (lang.err_perm_dir == 0)
	{
		lang.err_perm_dir = strdup("failed to change current directory");
	}
	if (lang.err_console_dev == 0)
	{
		lang.err_console_dev = strdup("failed to access console");
	}
}

void config_lang_free()
{
	free(lang.login);
	free(lang.password);
	free(lang.f1);
	free(lang.f2);
	free(lang.shell);
	free(lang.xinitrc);
	free(lang.logout);
	free(lang.capslock);
	free(lang.numlock);
	free(lang.err_pam_buf);
	free(lang.err_pam_sys);
	free(lang.err_pam_auth);
	free(lang.err_pam_cred_insufficient);
	free(lang.err_pam_authinfo_unavail);
	free(lang.err_pam_maxtries);
	free(lang.err_pam_user_unknown);
	free(lang.err_pam_acct_expired);
	free(lang.err_pam_authok_reqd);
	free(lang.err_pam_perm_denied);
	free(lang.err_pam_cred_err);
	free(lang.err_pam_cred_expired);
	free(lang.err_pam_cred_unavail);
	free(lang.err_pam_session);
	free(lang.err_pam_abort);
	free(lang.err_perm_group);
	free(lang.err_perm_user);
	free(lang.err_perm_dir);
	free(lang.err_console_dev);
}

int config_config_handler(void* user, const char* section, const char* name, const char* value)
{
	(void)(user);

	if (strcmp(section, "box_main") == 0)
	{
		if (strcmp(name, "margin_box_main_h") == 0)
		{
			config.margin_box_main_h = abs(atoi(value));
		}
		else if (strcmp(name, "margin_box_main_v") == 0)
		{
			config.margin_box_main_v = abs(atoi(value));
		}
		else if (strcmp(name, "input_len") == 0)
		{
			config.input_len = abs(atoi(value));
		}
		else if (strcmp(name, "bg") == 0)
		{
			config.bg = strtoul(value, NULL, 16);
		}
		else if (strcmp(name, "fg") == 0)
		{
			config.fg = strtoul(value, NULL, 16);
		}
		else if (strcmp(name, "max_desktop_len") == 0)
		{
			config.max_desktop_len = abs(atoi(value));
		}
		else if (strcmp(name, "max_login_len") == 0)
		{
			config.max_login_len = abs(atoi(value));
		}
		else if (strcmp(name, "max_password_len") == 0)
		{
			config.max_password_len = abs(atoi(value));
		}
		else if (strcmp(name, "min_refresh_delta") == 0)
		{
			config.min_refresh_delta = abs(atoi(value));
		}
		else if (strcmp(name, "blank_box") == 0)
		{
			config.blank_box = (atoi(value) > 0) ? true : false;
		}
		else if (strcmp(name, "force_update") == 0)
		{
			config.force_update = (atoi(value) > 0) ? true : false;
		}
		else if (strcmp(name, "animate") == 0)
		{
			config.animate = abs(atoi(value));
		}
		else if (strcmp(name, "xsessions") == 0)
		{
			cfg_dup(&config.xsessions, value);
		}
		else if (strcmp(name, "service_name") == 0)
		{
			cfg_dup(&config.service_name, value);
		}
		else if (strcmp(name, "x_cmd") == 0)
		{
			cfg_dup(&config.x_cmd, value);
		}
		else if (strcmp(name, "x_cmd_setup") == 0)
		{
			cfg_dup(&config.x_cmd_setup, value);
		}
		else if (strcmp(name, "mcookie_cmd") == 0)
		{
			cfg_dup(&config.mcookie_cmd, value);
		}
		else if (strcmp(name, "xauthority") == 0)
		{
			cfg_dup(&config.xauthority, value);
		}
		else if (strcmp(name, "path") == 0)
		{
			cfg_dup(&config.path, value);
		}
		else if (strcmp(name, "shutdown_cmd") == 0)
		{
			cfg_dup(&config.shutdown_cmd, value);
		}
		else if (strcmp(name, "console_dev") == 0)
		{
			cfg_dup(&config.console_dev, value);
		}
		else if (strcmp(name, "tty") == 0)
		{
			config.tty = abs(atoi(value));
		}
		else if (strcmp(name, "save") == 0)
		{
			config.save = (atoi(value) > 0) ? true : false;
		}
		else if (strcmp(name, "load") == 0)
		{
			config.load = (atoi(value) > 0) ? true : false;
		}
		else if (strcmp(name, "save_file") == 0)
		{
			cfg_dup(&config.save_file, value);
		}
		else if (strcmp(name, "custom_res") == 0)
		{
			config.custom_res = (atoi(value) > 0) ? true : false;
		}
		else if (strcmp(name, "res_width") == 0)
		{
			config.res_width = abs(atoi(value));
		}
		else if (strcmp(name, "res_height") == 0)
		{
			config.res_height = abs(atoi(value));
		}
		else if (strcmp(name, "hide_x") == 0)
		{
			config.hide_x = (atoi(value) > 0) ? true : false;
		}
		else if (strcmp(name, "hide_x_save_log") == 0)
		{
			cfg_dup(&config.hide_x_save_log, value);
		}
		else if (strcmp(name, "lang") == 0)
		{
			cfg_dup(&config.lang, value);
		}
	}

	return 1;
}

void config_config_patch()
{
	if (config.margin_box_main_h == 0)
	{
		config.margin_box_main_h = 2;
	}
	if (config.margin_box_main_v == 0)
	{
		config.margin_box_main_v = 1;
	}
	if (config.input_len == 0)
	{
		config.input_len = 34;
	}
	if (config.bg == 0)
	{
		config.bg = 0x000000;
	}
	if (config.fg == 0)
	{
		config.fg = 0xffffff;
	}
	if (config.max_desktop_len == 0)
	{
		// arbitrary one
		config.max_desktop_len = 100;
	}
	if (config.max_login_len == 0)
	{
		// for "useradd" the max is 32
		config.max_login_len = 32;

		#ifdef LOGIN_NAME_MAX
			if (config.max_login_len < LOGIN_NAME_MAX)
			{
				// the posix standard specifies it includes the terminating NULL
				// http://pubs.opengroup.org/onlinepubs/007908799/xsh/limits.h.html
				config.max_login_len = LOGIN_NAME_MAX - 1;
			}
		#endif

		#ifdef _POSIX_LOGIN_NAME_MAX
			if (config.max_login_len < _POSIX_LOGIN_NAME_MAX)
			{
				config.max_login_len = _POSIX_LOGIN_NAME_MAX - 1;
			}
		#endif
	}
	if (config.max_password_len == 0)
	{
		// for "passwd" the max is 200
		// https://github.com/shadow-maint/shadow/blob/master/src/passwd.c#L217
		// for "sudo" it is 255
		// https://www.sudo.ws/repos/sudo/file/tip/include/sudo_plugin.h
		// https://www.sudo.ws/repos/sudo/file/tip/src/sudo.c
		// "su" and "login" user linux-pam and do not seem to have a limit
		config.max_password_len = 255;
	}
	if (config.min_refresh_delta == 0)
	{
		config.min_refresh_delta = 1000;
	}
	if (config.xsessions == 0)
	{
		config.xsessions = strdup("/usr/share/xsessions");
	}
	if (config.service_name == 0)
	{
		config.service_name = strdup("login");
	}
	if (config.x_cmd == 0)
	{
		config.x_cmd = strdup("/usr/bin/X");
	}
	if (config.x_cmd_setup == 0)
	{
		config.x_cmd_setup = strdup("/etc/ly/xsetup.sh");
	}
	if (config.mcookie_cmd == 0)
	{
		config.mcookie_cmd = strdup("/usr/bin/mcookie");
	}
	if (config.xauthority == 0)
	{
		config.xauthority = strdup(".lyxauth");
	}
	if (config.path == 0)
	{
		config.path = strdup("/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/bin/env");
	}
	if (config.shutdown_cmd == 0)
	{
		config.shutdown_cmd = strdup("/sbin/shutdown");
	}
	if (config.console_dev == 0)
	{
		config.console_dev = strdup("/dev/console");
	}
	if (config.tty == 0)
	{
		config.tty = 2;
	}
	if (config.save_file == 0)
	{
		config.save_file = strdup("/etc/ly/ly.save");
	}
	if ((config.res_width == 0) || (config.res_height == 0))
	{
		config.custom_res = false;
	}
	if (config.hide_x_save_log == 0)
	{
		config.hide_x_save_log = strdup("/dev/null");
	}
	if (config.lang == 0)
	{
		config.lang = strdup("/etc/ly/lang/en.ini");
	}

	// fill secret parameters
	config.box_main_w = compute_box_main_width();
	config.box_main_h = 9;
}

void config_config_free()
{
	free(config.xsessions);
	free(config.service_name);
	free(config.x_cmd);
	free(config.x_cmd_setup);
	free(config.mcookie_cmd);
	free(config.xauthority);
	free(config.path);
	free(config.shutdown_cmd);
	free(config.console_dev);
	free(config.save_file);
	free(config.hide_x_save_log);
	free(config.lang);
}

// loads the ini configs
void config_load(const char* file_config)
{
	// we don't care about this function's success
	ini_parse(file_config, config_config_handler, NULL);
	ini_parse(config.lang, config_lang_handler, NULL);
	// because we check for missing strings anyway
	config_lang_patch(); // config patch depends on lang
	config_config_patch(); // so we call them in this order
}

void set_error(enum err error)
{
	switch (error)
	{
		case ERR_PERM_GROUP:
			info_line = lang.err_perm_group;
			break;
		case ERR_PERM_USER:
			info_line = lang.err_perm_user;
			break;
		case ERR_PERM_DIR:
			info_line = lang.err_perm_dir;
			break;
		default:
			info_line = lang.err_pam_abort;
			break;
	}
}

void pam_diagnose(int error)
{
	switch (error)
	{
		case PAM_BUF_ERR:
			info_line = lang.err_pam_buf;
			break;
		case PAM_SYSTEM_ERR:
			info_line = lang.err_pam_sys;
			break;
		case PAM_AUTH_ERR:
			info_line = lang.err_pam_auth;
			break;
		case PAM_CRED_INSUFFICIENT:
			info_line = lang.err_pam_cred_insufficient;
			break;
		case PAM_AUTHINFO_UNAVAIL:
			info_line = lang.err_pam_authinfo_unavail;
			break;
		case PAM_MAXTRIES:
			info_line = lang.err_pam_maxtries;
			break;
		case PAM_USER_UNKNOWN:
			info_line = lang.err_pam_user_unknown;
			break;
		case PAM_ACCT_EXPIRED:
			info_line = lang.err_pam_acct_expired;
			break;
		case PAM_NEW_AUTHTOK_REQD:
			info_line = lang.err_pam_authok_reqd;
			break;
		case PAM_PERM_DENIED:
			info_line = lang.err_pam_perm_denied;
			break;
		case PAM_CRED_ERR:
			info_line = lang.err_pam_cred_err;
			break;
		case PAM_CRED_EXPIRED:
			info_line = lang.err_pam_cred_expired;
			break;
		case PAM_CRED_UNAVAIL:
			info_line = lang.err_pam_cred_unavail;
			break;
		case PAM_SESSION_ERR:
			info_line = lang.err_pam_session;
			break;
		case PAM_ABORT:
		default:
			info_line = lang.err_pam_abort;
			break;
	}
}
