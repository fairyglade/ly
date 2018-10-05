#define _XOPEN_SOURCE 700
#include "util.h"
#include "config.h"
#include "widgets.h"
#include "cylgom.h"

#include <string.h>
#include <unistd.h>

// hostname
#include <limits.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <stdlib.h>
#include <unistd.h>
#include <netdb.h>
#include <sys/ioctl.h>
#include <linux/vt.h>

char* hostname_backup;

void hostname(char** out)
{
	struct addrinfo hints;
	struct addrinfo* info;
	char* hostname;
	char* dot;
	int host_name_max;
	int result;

	if ((host_name_max = sysconf(_SC_HOST_NAME_MAX)) == -1)
	{
		perror("sysconf(_SC_HOST_NAME_MAX)");
		exit(1);
	}

	if ((hostname = malloc(host_name_max+1)) == NULL)
	{
		perror("malloc");
		exit(1);
	}

	gethostname(hostname, sizeof(hostname));
	memset(&hints, 0, sizeof hints);
	hints.ai_family = AF_UNSPEC;
	hints.ai_socktype = SOCK_STREAM;
	hints.ai_flags = AI_CANONNAME;
	result = getaddrinfo(hostname, "http", &hints, &info);

	if ((result == 0) && (info != NULL))
	{
		dot = strchr(info->ai_canonname, '.');
		*out = strndup(info->ai_canonname, dot - info->ai_canonname);
	}
	else
	{
		*out = strdup("");
	}

	hostname_backup = *out;
	freeaddrinfo(info);
	free(hostname);
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
