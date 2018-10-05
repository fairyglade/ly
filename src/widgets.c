#include "widgets.h"
#include "cylgom.h"
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>
#include <sys/mman.h>

enum err widget_desktop(struct desktop* target)
{
	enum err error = OK;
	
	// one default slot for the shell
	target->list = NULL;
	target->cmd = NULL;
	target->display_server = NULL;
	target->cur = 0;
	target->len = 0;

	error |= widget_desktop_add(target, strdup(lang.shell), strdup(""), DS_SHELL);
	error |= widget_desktop_add(target, strdup(lang.xinitrc), strdup(""), DS_XINITRC);

	return error;
}

enum err widget_input(struct input* target, u64 len)
{
	enum err error = OK;
	int ret;

	target->text = malloc(len + 1);

	if (target->text == NULL)
	{
		error = ERR;
	}
	else
	{
		// lock inputs memory so it won't swap and leak the password
		// probably not relevant as most software is insecure as hell,
		// but hey are we trying to write good code or not?
		ret = mlock(target->text, len + 1);

		if (ret < 0)
		{
			error = SECURE_RAM;
		}

		memset(target->text, 0, len + 1);
	}

	target->cur = target->text;
	target->end = target->text;
	target->visible_start = target->text;
	target->len = len;

	return error;
}

void widget_desktop_free(struct desktop* target)
{
	if (target != NULL)
	{
		for (u16 i = 0; i < target->len; ++i)
		{
			if (target->list[i] != NULL)
			{
				free(target->list[i]);
			}
			if (target->cmd[i] != NULL)
			{
				free(target->cmd[i]);
			}
		}

		free(target->list);
		free(target->cmd);
		free(target->display_server);
	}
}

void widget_input_free(struct input* target)
{
	// wipes the passord from memory and
	// restores the buffer's address as swappable
	memset(target->text, 0, target->len);
	munlock(target->text, target->len + 1);
	free(target->text);
}

void widget_desktop_move_cur(struct desktop* target, enum direction dest)
{
	if ((dest == RIGHT) && (target->cur < (target->len - 1)))
	{
		++(target->cur);
	}

	if ((dest == LEFT) && (target->cur > 0))
	{
		--(target->cur);
	}
}

enum err widget_desktop_add(struct desktop* target, char* name, char* cmd, enum display_server display_server)
{
	++(target->len);
	target->list = realloc(target->list, target->len * (sizeof (char*)));
	target->cmd = realloc(target->cmd, target->len * (sizeof (char*)));
	target->display_server = realloc(target->display_server, target->len * (sizeof (enum display_server)));
	target->cur = target->len - 1;

	if ((target->list == NULL)
		|| (target->cmd == NULL)
		|| (target->display_server == NULL))
	{
		return ERR;
	}

	target->list[target->cur] = name;
	target->cmd[target->cur] = cmd;
	target->display_server[target->cur] = display_server;

	return OK;
}

void widget_input_move_cur(struct input* target, enum direction dest)
{
	if ((dest == RIGHT) && (target->cur < target->end))
	{
		++(target->cur);

		if ((target->cur - target->visible_start) > target->visible_len)
		{
			++(target->visible_start);
		}
	}

	if ((dest == LEFT) && (target->cur > target->text))
	{
		--(target->cur);

		if ((target->cur - target->visible_start) < 0)
		{
			--(target->visible_start);
		}
	}
}

void widget_input_write(struct input* target, char ascii)
{
	if (ascii <= 0)
	{
		return; // unices do not support usernames and passwords other than ascii
	}

	if ((target->end - target->text + 1) < target->len)
	{
		// moves the text on the right to add space for the new ascii char
		memcpy(target->cur + 1, target->cur, target->end - target->cur);
		++(target->end);
		// adds the new char and moves the cursor to the right
		*(target->cur) = ascii;
		widget_input_move_cur(target, RIGHT);
	}
}

void widget_input_delete(struct input* target)
{
	if (target->cur < target->end)
	{
		// moves the text on the right to overwrite the currently pointed char
		memcpy(target->cur, target->cur + 1, target->end - target->cur + 1);
		--(target->end);
	}
}

void widget_input_backspace(struct input* target)
{
	if (target->cur > target->text)
	{
		widget_input_move_cur(target, LEFT);
		widget_input_delete(target);
	}
}
