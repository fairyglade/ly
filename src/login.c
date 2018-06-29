#define _XOPEN_SOURCE 700
#define _DEFAULT_SOURCE

/* std lib */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
/* linux */
#include <sys/wait.h>
#include <paths.h>
#include <unistd.h>
#include <sys/types.h>
#include <linux/limits.h>
#include <grp.h>
#include <pwd.h>
#include <signal.h>
#include <X11/Xlib.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
/* ncurses */
#include <form.h>
/* pam */
#include <security/pam_appl.h>
#include <security/pam_misc.h>
#define PAM_SYSTEMD
#include <security/pam_modules.h>
#include <security/pam_modutil.h>
/* ly */
#include "lang.h"
#include "config.h"
#include "utils.h"
#include "login.h"
#include "desktop.h"

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

int start_env(const char* username, const char* password,
const char* de_command, enum deserv_t display_server)
{
	pid_t pid_display;
	int display_status;
	/* login info */
	int pam_result;
	const char* creds[2] = {username, password};
	struct pam_conv conv = {login_conv, creds};
	struct passwd* pwd = NULL;
	pam_handle_t* login_handle;
	/* session info */
	int display_id;
	char display_name[3];
	char tty_id[3];
	char vt[5];
	/* generates console and display id and updates the environment */
	destroy_env();
	display_id = get_free_display();
	snprintf(display_name, sizeof(display_name), ":%d", display_id);
	snprintf(tty_id, sizeof(tty_id), "%d", LY_CONSOLE_TTY);
	snprintf(vt, sizeof(vt), "vt%d", LY_CONSOLE_TTY);
	init_xdg(tty_id, display_name, display_server);
	/* pam_start and error handling */
	pam_result = pam_start(LY_SERVICE_NAME, username, &conv, &login_handle);

	if(pam_result != PAM_SUCCESS)
	{
		switch(pam_result)
		{
			case PAM_BUF_ERR :
				error_print(LY_ERR_PAM_BUF);
				break;

			case PAM_SYSTEM_ERR :
				error_print(LY_ERR_PAM_SYSTEM);
				break;

			case PAM_ABORT :
			default:
				error_print(LY_ERR_PAM_ABORT);
				break;
		}

		pam_end(login_handle, pam_result);
		return 1;
	}

	/* pam_authenticate and error handling */
	pam_result = pam_authenticate(login_handle, 0);

	if(pam_result != PAM_SUCCESS)
	{
		switch(pam_result)
		{
			case PAM_AUTH_ERR :
				error_print(LY_ERR_PAM_AUTH);
				break;

			case PAM_CRED_INSUFFICIENT :
				error_print(LY_ERR_PAM_CRED_INSUFFICIENT);
				break;

			case PAM_AUTHINFO_UNAVAIL :
				error_print(LY_ERR_PAM_AUTHINFO_UNAVAIL);
				break;

			case PAM_MAXTRIES :
				error_print(LY_ERR_PAM_MAXTRIES);
				break;

			case PAM_USER_UNKNOWN :
				error_print(LY_ERR_PAM_USER_UNKNOWN);
				break;

			case PAM_ABORT :
			default:
				error_print(LY_ERR_PAM_ABORT);
				break;
		}

		pam_end(login_handle, pam_result);
		return 1;
	}

	/* pam_acct_mgmt and error handling */
	pam_result = pam_acct_mgmt(login_handle, 0);

	if(pam_result != PAM_SUCCESS)
	{
		switch(pam_result)
		{
			case PAM_ACCT_EXPIRED :
				error_print(LY_ERR_PAM_ACCT_EXPIRED);
				break;

			case PAM_AUTH_ERR :
				error_print(LY_ERR_PAM_AUTH);
				break;

			case PAM_NEW_AUTHTOK_REQD :
				error_print(LY_ERR_PAM_NEW_AUTHTOK_REQD);
				break;

			case PAM_PERM_DENIED :
				error_print(LY_ERR_PAM_PERM_DENIED);
				break;

			case PAM_USER_UNKNOWN :
				error_print(LY_ERR_PAM_USER_UNKNOWN);
				break;

			default:
				error_print(LY_ERR_PAM_ABORT);
				break;
		}

		pam_end(login_handle, pam_result);
		return 1;
	}

	/* Initialise user groups */
	/* Get pwd structure for the user to get his group id */
	struct passwd* pw = getpwnam(username);

	if(!pw)
	{
		error_print(strerror(errno));
		pam_end(login_handle, pam_result);
		return 1;
	}

	int grp_result = initgroups(username, pw->pw_gid);

	if(grp_result == -1)
	{
		error_print(strerror(errno));
		pam_end(login_handle, pam_result);
		return 1;
	}

	/* pam_setcred and error handling */
	pam_result = pam_setcred(login_handle, PAM_ESTABLISH_CRED);

	if(pam_result != PAM_SUCCESS)
	{
		switch(pam_result)
		{
			case PAM_BUF_ERR :
				error_print(LY_ERR_PAM_BUF);
				break;

			case PAM_CRED_ERR :
				error_print(LY_ERR_PAM_CRED);
				break;

			case PAM_CRED_EXPIRED :
				error_print(LY_ERR_PAM_CRED_EXPIRED);
				break;

			case PAM_CRED_UNAVAIL :
				error_print(LY_ERR_PAM_CRED_UNAVAIL);
				break;

			case PAM_SYSTEM_ERR :
				error_print(LY_ERR_PAM_SYSTEM);
				break;

			case PAM_USER_UNKNOWN :
				error_print(LY_ERR_PAM_USER_UNKNOWN);
				break;

			default:
				error_print(LY_ERR_PAM_ABORT);
				break;
		}

		pam_end(login_handle, pam_result);
		return 1;
	}

	/* pam_open_session and error handling */
	pam_result = pam_open_session(login_handle, 0);

	if(pam_result != PAM_SUCCESS)
	{
		pam_setcred(login_handle, PAM_DELETE_CRED);

		switch(pam_result)
		{
			case PAM_BUF_ERR :
				error_print(LY_ERR_PAM_BUF);
				break;

			case PAM_CRED_ERR :
				error_print(LY_ERR_PAM_CRED);
				break;

			case PAM_CRED_EXPIRED :
				error_print(LY_ERR_PAM_CRED_EXPIRED);
				break;

			case PAM_CRED_UNAVAIL :
				error_print(LY_ERR_PAM_CRED_UNAVAIL);
				break;

			case PAM_SYSTEM_ERR :
				error_print(LY_ERR_PAM_SYSTEM);
				break;

			case PAM_USER_UNKNOWN :
				error_print(LY_ERR_PAM_USER_UNKNOWN);
				break;

			default:
				error_print(LY_ERR_PAM_ABORT);
				break;
		}

		pam_end(login_handle, pam_result);
		return 1;
	}

	/* login error */
	if(login_handle == NULL)
	{
		return 1;
	}

	/* temporarily exits ncurses mode */
	def_prog_mode();
	endwin();
	pwd = getpwnam(username);
	/* launches the DE */
	pid_display = fork();

	if(pid_display == 0)
	{
		/* downgrades group permissions and checks for an error */
		if(setgid(pwd->pw_gid) < 0)
		{
			error_print(LY_ERR_PERM_GROUP);
			pam_end(login_handle, pam_result);
			return 1;
		}

		/* initializes environment variables */
		init_env(login_handle, pwd);

		/* downgrades user permissions and checks for an error */
		if(setuid(pwd->pw_uid) < 0)
		{
			error_print(LY_ERR_PERM_USER);
			pam_end(login_handle, pam_result);
			return 1;
		}

		/* changes directory and checks for an error */
		if(chdir(pwd->pw_dir) < 0)
		{
			error_print(LY_ERR_PERM_DIR);
			pam_end(login_handle, pam_result);
			return 1;
		}

		/* starts the chosen environment */
		switch(display_server)
		{
			case shell:
				launch_shell(pwd, login_handle);

			case wayland:
				launch_wayland(pwd, login_handle, de_command);
				break;

			case xorg:
				launch_xorg(pwd, login_handle, de_command, display_name, vt, 0);
				break;

			case xinitrc:
			default :
				launch_xorg(pwd, login_handle, de_command, display_name, vt, 1);
				break;
		}

		exit(EXIT_SUCCESS);
	}

	/* waits for the de/shell to exit */
	waitpid(pid_display, &display_status, 0);
	/* pam_close_session and error handling */
	pam_result = pam_close_session(login_handle, 0);

	if(pam_result != PAM_SUCCESS)
	{
		switch(pam_result)
		{
			case PAM_BUF_ERR :
				error_print(LY_ERR_PAM_BUF);
				break;

			case PAM_SESSION_ERR :
				error_print(LY_ERR_PAM_SESSION);
				break;

			case PAM_ABORT :
			default:
				error_print(LY_ERR_PAM_ABORT);
				break;
		}

		pam_end(login_handle, pam_result);
		return 1;
	}

	/* pam_setcred and error handling */
	pam_result = pam_setcred(login_handle, PAM_DELETE_CRED);

	if(pam_result != PAM_SUCCESS)
	{
		switch(pam_result)
		{
			case PAM_BUF_ERR :
				error_print(LY_ERR_PAM_BUF);
				break;

			case PAM_CRED_ERR :
				error_print(LY_ERR_PAM_CRED);
				break;

			case PAM_CRED_EXPIRED :
				error_print(LY_ERR_PAM_CRED_EXPIRED);
				break;

			case PAM_CRED_UNAVAIL :
				error_print(LY_ERR_PAM_CRED_UNAVAIL);
				break;

			case PAM_SYSTEM_ERR :
				error_print(LY_ERR_PAM_SYSTEM);
				break;

			case PAM_USER_UNKNOWN :
				error_print(LY_ERR_PAM_USER_UNKNOWN);
				break;

			default:
				error_print(LY_ERR_PAM_ABORT);
				break;
		}

		pam_end(login_handle, pam_result);
		return 1;
	}

	/* pam_end and error handling */
	pam_result = pam_end(login_handle, pam_result);

	if(pam_result != PAM_SUCCESS)
	{
		error_print(LY_ERR_PAM_SYSTEM);
		refresh();
		return 1;
	}

	error_print(LY_LANG_LOGOUT);
	refresh();
	return 0;
}

void launch_xorg(struct passwd* pwd, pam_handle_t* pam_handle,
const char* de_command, const char* display_name, const char* vt,
int xinitrc)
{
	FILE* file;
	pid_t child;
	int status;
	char cmd[LY_LIM_CMD];
	char* argv[] = {pwd->pw_shell, "-l", "-c", cmd, NULL};
	extern char** environ;
	/* updates cookie */
	snprintf(cmd, sizeof(cmd), "exec xauth add %s . `%s`", display_name,
	LY_CMD_MCOOKIE);
	/* creates the file if it can't be found */
	file = fopen(getenv("XAUTHORITY"), "ab+");
	fclose(file);
	/* generates the cookie */
	child = fork();

	if(child == 0)
	{
		execl(pwd->pw_shell, pwd->pw_shell, "-c", cmd, NULL);
		exit(EXIT_SUCCESS);
	}

	waitpid(child, &status, 0);
	reset_terminal(pwd);
	snprintf(cmd, sizeof(cmd),
	"exec xinit %s %s%s -- %s %s %s -auth %s",
	LY_CMD_XSETUP,
	xinitrc ? "" : "/usr/bin/",
	de_command, LY_CMD_X,
	display_name, vt, getenv("XAUTHORITY"));
	execve(pwd->pw_shell, argv, environ);
	exit(EXIT_SUCCESS);
}

void launch_wayland(struct passwd* pwd, pam_handle_t* pam_handle,
const char* de_command)
{
	exit(EXIT_FAILURE);
}

void launch_shell(struct passwd* pwd, pam_handle_t* pam_handle)
{
	char* pos;
	char args[PATH_MAX + 2];
	reset_terminal(pwd);
	args[0] = '-';
	strncpy(args + 1, ((pos = strrchr(pwd->pw_shell,
	'/')) ? pos + 1 : pwd->pw_shell), sizeof(args) - 1);
	execl(pwd->pw_shell, args, NULL);
	exit(EXIT_SUCCESS);
}

void destroy_env(void)
{
	/* our environment */
	extern char** environ;
	/* completely destroys environment */
	environ = malloc(sizeof(char*));
	memset(environ, 0, sizeof(char*));
}

void init_xdg(const char* tty_id, const char* display_name,
enum deserv_t display_server)
{
	setenv("XDG_SESSION_CLASS", "user", 0);
	setenv("XDG_SEAT", "seat0", 0);
	setenv("XDG_VTNR", tty_id, 0);
	setenv("DISPLAY", display_name, 1);

	switch(display_server)
	{
		case shell:
			setenv("XDG_SESSION_TYPE", "tty", 0);

		case wayland:
			setenv("XDG_SESSION_TYPE", "wayland", 0);
			break;

		case xorg:
		default :
			setenv("XDG_SESSION_TYPE", "x11", 0);
			break;
	}
}

int init_env(pam_handle_t* pam_handle, struct passwd* pw)
{
	int i;
	int len;
	/* buffers */
	char tmp[PATH_MAX];
	char* buf;
	char** env;
	char* termenv = getenv("TERM");
	setenv("HOME", pw->pw_dir, 0);
	setenv("USER", pw->pw_name, 1);
	setenv("SHELL", pw->pw_shell, 1);
	setenv("LOGNAME", pw->pw_name, 1);
	snprintf(tmp, sizeof(tmp), "%s/%s", pw->pw_dir, LY_XAUTHORITY);
	setenv("XAUTHORITY", tmp, 0);
	buf = termenv ? strdup(termenv) : NULL;
	setenv("TERM", buf ? buf : "linux", 1);
	free(buf);
	len = snprintf(tmp, sizeof(tmp), "%s/%s", _PATH_MAILDIR, pw->pw_name);

	if((len > 0) && ((size_t) len < sizeof(tmp)))
	{
		setenv("MAIL", tmp, 0);
	}

	if(setenv("PATH", LY_PATH, 1))
	{
		return 0;
	}

	env = pam_getenvlist(pam_handle);

	for(i = 0; env && env[i]; i++)
	{
		putenv(env[i]);
	}

	return 1;
}

void reset_terminal(struct passwd* pwd)
{
	pid_t pid;
	int status;
	pid = fork();
	char cmd[LY_LIM_CMD];
	strncpy(cmd, "exec tput reset", sizeof(cmd));

	if(pid == 0)
	{
		execl(pwd->pw_shell, pwd->pw_shell, "-c", cmd, NULL);
		exit(EXIT_SUCCESS);
	}

	waitpid(pid, &status, 0);
}

int get_free_display(void)
{
	int i;
	char xlock[LY_LIM_PATH];

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
