#include <stdlib.h>
#include <stdio.h>
#include <dirent.h>
#include <string.h>

#include "lang.h"
#include "config.h"
#include "utils.h"
#include "desktop.h"

#define LY_XSESSION_EXEC "Exec="
#define LY_XSESSION_NAME "Name="

// searches a folder
void get_desktops(char* sessions_dir, struct delist_t* list, int* remote_count, short x)
{
	/* xsession */
	FILE* file;
	DIR* dir;
	struct dirent* dir_info;
	/* buffers */
	char path[LY_LIM_PATH];
	char* name;
	char* command;
	int count = *remote_count;

	/* reads xorg's desktop environments entries */
	dir = opendir(sessions_dir);

	/* exits if the folder can't be read */
	if(!dir)
	{
		error_print(LY_ERR_DELIST);
		end_list(list, count);
		return;
	}

	/* cycles through the folder */
	while((dir_info = readdir(dir)))
	{
		/* gets rid of ".", ".." and ".*" files */
		if((dir_info->d_name)[0] == '.')
		{
			continue;
		}

		/* opens xsession file */
		snprintf(path, sizeof(path), "%s/%s", sessions_dir,
		dir_info->d_name);
		file = fopen(path, "r");

		/* stops the entire procedure if the file can't be read */
		if(!file)
		{
			error_print(LY_ERR_DELIST);
			closedir(dir);
			break;
		}

		/* reads xsession file */
		name = NULL;
		command = NULL;
		get_props(file, &name, &command);

		/* frees memory when the entries are incomplete */
		if((name && !command) || (!name && command))
		{
			free(name ? name : command);
			break;
		}

		/* adds the new entry to the list */
		list->names = realloc(list->names,
		(count + 2) * (sizeof * (list->names)));
		list->names[count] = name;
		list->props = realloc(list->props,
		(count + 1) * (sizeof * (list->props)));
		list->props[count].cmd = command;
		list->props[count].type = x ? xorg : wayland;
		++count;
		fclose(file);
	}

	closedir(dir);
	*remote_count = count;
}

/* returns a list containing all the DE for all the display servers */
struct delist_t* list_de(void)
{
	/* de list */
	int count = 2;
	struct delist_t* list = init_list(count);

	get_desktops(LY_PATH_XSESSIONS, list, &count, true);
	get_desktops(LY_PATH_WSESSIONS, list, &count, false);
	end_list(list, count);
	return list;
}

/* writes default entries to the DE list */
struct delist_t* init_list(int count)
{
	struct delist_t* list = malloc(sizeof * list);
	list->names = malloc((count + 1) * (sizeof * (list->names)));
	list->names[0] = strdup(LY_LANG_SHELL);
	list->names[1] = strdup(LY_LANG_XINITRC);
	list->props = malloc(count * (sizeof * (list->props)));
	list->props[0].cmd = strdup("");
	list->props[0].type = shell;
	list->props[1].cmd = strdup(LY_CMD_XINITRC);
	list->props[1].type = xinitrc;
	return list;
}

void end_list(struct delist_t* list, int count)
{
	list->names[count] = NULL;
	list->count = count;
}

/* extracts the name and command of a DE from its .desktop file */
void get_props(FILE* file, char** name, char** command)
{
	char line[LY_LIM_LINE_FILE];

	while(fgets(line, sizeof(line), file))
	{
		if(!strncmp(LY_XSESSION_NAME, line, (sizeof(LY_XSESSION_NAME) - 1)))
		{
			*name = strdup(trim(line + (sizeof(LY_XSESSION_NAME) - 1)));
		}
		else if(!strncmp(LY_XSESSION_EXEC, line,
		(sizeof(LY_XSESSION_EXEC) - 1)))
		{
			*command = strdup(trim(line + (sizeof(LY_XSESSION_EXEC) - 1)));
		}

		if(*name && *command)
		{
			break;
		}
	}
}

void free_list(struct delist_t* list)
{
	int count;

	for(count = 0; count < list->count; ++count)
	{
		free(list->names[count]);
		free(list->props[count].cmd);
	}

	free(list->names);
	free(list->props);
	free(list);
}
