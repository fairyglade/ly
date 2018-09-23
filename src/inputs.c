#include "inputs.h"
#include "termbox.h"
#include "widgets.h"
#include "cylgom.h"
#include <stdlib.h>

void handle_desktop(void* input_struct, struct tb_event* event)
{
	struct desktop* target = (struct desktop*) input_struct;

	if ((event != NULL) && (event->type == TB_EVENT_KEY))
	{
		if (event->key == TB_KEY_ARROW_LEFT)
		{
			widget_desktop_move_cur(target, LEFT);
		}
		else if (event->key == TB_KEY_ARROW_RIGHT)
		{
			widget_desktop_move_cur(target, RIGHT);
		}
	}

	tb_set_cursor(target->x + 2, target->y);
}

void handle_text(void* input_struct, struct tb_event* event)
{
	struct input* target = (struct input*) input_struct;

	if ((event != NULL) && (event->type == TB_EVENT_KEY))
	{
		if (event->key == TB_KEY_ARROW_LEFT)
		{
			widget_input_move_cur(target, LEFT);
		}
		else if (event->key == TB_KEY_ARROW_RIGHT)
		{
			widget_input_move_cur(target, RIGHT);
		}
		else if (event->key == TB_KEY_DELETE)
		{
			widget_input_delete(target);
		}
		else if ((event->key == TB_KEY_BACKSPACE) || (event->key == TB_KEY_BACKSPACE2))
		{
			widget_input_backspace(target);
		}
		else if (((event->ch > 31) && (event->ch < 127)) || (event->key == TB_KEY_SPACE))
		{
			char buf[7] = {0};

			if (event->key == TB_KEY_SPACE)
			{
				buf[0] = ' ';
			}
			else
			{
				utf8_unicode_to_char(buf, event->ch);
			}

			widget_input_write(target, buf[0]);
		}
	}

	tb_set_cursor(target->x + (target->cur - target->visible_start), target->y);
}
