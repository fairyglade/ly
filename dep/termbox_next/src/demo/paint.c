#include "../termbox.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

static int curCol = 0;
static int curRune = 0;
static struct tb_cell* backbuf;
static int bbw = 0, bbh = 0;

static const uint32_t runes[] =
{
	0x20, // ' '
	0x2591, // '░'
	0x2592, // '▒'
	0x2593, // '▓'
	0x2588, // '█'
};

#define len(a) (sizeof(a)/sizeof(a[0]))

static const uint32_t colors[] =
{
	TB_BLACK,
	TB_RED,
	TB_GREEN,
	TB_YELLOW,
	TB_BLUE,
	TB_MAGENTA,
	TB_CYAN,
	TB_WHITE,
};

void updateAndDrawButtons(int* current, int x, int y, int mx, int my, int n,
	void (*attrFunc)(int, uint32_t*, uint32_t*, uint32_t*))
{
	int lx = x;
	int ly = y;

	for (int i = 0; i < n; i++)
	{
		if (lx <= mx && mx <= lx + 3 && ly <= my && my <= ly + 1)
		{
			*current = i;
		}

		uint32_t r;
		uint32_t fg, bg;
		(*attrFunc)(i, &r, &fg, &bg);
		tb_change_cell(lx + 0, ly + 0, r, fg, bg);
		tb_change_cell(lx + 1, ly + 0, r, fg, bg);
		tb_change_cell(lx + 2, ly + 0, r, fg, bg);
		tb_change_cell(lx + 3, ly + 0, r, fg, bg);
		tb_change_cell(lx + 0, ly + 1, r, fg, bg);
		tb_change_cell(lx + 1, ly + 1, r, fg, bg);
		tb_change_cell(lx + 2, ly + 1, r, fg, bg);
		tb_change_cell(lx + 3, ly + 1, r, fg, bg);
		lx += 4;
	}

	lx = x;
	ly = y;

	for (int i = 0; i < n; i++)
	{
		if (*current == i)
		{
			uint32_t fg = TB_RED | TB_BOLD;
			uint32_t bg = TB_DEFAULT;
			tb_change_cell(lx + 0, ly + 2, '^', fg, bg);
			tb_change_cell(lx + 1, ly + 2, '^', fg, bg);
			tb_change_cell(lx + 2, ly + 2, '^', fg, bg);
			tb_change_cell(lx + 3, ly + 2, '^', fg, bg);
		}

		lx += 4;
	}
}

void runeAttrFunc(int i, uint32_t* r, uint32_t* fg, uint32_t* bg)
{
	*r = runes[i];
	*fg = TB_DEFAULT;
	*bg = TB_DEFAULT;
}

void colorAttrFunc(int i, uint32_t* r, uint32_t* fg, uint32_t* bg)
{
	*r = ' ';
	*fg = TB_DEFAULT;
	*bg = colors[i];
}

void updateAndRedrawAll(int mx, int my)
{
	tb_clear();

	if (mx != -1 && my != -1)
	{
		backbuf[bbw * my + mx].ch = runes[curRune];
		backbuf[bbw * my + mx].fg = colors[curCol];
	}

	memcpy(tb_cell_buffer(), backbuf, sizeof(struct tb_cell)*bbw * bbh);
	int h = tb_height();
	updateAndDrawButtons(&curRune, 0, 0, mx, my, len(runes), runeAttrFunc);
	updateAndDrawButtons(&curCol, 0, h - 3, mx, my, len(colors), colorAttrFunc);
	tb_present();
}

void reallocBackBuffer(int w, int h)
{
	bbw = w;
	bbh = h;

	if (backbuf)
	{
		free(backbuf);
	}

	backbuf = calloc(sizeof(struct tb_cell), w * h);
}

int main(int argv, char** argc)
{
	(void)argc;
	(void)argv;
	int code = tb_init();

	if (code < 0)
	{
		fprintf(stderr, "termbox init failed, code: %d\n", code);
		return -1;
	}

	tb_select_input_mode(TB_INPUT_ESC | TB_INPUT_MOUSE);
	int w = tb_width();
	int h = tb_height();
	reallocBackBuffer(w, h);
	updateAndRedrawAll(-1, -1);

	for (;;)
	{
		struct tb_event ev;
		int mx = -1;
		int my = -1;
		int t = tb_poll_event(&ev);

		if (t == -1)
		{
			tb_shutdown();
			fprintf(stderr, "termbox poll event error\n");
			return -1;
		}

		switch (t)
		{
			case TB_EVENT_KEY:
				if (ev.key == TB_KEY_ESC)
				{
					tb_shutdown();
					return 0;
				}

				break;

			case TB_EVENT_MOUSE:
				if (ev.key == TB_KEY_MOUSE_LEFT)
				{
					mx = ev.x;
					my = ev.y;
				}

				break;

			case TB_EVENT_RESIZE:
				reallocBackBuffer(ev.w, ev.h);
				break;
		}

		updateAndRedrawAll(mx, my);
	}
}
