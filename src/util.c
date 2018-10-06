#include "util.h"
#include "config.h"
#include "widgets.h"
#include "cylgom.h"

#include <string.h>
#include <unistd.h>

#include <limits.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <stdlib.h>
#include <unistd.h>
#include <netdb.h>
#include <sys/ioctl.h>
#include <linux/vt.h>

static char* hostname_backup = NULL;

void hostname(char** out)
{
	if (hostname_backup != NULL)
	{
		*out = hostname_backup;
		return;
	}

	int maxlen = sysconf(_SC_HOST_NAME_MAX);
	if (maxlen < 0)
	{
		maxlen = _POSIX_HOST_NAME_MAX;
	}

	if ((hostname_backup = malloc(maxlen + 1)) == NULL)
	{
		perror("malloc");
		exit(1);
	}

	if (gethostname(hostname_backup, maxlen) < 0)
	{
		perror("gethostname");
		exit(1);
	}
	hostname_backup[maxlen] = '\0';
	*out = hostname_backup;
}

void free_hostname()
{
	free(hostname_backup);
}

void switch_tty()
{
	FILE* console = fopen(config.console_dev, "w");

	if (console == NULL)
	{
		info_line = lang.err_console_dev;
		return;
	}

	int fd = fileno(console);

	ioctl(fd, VT_ACTIVATE, config.tty);
	ioctl(fd, VT_WAITACTIVE, config.tty);

	fclose(console);
}

void save(struct desktop* desktop, struct input* login)
{
	if (config.save)
	{
		FILE* file = fopen(config.save_file, "wb+");

		if (file != NULL)
		{
			fprintf(file, "%s\n%d", login->text, desktop->cur);
			fclose(file);
		}
	}
}

void load(struct desktop* desktop, struct input* login)
{
	if (config.load == 0)
	{
		return;
	}

	FILE* file = fopen(config.save_file, "rb");

	if (file == NULL)
	{
		return;
	}

	char* line = malloc((config.max_login_len * (sizeof (char))) + 1);

	if (line == NULL)
	{
		fclose(file);
		return;
	}

	if (fgets(line, (config.max_login_len * (sizeof (char))) + 1, file))
	{
		strncpy(login->text, line, login->len);

		int len = strlen(line);

		if (len == 0)
		{
			login->end = login->text;
		}
		else
		{
			login->end = login->text + len - 1;
			login->text[len - 1] = '\0';
		}
	}
	else
	{
		fclose(file);
		free(line);
		return;
	}

	if (fgets(line, (config.max_login_len * (sizeof (char))) + 1, file))
	{
		int saved_cur = abs(atoi(line));

		if (saved_cur < desktop->len)
		{
			desktop->cur = saved_cur;
		}
	}

	fclose(file);
	free(line);
}
