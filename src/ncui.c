#define _XOPEN_SOURCE

#include "ncui.h"

/* stdlib */
#include <string.h>
#include <stdlib.h>
/* linux */
#include <sys/ioctl.h>
#include <linux/vt.h>
/* ncurses */
#include <form.h>
/* ly */
#include "lang.h"
#include "config.h"
#include "utils.h"

size_t max(size_t a, size_t b)
{
	return (a > b) ? a : b;
}

void init_ncurses(FILE* desc)
{
	int filedesc = fileno(desc);
	/* required for ncurses */
	putenv(LY_CONSOLE_TERM);
	/* switches tty */
	ioctl(filedesc, VT_ACTIVATE, LY_CONSOLE_TTY);
	ioctl(filedesc, VT_WAITACTIVE, LY_CONSOLE_TTY);
	/* ncurses startup */
	initscr();
	raw();
	noecho();
}

void init_form(struct ncform* form, char** list, int max_de, int* de_id)
{
	FILE* file;
	char line[LY_LIM_LINE_FILE];
	char user[LY_LIM_LINE_FILE];
	char* arrow_left;
	char arrow_right[3] = " >";
	int de;
	int i;

	/* opens the file */
	file = fopen(LY_CFG_SAVE, "rb");
	memset(user, '\0', LY_LIM_LINE_FILE);
	de = max_de;

	/* reads the username and DE from the save file if enabled */
	if(LY_CFG_READ_SAVE)
	{
		if(fgets(line, sizeof(line), file))
		{
			strcpy(user, line);
		}

		if(fgets(line, sizeof(line), file))
		{
			de = (unsigned int) strtol(line, NULL, 10);
		}
	}

	fclose(file);
	/* computes input padding from labels text */
	form->label_pad = max(strlen(LY_LANG_LOGIN), strlen(LY_LANG_PASSWORD));
	arrow_left = malloc((form->label_pad + 1) * (sizeof (char)));
	/* adds the left arrow */
	i = 0;
	form->fields[i] = new_field(1, form->label_pad, 0, 0, 0, 0);
	memset(arrow_left, ' ', form->label_pad);
	arrow_left[form->label_pad - 2] = '<';
	arrow_left[form->label_pad] = '\0';
	set_field_buffer(form->fields[i], 0, arrow_left);
	set_field_opts(form->fields[i], O_VISIBLE | O_PUBLIC | O_AUTOSKIP);
	/* DE list */
	++i;
	form->fields[i] = new_field(1, 32, 0, form->label_pad, 0, 0);
	set_field_type(form->fields[i], TYPE_ENUM, list);

	if(de < max_de)
	{
		set_field_buffer(form->fields[i], 0, list[de]);
		*de_id = de;
	}
	else
	{
		set_field_buffer(form->fields[i], 0, list[0]);
		*de_id = 0;
	}

	set_field_opts(form->fields[i],
	O_VISIBLE | O_PUBLIC | O_ACTIVE);
	/* adds the right arrow */
	++i;
	form->fields[i] = new_field(1, 2, 0, form->label_pad + 32, 0, 0);
	set_field_buffer(form->fields[i], 0, arrow_right);
	set_field_opts(form->fields[i], O_VISIBLE | O_PUBLIC | O_AUTOSKIP);
	/* login label */
	++i;
	form->fields[i] = new_field(1, form->label_pad, 2, 0, 0, 0);
	set_field_buffer(form->fields[i], 0, LY_LANG_LOGIN);
	set_field_opts(form->fields[i], O_VISIBLE | O_PUBLIC | O_AUTOSKIP);
	/* login field */
	++i;
	form->fields[i] = new_field(1, 32, 2, form->label_pad, 0, 0);

	if(*user)
	{
		set_field_buffer(form->fields[i], 0, user);
	}

	set_field_opts(form->fields[i],
	O_VISIBLE | O_PUBLIC | O_EDIT | O_ACTIVE);
	/* password label */
	++i;
	form->fields[i] = new_field(1, form->label_pad, 4, 0, 0, 0);
	set_field_buffer(form->fields[i], 0, LY_LANG_PASSWORD);
	set_field_opts(form->fields[i], O_VISIBLE | O_PUBLIC | O_AUTOSKIP);
	/* password field */
	++i;
	form->fields[i] = new_field(1, 32, 4, form->label_pad, 0, 0);
	set_field_opts(form->fields[i], O_VISIBLE | O_EDIT | O_ACTIVE);
	/* bound */
	++i;
	form->fields[i] = NULL;
	/* generates the form */
	form->form = new_form(form->fields);
	form_opts_off(form->form, O_BS_OVERLOAD);
	scale_form(form->form, &(form->height), &(form->width));
}

void init_win(struct ncwin* win, struct ncform* form)
{
	int rows;
	int cols;
	/* fetches screen size */
	getmaxyx(stdscr, rows, cols);
	/* adds a margin */
	win->width = LY_MARGIN_H * 2 + form->width;
	win->height = LY_MARGIN_V * 2 + form->height + 2;
	/* saves the position */
	win->y = (rows - win->height) / 2;
	win->x = (cols - win->width) / 2;
	/* generates the window */
	win->win = newwin(win->height, win->width, win->y, win->x);
	/* enables advanced input (eg. "F1" key) */
	keypad(win->win, TRUE);
}

void init_scene(struct ncwin* win, struct ncform* form)
{
	set_form_win(form->form, win->win);
	set_form_sub(form->form, derwin(win->win, form->height, form->width,
	LY_MARGIN_V + 2, LY_MARGIN_H));
}

void init_draw(struct ncwin* win, struct ncform* form)
{
	char line[LY_LIM_LINE_CONSOLE];
	/* frame */
	box(win->win, 0, 0);
	/* initializes error output and prints greeting message */
	error_init(win->win, win->width, LY_LANG_GREETING);
	/* prints shutdown & reboot hints */
	snprintf(line, sizeof(line), "F1 %s    F2 %s", LY_LANG_SHUTDOWN,
	LY_LANG_REBOOT);
	mvprintw(0, 0, line);
	/* dumps ncurses buffer */
	refresh();
	/* registers form */
	post_form(form->form);
	/* dumps window buffer */
	wrefresh(win->win);
}

void end_form(struct ncform* form)
{
	unpost_form(form->form);
	free_form(form->form);
	free_field(form->fields[0]);
	free_field(form->fields[1]);
	free_field(form->fields[2]);
	free_field(form->fields[3]);
	free_field(form->fields[4]);
	free_field(form->fields[5]);
	free_field(form->fields[6]);
}
