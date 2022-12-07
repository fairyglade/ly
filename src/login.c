#include "dragonfail.h"
#include "termbox.h"

#include "inputs.h"
#include "draw.h"
#include "utils.h"
#include "config.h"
#include "login.h"

#include <errno.h>
#include <grp.h>
#include <pwd.h>
#include <security/pam_appl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <utmp.h>
#include <xcb/xcb.h>

int get_free_display()
{
	char xlock[1024];
	uint8_t i;

	for (i = 0; i < 200; ++i)
	{
		snprintf(xlock, 1024, "/tmp/.X%d-lock", i);

		if (access(xlock, F_OK) == -1)
		{
			break;
		}
	}

	return i;
}

void reset_terminal(struct passwd* pwd)
{
	pid_t pid = fork();

	if (pid == 0)
	{
		execl(pwd->pw_shell, pwd->pw_shell, "-c", config.term_reset_cmd, NULL);
		exit(EXIT_SUCCESS);
	}

	int status;
	waitpid(pid, &status, 0);
}

int login_conv(
	int num_msg,
	const struct pam_message** msg,
	struct pam_response** resp,
	void* appdata_ptr)
{
	*resp = calloc(num_msg, sizeof (struct pam_response));

	if (*resp == NULL)
	{
		return PAM_BUF_ERR;
	}

	char* username;
	char* password;
	int ok = PAM_SUCCESS;
	int i;

	for (i = 0; i < num_msg; ++i)
	{
		switch (msg[i]->msg_style)
		{
			case PAM_PROMPT_ECHO_ON:
			{
				username = ((char**) appdata_ptr)[0];
				(*resp)[i].resp = strdup(username);
				break;
			}
			case PAM_PROMPT_ECHO_OFF:
			{
				password = ((char**) appdata_ptr)[1];
				(*resp)[i].resp = strdup(password);
				break;
			}
			case PAM_ERROR_MSG:
			{
				ok = PAM_CONV_ERR;
				break;
			}
		}

		if (ok != PAM_SUCCESS)
		{
			break;
		}
	}

	if (ok != PAM_SUCCESS)
	{
		for (i = 0; i < num_msg; ++i)
		{
			if ((*resp)[i].resp == NULL)
			{
				continue;
			}

			free((*resp)[i].resp);
			(*resp)[i].resp = NULL;
		}

		free(*resp);
		*resp = NULL;
	}

	return ok;
}

void pam_diagnose(int error, struct term_buf* buf)
{
	switch (error)
	{
		case PAM_ACCT_EXPIRED:
		{
			buf->info_line = lang.err_pam_acct_expired;
			break;
		}
		case PAM_AUTH_ERR:
		{
			buf->info_line = lang.err_pam_auth;
			break;
		}
		case PAM_AUTHINFO_UNAVAIL:
		{
			buf->info_line = lang.err_pam_authinfo_unavail;
			break;
		}
		case PAM_BUF_ERR:
		{
			buf->info_line = lang.err_pam_buf;
			break;
		}
		case PAM_CRED_ERR:
		{
			buf->info_line = lang.err_pam_cred_err;
			break;
		}
		case PAM_CRED_EXPIRED:
		{
			buf->info_line = lang.err_pam_cred_expired;
			break;
		}
		case PAM_CRED_INSUFFICIENT:
		{
			buf->info_line = lang.err_pam_cred_insufficient;
			break;
		}
		case PAM_CRED_UNAVAIL:
		{
			buf->info_line = lang.err_pam_cred_unavail;
			break;
		}
		case PAM_MAXTRIES:
		{
			buf->info_line = lang.err_pam_maxtries;
			break;
		}
		case PAM_NEW_AUTHTOK_REQD:
		{
			buf->info_line = lang.err_pam_authok_reqd;
			break;
		}
		case PAM_PERM_DENIED:
		{
			buf->info_line = lang.err_pam_perm_denied;
			break;
		}
		case PAM_SESSION_ERR:
		{
			buf->info_line = lang.err_pam_session;
			break;
		}
		case PAM_SYSTEM_ERR:
		{
			buf->info_line = lang.err_pam_sys;
			break;
		}
		case PAM_USER_UNKNOWN:
		{
			buf->info_line = lang.err_pam_user_unknown;
			break;
		}
		case PAM_ABORT:
		default:
		{
			buf->info_line = lang.err_pam_abort;
			break;
		}
	}

	dgn_throw(DGN_PAM);
}

void env_init(struct passwd* pwd)
{
	extern char** environ;
	char* term = getenv("TERM");
	char* lang = getenv("LANG");
	// clean env
	environ[0] = NULL;
	
	setenv("TERM", term ? term : "linux", 1);
	setenv("HOME", pwd->pw_dir, 1);
	setenv("PWD", pwd->pw_dir, 1);
	setenv("SHELL", pwd->pw_shell, 1);
	setenv("USER", pwd->pw_name, 1);
	setenv("LOGNAME", pwd->pw_name, 1);
	setenv("LANG", lang ? lang : "C", 1);

	// Set PATH if specified in the configuration
	if (strlen(config.path))
	{
		int ok = setenv("PATH", config.path, 1);

		if (ok != 0)
		{
			dgn_throw(DGN_PATH);
		}
	}
}

void env_xdg_session(const enum display_server display_server)
{
	switch (display_server)
	{
		case DS_WAYLAND:
		{
			setenv("XDG_SESSION_TYPE", "wayland", 1);
			break;
		}
		case DS_SHELL:
		{
			setenv("XDG_SESSION_TYPE", "tty", 0);
			break;
		}
		case DS_XINITRC:
		case DS_XORG:
		{
			setenv("XDG_SESSION_TYPE", "x11", 0);
			break;
		}
	}
}

void env_xdg(const char* tty_id, const char* desktop_name)
{
    char user[20];
    snprintf(user, 20, "/run/user/%d", getuid());
    setenv("XDG_RUNTIME_DIR", user, 0);
    setenv("XDG_SESSION_CLASS", "user", 0);
    setenv("XDG_SESSION_ID", "1", 0);
    setenv("XDG_SESSION_DESKTOP", desktop_name, 0);
    setenv("XDG_SEAT", "seat0", 0);
    setenv("XDG_VTNR", tty_id, 0);
}

void add_utmp_entry(
	struct utmp *entry,
	char *username,
	pid_t display_pid
) {
	entry->ut_type = USER_PROCESS;
	entry->ut_pid = display_pid;
	strcpy(entry->ut_line, ttyname(STDIN_FILENO) + strlen("/dev/"));

	/* only correct for ptys named /dev/tty[pqr][0-9a-z] */
	strcpy(entry->ut_id, ttyname(STDIN_FILENO) + strlen("/dev/tty"));

	time((long int *) &entry->ut_time);

	strncpy(entry->ut_user, username, UT_NAMESIZE);
	memset(entry->ut_host, 0, UT_HOSTSIZE);
	entry->ut_addr = 0;
	setutent();

	pututline(entry);
}

void remove_utmp_entry(struct utmp *entry) {
	entry->ut_type = DEAD_PROCESS;
	memset(entry->ut_line, 0, UT_LINESIZE);
	entry->ut_time = 0;
	memset(entry->ut_user, 0, UT_NAMESIZE);
	setutent();
	pututline(entry);
	endutent();
}

void xauth(const char* display_name, const char* shell, char* pwd)
{
	const char* xauth_file = "lyxauth";
	char* xauth_dir = getenv("XDG_RUNTIME_DIR");
	if ((xauth_dir == NULL) || (*xauth_dir == '\0'))
	{
		xauth_dir = getenv("XDG_CONFIG_HOME");
		struct stat sb;
		if ((xauth_dir == NULL) || (*xauth_dir == '\0'))
		{
			xauth_dir = strdup(pwd);
			strcat(xauth_dir, "/.config");
			stat(xauth_dir, &sb);
			if (S_ISDIR(sb.st_mode))
			{
				strcat(xauth_dir, "/ly");
			}
			else
			{
				xauth_dir = pwd;
				xauth_file = ".lyxauth";
			}
		}
		else
		{
			strcat(xauth_dir, "/ly");
		}

		// If .config/ly/ or XDG_CONFIG_HOME/ly/ doesn't exist and can't create the directory, use pwd
		// Passing pwd beforehand is safe since stat will always evaluate false
		stat(xauth_dir, &sb);
		if (!S_ISDIR(sb.st_mode) && mkdir(xauth_dir, 0777) == -1)
		{
			xauth_dir = pwd;
			xauth_file = ".lyxauth";
		}
	}

	// trim trailing slashes
	int i = strlen(xauth_dir) - 1;
	while (xauth_dir[i] == '/') i--;
	xauth_dir[i + 1] = '\0';

	char xauthority[256];
	snprintf(xauthority, 256, "%s/%s", xauth_dir, xauth_file);
	setenv("XAUTHORITY", xauthority, 1);
	setenv("DISPLAY", display_name, 1);

	FILE* fp = fopen(xauthority, "ab+");

	if (fp != NULL)
	{
		fclose(fp);
	}

	pid_t pid = fork();

	if (pid == 0)
	{
		char cmd[1024];
		snprintf(
			cmd,
			1024,
			"%s add %s . `%s`",
			config.xauth_cmd,
			display_name,
			config.mcookie_cmd);
		execl(shell, shell, "-c", cmd, NULL);
		exit(EXIT_SUCCESS);
	}

	int status;
	waitpid(pid, &status, 0);
}

void xorg(
	struct passwd* pwd,
	const char* vt,
	const char* desktop_cmd)
{
	char display_name[4];

	snprintf(display_name, 3, ":%d", get_free_display());
	xauth(display_name, pwd->pw_shell, pwd->pw_dir);

	// start xorg
	pid_t pid = fork();

	if (pid == 0)
	{
		char x_cmd[1024];
		snprintf(
			x_cmd,
			1024,
			"%s %s %s",
			config.x_cmd,
			display_name,
			vt);
		execl(pwd->pw_shell, pwd->pw_shell, "-c", x_cmd, NULL);
		exit(EXIT_SUCCESS);
	}

	int ok;
	xcb_connection_t* xcb;

	do
	{
		xcb = xcb_connect(NULL, NULL);
		ok = xcb_connection_has_error(xcb);
		kill(pid, 0);
	}
	while((ok != 0) && (errno != ESRCH));

	if (ok != 0)
	{
		return;
	}

	pid_t xorg_pid = fork();

	if (xorg_pid == 0)
	{
		char de_cmd[1024];
		snprintf(
			de_cmd,
			1024,
			"%s %s",
			config.x_cmd_setup,
			desktop_cmd);
		execl(pwd->pw_shell, pwd->pw_shell, "-c", de_cmd, NULL);
		exit(EXIT_SUCCESS);
	}

	int status;
	waitpid(xorg_pid, &status, 0);
	xcb_disconnect(xcb);
	kill(pid, 0);

	if (errno != ESRCH)
	{
		kill(pid, SIGTERM);
		waitpid(pid, &status, 0);
	}
}

void wayland(
	struct passwd* pwd,
	const char* desktop_cmd)
{

	char cmd[1024];
	snprintf(cmd, 1024, "%s %s", config.wayland_cmd, desktop_cmd);
	execl(pwd->pw_shell, pwd->pw_shell, "-c", cmd, NULL);
}

void shell(struct passwd* pwd)
{
	const char* pos = strrchr(pwd->pw_shell, '/');
	char args[1024];
	args[0] = '-';

	if (pos != NULL)
	{
		pos = pos + 1;
	}
	else
	{
		pos = pwd->pw_shell;
	}

	strncpy(args + 1, pos, 1023);
	execl(pwd->pw_shell, args, NULL);
}

// pam_do performs the pam action specified in pam_action
// on pam_action fail, call diagnose and end pam session
int pam_do(
	int (pam_action)(struct pam_handle *, int),
	struct pam_handle *handle,
	int flags,
	struct term_buf *buf)
{
	int status = pam_action(handle, flags);

	if (status != PAM_SUCCESS) {
		pam_diagnose(status, buf);
		pam_end(handle, status);
	}

	return status;
}

void auth(
	struct desktop* desktop,
	struct text* login,
	struct text* password,
	struct term_buf* buf)
{
	int ok;

    char tty_id [3];
    snprintf(tty_id, 3, "%d", config.tty);

    // Add XDG environment variables
    env_xdg_session(desktop->display_server[desktop->cur]);
    env_xdg(tty_id, desktop->list_simple[desktop->cur]);

	// open pam session
	const char* creds[2] = {login->text, password->text};
	struct pam_conv conv = {login_conv, creds};
	struct pam_handle* handle;

	ok = pam_start(config.service_name, NULL, &conv, &handle);

	if (ok != PAM_SUCCESS)
	{
		pam_diagnose(ok, buf);
		pam_end(handle, ok);
		return;
	}

	ok = pam_do(pam_authenticate, handle, 0, buf);

	if (ok != PAM_SUCCESS)
	{
		return;
	}

	ok = pam_do(pam_acct_mgmt, handle, 0, buf);

	if (ok != PAM_SUCCESS)
	{
		return;
	}

	ok = pam_do(pam_setcred, handle, PAM_ESTABLISH_CRED, buf);

	if (ok != PAM_SUCCESS)
	{
		return;
	}

	ok = pam_do(pam_open_session, handle, 0, buf);

	if (ok != PAM_SUCCESS)
	{
		return;
	}

	// clear the credentials
	input_text_clear(password);

	// get passwd structure
	struct passwd* pwd = getpwnam(login->text);
	endpwent();

	if (pwd == NULL)
	{
		dgn_throw(DGN_PWNAM);
		pam_end(handle, ok);
		return;
	}

	// set user shell
	if (pwd->pw_shell[0] == '\0')
	{
		setusershell();

		char* shell = getusershell();

		if (shell != NULL)
		{
			strcpy(pwd->pw_shell, shell);
		}

		endusershell();
	}

	// restore regular terminal mode
	tb_clear();
	tb_present();
	tb_shutdown();

	// start desktop environment
	pid_t pid = fork();

	if (pid == 0)
	{
		// set user info
		ok = initgroups(pwd->pw_name, pwd->pw_gid);

		if (ok != 0)
		{
			dgn_throw(DGN_USER_INIT);
			exit(EXIT_FAILURE);
		}

		ok = setgid(pwd->pw_gid);

		if (ok != 0)
		{
			dgn_throw(DGN_USER_GID);
			exit(EXIT_FAILURE);
		}

		ok = setuid(pwd->pw_uid);

		if (ok != 0)
		{
			dgn_throw(DGN_USER_UID);
			exit(EXIT_FAILURE);
		}

		// get a display
		char vt[5];
		snprintf(vt, 5, "vt%d", config.tty);

		// set env (this clears the environment)
		env_init(pwd);
		// Re-add XDG environment variables from lines 508,509
		env_xdg_session(desktop->display_server[desktop->cur]);
		env_xdg(tty_id, desktop->list_simple[desktop->cur]);

		if (dgn_catch())
		{
			exit(EXIT_FAILURE);
		}

		// add pam variables
		char** env = pam_getenvlist(handle);

		for (uint16_t i = 0; env && env[i]; ++i)
		{
			putenv(env[i]);
		}

		// execute
		int ok = chdir(pwd->pw_dir);

		if (ok != 0)
		{
			dgn_throw(DGN_CHDIR);
			exit(EXIT_FAILURE);
		}

		reset_terminal(pwd);
		switch (desktop->display_server[desktop->cur])
		{
			case DS_WAYLAND:
			{
				wayland(pwd, desktop->cmd[desktop->cur]);
				break;
			}
			case DS_SHELL:
			{
				shell(pwd);
				break;
			}
			case DS_XINITRC:
			case DS_XORG:
			{
				xorg(pwd, vt, desktop->cmd[desktop->cur]);
				break;
			}
		}

		exit(EXIT_SUCCESS);
	}

	// add utmp audit
	struct utmp entry;
	add_utmp_entry(&entry, pwd->pw_name, pid);

	// wait for the session to stop
	int status;
	waitpid(pid, &status, 0);
	remove_utmp_entry(&entry);

	reset_terminal(pwd);

	// reinit termbox
	tb_init();
	tb_select_output_mode(TB_OUTPUT_NORMAL);

	// reload the desktop environment list on logout
	input_desktop_free(desktop);
	input_desktop(desktop);
	desktop_load(desktop);

	// close pam session
	ok = pam_do(pam_close_session, handle, 0, buf);

	if (ok != PAM_SUCCESS)
	{
		return;
	}

	ok = pam_do(pam_setcred, handle, PAM_DELETE_CRED, buf);

	if (ok != PAM_SUCCESS)
	{
		return;
	}

	ok = pam_end(handle, 0);

	if (ok != PAM_SUCCESS)
	{
		pam_diagnose(ok, buf);
	}
}

