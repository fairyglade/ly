#ifndef H_LY_INPUTS
#define H_LY_INPUTS

#include "termbox.h"
#include "ctypes.h"

enum display_server {DS_WAYLAND, DS_SHELL, DS_XINITRC, DS_XORG};

struct text
{
	char* text;
	char* end;
	i64 len;
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

void handle_desktop(void* input_struct, struct tb_event* event);
void handle_text(void* input_struct, struct tb_event* event);
void input_desktop(struct desktop* target);
void input_text(struct text* target, u64 len);
void input_desktop_free(struct desktop* target);
void input_text_free(struct text* target);
void input_desktop_right(struct desktop* target);
void input_desktop_left(struct desktop* target);
void input_desktop_add(
	struct desktop* target,
	char* name,
	char* cmd,
	enum display_server display_server);
void input_text_right(struct text* target);
void input_text_left(struct text* target);
void input_text_write(struct text* target, char ascii);
void input_text_delete(struct text* target);
void input_text_backspace(struct text* target);
void input_text_clear(struct text* target);

#endif
