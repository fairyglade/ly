#include "draw.h"
#include "cylgom.h"
#include "termbox.h"
#include "util.h"
#include "config.h"
#include "widgets.h"
#include <math.h>
#include <string.h>
#include <ctype.h>
#include <stdlib.h>
#include <sys/time.h>
#include <sys/ioctl.h>
#include <linux/kd.h> 
#include <linux/vt.h>
#include <stdio.h>
#include <unistd.h>

// border chars: ┌ └ ┐ ┘ ─ ─ │ │
struct box box_main = {0x250c, 0x2514, 0x2510, 0x2518, 0x2500, 0x2500 ,0x2502, 0x2502};
// alternative border chars:
// struct box box_main = {'+', '+', '+', '+', '-', '-', '|', '|'};

u16 width = 0;
u16 height = 0;
u16 box_main_x = 0;
u16 box_main_y = 0;
u16 labels_max_len = 0;

void draw_init()
{
	if (config.custom_res)
	{
		width = config.res_width;
		height = config.res_height;
	}
	else
	{
		width = tb_width();
		height = tb_height();
	}

	if (info_line == NULL)
	{
		hostname(&info_line);
	}
}

// box outline
void draw_box()
{
	box_main_x = ((width - config.box_main_w) / 2);
	box_main_y = ((height - config.box_main_h) / 2);
	u16 box_main_x2 = ((width + config.box_main_w) / 2);
	u16 box_main_y2 = ((height + config.box_main_h) / 2);
	// corners
	tb_change_cell(box_main_x - 1,
		box_main_y - 1,
		box_main.left_up,
		config.fg,
		config.bg);
	tb_change_cell(box_main_x2 + 1,
		box_main_y - 1,
		box_main.right_up,
		config.fg,
		config.bg);
	tb_change_cell(box_main_x - 1,
		box_main_y2 + 1,
		box_main.left_down,
		config.fg,
		config.bg);
	tb_change_cell(box_main_x2 + 1,
		box_main_y2 + 1,
		box_main.right_down,
		config.fg,
		config.bg);

	// top and bottom
	struct tb_cell c1 = {box_main.top, config.fg, config.bg};
	struct tb_cell c2 = {box_main.bot, config.fg, config.bg};

	for(u8 i = 0; i <= config.box_main_w; ++i)
	{
		tb_put_cell(box_main_x + i,
			box_main_y - 1,
			&c1);
		tb_put_cell(box_main_x + i,
			box_main_y2 + 1,
			&c2);
	}

	// left and right
	c1.ch = box_main.left;
	c2.ch = box_main.right;
	// blank
	struct tb_cell blank = {' ', config.fg, config.bg};

	for(u8 i = 0; i <= config.box_main_h; ++i)
	{
		// testing in the height loop takes less cycles
		// (I know this is placebo optimization :D)
		if (config.blank_box)
		{
			for (u8 k = 0; k <= config.box_main_w; ++k)
			{
				tb_put_cell(box_main_x + k,
					box_main_y + i,
					&blank);
			}
		}

		tb_put_cell(box_main_x - 1,
			box_main_y + i,
			&c1);
		tb_put_cell(box_main_x2 + 1,
			box_main_y + i,
			&c2);
	}
}

struct tb_cell* strn_cell(char* s, u16 len)
{
	struct tb_cell* cells = malloc((sizeof (struct tb_cell)) * len);
	char* s2 = s;
	u32 c;
	
	if (cells != NULL)
	{
		for (u16 i = 0; i < len; ++i)
		{
			if ((s2 - s) >= len)
			{
				break;
			}

			s2 += utf8_char_to_unicode(&c, s2);

			cells[i].ch = c;
			cells[i].bg = config.bg;
			cells[i].fg = config.fg;
		}
	}

	return cells;
}

struct tb_cell* str_cell(char* s)
{
	return strn_cell(s, strlen(s));
}

// input labels
void draw_labels()
{
	struct tb_cell* login = str_cell(lang.login);

	tb_blit(box_main_x + config.margin_box_main_h,
		box_main_y + config.margin_box_main_v + 5,
		strlen(lang.login),
		1,
		login);

	free(login);

	struct tb_cell* password = str_cell(lang.password);

	tb_blit(box_main_x + config.margin_box_main_h,
		box_main_y + config.margin_box_main_v + 7,
		strlen(lang.password),
		1,
		password);

	free(password);

	labels_max_len = strlen(lang.login);

	if (labels_max_len < strlen(lang.password))
	{
		labels_max_len = strlen(lang.password);
	}

	if (info_line != NULL)
	{
		u16 hostname_len = strlen(info_line);
		struct tb_cell* info_cell = str_cell(info_line);

		tb_blit(box_main_x + ((config.box_main_w - hostname_len) / 2),
			box_main_y + config.margin_box_main_v,
			hostname_len,
			1,
			info_cell);
		free(info_cell);
	}
}

// F1 and F2 labels
void draw_f_commands()
{
	struct tb_cell* f1 = str_cell(lang.f1);
	tb_blit(0, 0, strlen(lang.f1), 1, f1);
	free(f1);

	struct tb_cell* f2 = str_cell(lang.f2);
	tb_blit(strlen(lang.f1) + 1, 0, strlen(lang.f2), 1, f2);
	free(f2);
}

// numlock and capslock info
void draw_lock_state()
{
	FILE* console = fopen(config.console_dev, "w");

	if (console == NULL)
	{
		info_line = lang.err_console_dev;
		return;
	}

	int fd = fileno(console);
	char ret;

	ioctl(fd, KDGKBLED, &ret);
	fclose(console);

	u16 pos_x = width - strlen(lang.numlock);

	if (((ret >> 1) & 0x01) == 1)
	{
		struct tb_cell* numlock = str_cell(lang.numlock);
		tb_blit(pos_x, 0, strlen(lang.numlock), 1, numlock);
		free(numlock);
	}

	pos_x -= strlen(lang.capslock) + 1;

	if (((ret >> 2) & 0x01) == 1)
	{
		struct tb_cell* capslock = str_cell(lang.capslock);
		tb_blit(pos_x, 0, strlen(lang.capslock), 1, capslock);
		free(capslock);
	}
}

// main box
void draw_desktop(struct desktop* target)
{
	u16 len = strlen(target->list[target->cur]);

	if (len > (target->visible_len - 3))
	{
		len = target->visible_len - 3;
	}

	tb_change_cell(target->x,
		target->y,
		'<',
		config.fg,
		config.bg);

	tb_change_cell(target->x + target->visible_len - 1,
		target->y,
		'>',
		config.fg,
		config.bg);

	for (u16 i = 0; i < len; ++i)
	{
		tb_change_cell(target->x + i + 2,
			target->y,
			target->list[target->cur][i],
			config.fg,
			config.bg);
	}
}

// classic input
void draw_input(struct input* input)
{
	u16 len = strlen(input->text);
	u16 visible_len = input->visible_len;
	struct tb_cell* cells;

	if (len > visible_len)
	{
		len = visible_len;
	}

	cells = strn_cell(input->visible_start, len);

	if (cells != NULL)
	{
		tb_blit(input->x, input->y, len, 1, cells);
		free(cells);

		for (u16 i = input->end - input->visible_start; i < visible_len; ++i)
		{
			tb_change_cell(input->x + i,
				input->y,
				' ',
				config.fg,
				config.bg);
		}
	}
}

// password input (hidden text)
void draw_input_mask(struct input* input)
{
	u16 len = strlen(input->text);
	u16 visible_len = input->visible_len;

	if (len > visible_len)
	{
		len = visible_len;
	}

	for (u16 i = 0; i < visible_len; ++i)
	{
		if (input->visible_start + i < input->end)
		{
			tb_change_cell(input->x + i,
				input->y,
				'o',
				config.fg,
				config.bg);
		}
		else
		{
			tb_change_cell(input->x + i,
				input->y,
				' ',
				config.fg,
				config.bg);
		}
	}
}

// configures the inputs accroding to the size of the screen
void position_input(struct desktop* desktop, struct input* login, struct input* password)
{
	i32 len;
	u16 x;

	x = box_main_x + config.margin_box_main_h + labels_max_len + 1;
	len = box_main_x + config.box_main_w - config.margin_box_main_h - x;

	if (len < 0)
	{
		return;
	}

	desktop->x = x;
	desktop->y = box_main_y + config.margin_box_main_v + 3;
	desktop->visible_len = len;

	login->x = x;
	login->y = box_main_y + config.margin_box_main_v + 5;
	login->visible_len = len;

	password->x = x;
	password->y = box_main_y + config.margin_box_main_v + 7;
	password->visible_len = len;
}

// background animations
// example implementation
void spiral()
{
	static struct timeval time;
	static uint64_t time_present = 0;
	static uint64_t time_past = 0;
	const struct tb_cell c1 = {'o', config.fg, config.bg};
	static f64 ini = 0;

	gettimeofday(&time, NULL);
	time_present = time.tv_usec + ((uint64_t) 1000000) * time.tv_sec;

	ini += 2 * M_PI * ((time_present - time_past) / 2000000.0);

	if (ini > (5 * 2 * M_PI))
	{
		ini = 0;
	}

	for (f64 t = 0; t < (5 * 2 * M_PI); t += 0.01)
	{
		f64 y = sin(t + ini) * (height / 2) * 0.3 * (t / (2 * M_PI)) * 1.2;
		f64 x = cos(t + ini) * (width / 2) * 0.2 * (t / (2 * M_PI)) * 1.2;

		tb_put_cell((width / 2) + x, (height / 2) + y, &c1);
	}

	time_past = time_present;
}

void animate()
{
	switch(config.animate)
	{
		case 1:
			spiral();
			break;
		case 0:
		default:
			break;
	}
}

// very important ;)
void cascade(u8* fails)
{
	u16 width = tb_width();
	u16 height = tb_height();
	struct tb_cell* buf = tb_cell_buffer();
	char c;
	char c_under;
	bool changes = false;

	for (int i = height - 2; i >= 0; --i)
	{
		for (int k = 0; k < width; ++k)
		{
			c = buf[i * width + k].ch;

			if (isspace(c))
			{
				continue;
			}

			c_under = buf[(i + 1) * width + k].ch;

			if (!isspace(c_under))
			{
				continue;
			}

			if (!changes)
			{
				changes = true;
			}

			// omg this is not cryptographically secure
			if (((rand() % 10)) > 7)
			{
				continue;
			}

			buf[(i + 1) * width + k] = buf[i * width + k];
			buf[i * width + k].ch = ' ';
		}
	}

	if (!changes)
	{
		sleep(7);
		config.auth_fails = 0;
		config.min_refresh_delta = config.old_min_refresh_delta;
		config.force_update = config.old_force_update;
	}
}
