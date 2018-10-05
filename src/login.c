#include "config.h"
#include "login.h"
#include "widgets.h"
#include "desktop.h"
#include "termbox.h"

#include <sys/types.h>
#include <grp.h>
#include <pwd.h>
#include <signal.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <stdlib.h>

#include <security/pam_appl.h>
#include <security/pam_misc.h>

#ifdef LY_SYSTEMD
#define PAM_SYSTEMD
#endif

#include <security/pam_modules.h>
#include <security/pam_modutil.h>

int login_conv(int num_msg, const struct pam_message** msg,
	struct pam_response** resp, void* appdata_ptr)
{
	int i;
	int result = PAM_SUCCESS;

	if(!(*resp = calloc(num_msg, sizeof(struct pam_response))))
	{
		return PAM_BUF_ERR;
	}

	for(i = 0; i < num_msg; i++)
	{
		char* username, *password;

		switch(msg[i]->msg_style)
		{
			case PAM_PROMPT_ECHO_ON:
				username = ((char**) appdata_ptr)[0];
				(*resp)[i].resp = strdup(username);
				break;

			case PAM_PROMPT_ECHO_OFF:
				password = ((char**) appdata_ptr)[1];
				(*resp)[i].resp = strdup(password);
				break;

			case PAM_ERROR_MSG:
				fprintf(stderr, "%s\n", msg[i]->msg);
				result = PAM_CONV_ERR;
				break;

			case PAM_TEXT_INFO:
				printf("%s\n", msg[i]->msg);
				break;
		}

		if(result != PAM_SUCCESS)
		{
			break;
		}
	}

	if(result != PAM_SUCCESS)
	{
		free(*resp);
		*resp = 0;
	}

	return result;
}

int get_free_display()
{
	int i;
	char xlock[256];

	for(i = 0; i < 200; ++i)
	{
		snprintf(xlock, sizeof(xlock), "/tmp/.X%d-lock", i);

		if(access(xlock, F_OK) == -1)
		{
			break;
		}
	}

	return i;
}

enum err init_env(pam_handle_t* handle, struct passwd* pw)
{
	u16 i;
	u16 len;
	char tmp[256];
	char** env;
	char* termenv;
	
	termenv = getenv("TERM");
	setenv("HOME", pw->pw_dir, 0);
	setenv("USER", pw->pw_name, 1);
	setenv("SHELL", pw->pw_shell, 1);
	setenv("LOGNAME", pw->pw_name, 1);


	if (termenv)
	{
		setenv("TERM", termenv, 1);
	}
	else
	{
		setenv("TERM", "linux", 1);
	}

	snprintf(tmp, sizeof(tmp), "%s/%s", pw->pw_dir, config.xauthority);
	setenv("XAUTHORITY", tmp, 0);
	len = snprintf(tmp, sizeof(tmp), "%s/%s", _PATH_MAILDIR, pw->pw_name);

	if ((len > 0) && ((size_t) len < sizeof(tmp)))
	{
		setenv("MAIL", tmp, 0);
	}
	
	if (setenv("PATH", config.path, 1))
	{
		return ERR;
	}

	env = pam_getenvlist(handle);

	for (i = 0; env && env[i]; i++)
	{
		putenv(env[i]);
	}

	return OK;
}

void init_xdg(const char* tty_id, const char* display_name,
	enum display_server display_server)
{
	setenv("XDG_SESSION_CLASS", "user", 0);
	setenv("XDG_SEAT", "seat0", 0);
	setenv("XDG_VTNR", tty_id, 0);
	setenv("DISPLAY", display_name, 1);

	switch(display_server)
	{
		case DS_SHELL:
			setenv("XDG_SESSION_TYPE", "tty", 0);
			break;
		case DS_WAYLAND:
			setenv("XDG_SESSION_TYPE", "wayland", 0);
			break;
		case DS_XINITRC:
		case DS_XORG:
			setenv("XDG_SESSION_TYPE", "x11", 0);
			break;
	}
}

void reset_terminal(struct passwd* pwd)
{
	pid_t pid;
	int status;
	char cmd[256];

	pid = fork();
	strncpy(cmd, "exec tput reset", sizeof(cmd));

	if (pid == 0)
	{
		execl(pwd->pw_shell, pwd->pw_shell, "-c", cmd, NULL);
		exit(EXIT_SUCCESS);
	}

	waitpid(pid, &status, 0);
}

void launch_wayland(struct passwd* pwd, pam_handle_t* pam_handle,
	const char* de_command)
{
	char cmd[32];
	snprintf(cmd, 32, "exec %s", de_command);
	reset_terminal(pwd);
	execl(pwd->pw_shell, pwd->pw_shell, "-l", "-c", cmd, NULL);
	exit(EXIT_SUCCESS);
}

void launch_shell(struct passwd* pwd, pam_handle_t* pam_handle)
{
	char* pos;
	char args[256 + 2]; // arbitrary
	args[0] = '-';
	strncpy(args + 1, ((pos = strrchr(pwd->pw_shell,
		'/')) ? pos + 1 : pwd->pw_shell), sizeof(args) - 1);
	reset_terminal(pwd);
	execl(pwd->pw_shell, args, NULL);
	exit(EXIT_SUCCESS);
}

void launch_xorg(struct passwd* pwd, pam_handle_t* pam_handle,
	const char* de_command, const char* display_name, const char* vt,
	int xinitrc)
{
	FILE* file;
	pid_t child;
	int status;
	char cmd[256];

	// updates cookie
	snprintf(cmd,
		sizeof(cmd),
		"exec xauth add %s . `%s`",
		display_name,
		config.mcookie_cmd);

	file = fopen(getenv("XAUTHORITY"), "ab+");
	fclose(file);

	// generates the cookie
	child = fork();

	if(child == 0)
	{
		execl(pwd->pw_shell, pwd->pw_shell, "-c", cmd, NULL);
		exit(EXIT_SUCCESS);
	}

	waitpid(child, &status, 0);

	// starts x
	snprintf(cmd, sizeof(cmd),
		"exec xinit %s %s%s -- %s %s %s %s %s %s -auth %s",
		config.x_cmd_setup,
		xinitrc ? "" : "/usr/bin/",
		de_command, config.x_cmd,
		config.hide_x ? "-keeptty >" : "",
		config.hide_x ? config.hide_x_save_log : "",
		config.hide_x ? "2>&1" : "",
		display_name, vt, getenv("XAUTHORITY"));
	reset_terminal(pwd);
	execl(pwd->pw_shell, pwd->pw_shell, "-l", "-c", cmd, NULL);
	exit(EXIT_SUCCESS);
}

enum err login_desktop(struct desktop* desktop,
	struct input* login,
	struct input* password)
{
	int display_id;
	char display_name[3];
	pid_t display_pid;
	int display_status;

	const char* creds[2] = {login->text, password->text};
	struct pam_conv conv = {login_conv, creds};
	struct passwd* pwd = NULL;
	pam_handle_t* handle;
	int pam_result;

	enum display_server display_server = desktop->display_server[desktop->cur];
	char tty_id [3];
	char vt[5];

	display_id = get_free_display();
	snprintf(display_name, sizeof(display_name), ":%d", display_id);
	snprintf(tty_id, sizeof(tty_id), "%d", config.tty);
	snprintf(vt, sizeof(vt), "vt%d", config.tty);

	// starting pam transations
	pam_result = pam_start(config.service_name, login->text, &conv, &handle);

	if (pam_result != PAM_SUCCESS)
	{
		pam_diagnose(pam_result);
		pam_end(handle, pam_result);
		return ERR;
	}

	pam_result = pam_authenticate(handle, 0);

	if (pam_result != PAM_SUCCESS)
	{
		pam_diagnose(pam_result);
		pam_end(handle, pam_result);
		return ERR;
	}

	pam_result = pam_acct_mgmt(handle, 0);

	if (pam_result != PAM_SUCCESS)
	{
		pam_diagnose(pam_result);
		pam_end(handle, pam_result);
		return ERR;
	}

	// initializes user groups
	struct passwd* pw = getpwnam(login->text);

	if (!pw)
	{
		pam_end(handle, pam_result);
		return ERR;
	}

	int grp_result = initgroups(login->text, pw->pw_gid);

	if (grp_result == -1)
	{
		pam_end(handle, pam_result);
		return ERR;
	}

	// back to pam transactions
	pam_result = pam_setcred(handle, PAM_ESTABLISH_CRED);

	if (pam_result != PAM_SUCCESS)
	{
		pam_diagnose(pam_result);
		pam_end(handle, pam_result);
		return ERR;
	}

	pam_result = pam_open_session(handle, 0);

	if (pam_result != PAM_SUCCESS)
	{
		pam_diagnose(pam_result);
		pam_end(handle, pam_result);
		return ERR;
	}

	// login error
	if (handle == NULL)
	{
		return ERR;
	}

	pwd = getpwnam(login->text);

	// clears the password in memory
	widget_input_free(password);
	widget_input(password, config.max_password_len);

	// launches the DE
	display_pid = fork();
	
	if (display_pid == 0)
	{
		// restores regular terminal mode
		// doing this here to enable post-return cleanup
		tb_clear();
		tb_present();
		tb_shutdown();

		// initialization
		clearenv();
		init_xdg(tty_id, display_name, display_server);

		// downgrades group permissions
		if ((pwd == NULL) || (setgid(pwd->pw_gid) < 0))
		{
			set_error(ERR_PERM_GROUP);
			pam_end(handle, pam_result);
			exit(EXIT_FAILURE);
		}
		
		init_env(handle, pwd);

		// downgrades user permissions
		if (setuid(pwd->pw_uid) < 0)
		{
			set_error(ERR_PERM_USER);
			pam_end(handle, pam_result);
			exit(EXIT_FAILURE);
		}

		if (chdir(pwd->pw_dir) < 0)
		{
			set_error(ERR_PERM_DIR);
			pam_end(handle, pam_result);
			exit(EXIT_FAILURE);
		}

		switch (display_server)
		{
			case DS_SHELL:
				launch_shell(pwd, handle);
				break;
			case DS_WAYLAND:
				launch_wayland(pwd, handle, desktop->cmd[desktop->cur]);
				break;
			case DS_XORG:
				launch_xorg(pwd, handle, desktop->cmd[desktop->cur],
					display_name, vt, 0);
				break;
			case DS_XINITRC:
				launch_xorg(pwd, handle, desktop->cmd[desktop->cur],
					display_name, vt, 1);
				break;
		}

		exit(EXIT_SUCCESS);
	}

	// waits for the de/shell to exit
	waitpid(display_pid, &display_status, 0);

	tb_init();
	tb_select_output_mode(TB_OUTPUT_TRUECOLOR);

	// reloads the desktop environment list on logout
	widget_desktop_free(desktop);
	widget_desktop(desktop);
	desktop_load(desktop);

	info_line = lang.logout;
	pam_result = pam_close_session(handle, 0);

	if (pam_result != PAM_SUCCESS)
	{
		pam_diagnose(pam_result);
		pam_end(handle, pam_result);
		return ERR;
	}

	pam_result = pam_setcred(handle, PAM_DELETE_CRED);

	if (pam_result != PAM_SUCCESS)
	{
		pam_diagnose(pam_result);
		pam_end(handle, pam_result);
		return ERR;
	}

	pam_result = pam_end(handle, pam_result);

	if (pam_result != PAM_SUCCESS)
	{
		pam_diagnose(pam_result);
		pam_end(handle, pam_result);
		return ERR;
	}

	return OK;
}
