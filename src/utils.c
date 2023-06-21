#include "configator.h"
#include "dragonfail.h"
#include "inputs.h"
#include "config.h"
#include "utils.h"

#include <dirent.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#if defined(__DragonFly__) || defined(__FreeBSD__)
	#include <sys/consio.h>
#else // linux
	#include <linux/vt.h>
#endif

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

	hostname_backup = malloc(maxlen + 1);

	if (hostname_backup == NULL)
	{
		dgn_throw(DGN_ALLOC);
		return;
	}

	if (gethostname(hostname_backup, maxlen) < 0)
	{
		dgn_throw(DGN_HOSTNAME);
		return;
	}

	hostname_backup[maxlen] = '\0';
	*out = hostname_backup;
}

void free_hostname()
{
	free(hostname_backup);
}

void switch_tty(struct term_buf* buf)
{
	FILE* console = fopen(config.console_dev, "w");

	if (console == NULL)
	{
		buf->info_line = lang.err_console_dev;
		return;
	}

	int fd = fileno(console);

	ioctl(fd, VT_ACTIVATE, config.tty);
	ioctl(fd, VT_WAITACTIVE, config.tty);

	fclose(console);
}