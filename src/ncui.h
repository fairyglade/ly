#ifndef _NCUI_H_
#define _NCUI_H_

/* ncurses */
#include <form.h>

struct ncwin
{
	WINDOW* win;
	int x;
	int y;
	int width;
	int height;
};

struct ncform
{
	FORM* form;
	FIELD* fields[6];
	FIELD* active;
	int height;
	int width;
	int label_pad;
};

void init_ncurses(FILE* desc);
void init_form(struct ncform* form, char** list, int max_de,
int* de_id);
void init_win(struct ncwin* win, struct ncform* form);
void init_scene(struct ncwin* win, struct ncform* form);
void init_draw(struct ncwin* win, struct ncform* form);
void end_form(struct ncform* form);

#endif /* _NCUI_H_ */
