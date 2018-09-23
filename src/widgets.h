#ifndef H_WIDGETS
#define H_WIDGETS

#include "cylgom.h"
#include "config.h"
#include <stdbool.h>

enum direction {LEFT, RIGHT};

struct input
{
	char* text;
	char* end;
	u64 len;

	char* cur;
	char* visible_start;
	u16 visible_len;

	u16 x;
	u16 y;
};

struct desktop
{
	char** list;
	char** cmd;
	enum display_server* display_server;

	u16 cur;
	u16 len;
	u16 visible_len;

	u16 x;
	u16 y;
};

enum err widget_desktop(struct desktop* target);
enum err widget_input(struct input* target, u64 len);
void widget_desktop_free(struct desktop* target);
void widget_input_free(struct input* target);
void widget_desktop_move_cur(struct desktop* target, enum direction dest);
enum err widget_desktop_add(struct desktop* target, char* name, char* cmd, enum display_server display_server);
void widget_input_move_cur(struct input* target, enum direction dest);
void widget_input_write(struct input* target, char ascii);
void widget_input_delete(struct input* target);
void widget_input_backspace(struct input* target);

#endif
