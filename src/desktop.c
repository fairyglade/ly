#define _XOPEN_SOURCE 700
#include "desktop.h"
#include "cylgom.h"
#include "ini.h"
#include "widgets.h"
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <stddef.h>
#include <dirent.h>
#include <limits.h>

char* value_name = NULL;
char* value_exec = NULL;

int desktop_handler(void* user, const char* section, const char* name, const char* value)
{
	(void)(user);

	if (strcmp(section, "Desktop Entry") == 0)
	{
		if ((strcmp(name, "Name") == 0) && (value_name == NULL))
		{
			value_name = strdup(value);
		}
		if ((strcmp(name, "Exec") == 0) && (value_exec == NULL))
		{
			value_exec = strdup(value);
		}
	}

	return 1;
}

enum err desktop_load(struct desktop* target)
{
	DIR* dir;
	struct dirent* dir_info;

	#if defined(NAME_MAX)
		char path[NAME_MAX];
	#elif defined(_POSIX_PATH_MAX)
		char path[_POSIX_PATH_MAX];
	#else
		char path[1024];
	#endif

	// checks dir existence
	if (access(config.xsessions, F_OK) == -1)
	{
		return XSESSIONS_MISSING;
	}

	// requests read access
	dir = opendir(config.xsessions);

	if (dir == NULL)
	{
		return XSESSIONS_READ;
	}

	// reads the content
	dir_info = readdir(dir);

	while (dir_info != NULL)
	{
		// skips the files starting with "."
		if ((dir_info->d_name)[0] == '.')
		{
			dir_info = readdir(dir);
			continue;
		}

		snprintf(path, (sizeof (path)) - 1, "%s/", config.xsessions);
		strncat(path, dir_info->d_name, (sizeof (path)) - 1);
		ini_parse(path, desktop_handler, NULL);

		if ((value_name != NULL) && (value_exec != NULL))
		{
			widget_desktop_add(target, value_name, value_exec, DS_XORG);
			value_name = NULL;
			value_exec = NULL;
		}

		dir_info = readdir(dir);
	}

	closedir(dir);

	return OK;
}
