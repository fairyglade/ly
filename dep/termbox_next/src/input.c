#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>

#include "term.h"

#define BUFFER_SIZE_MAX 16

// if s1 starts with s2 returns 1, else 0
static int starts_with(const char* s1, const char* s2)
{
	// nice huh?
	while (*s2)
	{
		if (*s1++ != *s2++)
		{
			return 0;
		}
	}

	return 1;
}

static int parse_mouse_event(struct tb_event* event, const char* buf, int len)
{
	if ((len >= 6) && starts_with(buf, "\033[M"))
	{
		// X10 mouse encoding, the simplest one
		// \033 [ M Cb Cx Cy
		int b = buf[3] - 32;

		switch (b & 3)
		{
			case 0:
				if ((b & 64) != 0)
				{
					event->key = TB_KEY_MOUSE_WHEEL_UP;
				}
				else
				{
					event->key = TB_KEY_MOUSE_LEFT;
				}

				break;

			case 1:
				if ((b & 64) != 0)
				{
					event->key = TB_KEY_MOUSE_WHEEL_DOWN;
				}
				else
				{
					event->key = TB_KEY_MOUSE_MIDDLE;
				}

				break;

			case 2:
				event->key = TB_KEY_MOUSE_RIGHT;
				break;

			case 3:
				event->key = TB_KEY_MOUSE_RELEASE;
				break;

			default:
				return -6;
		}

		event->type = TB_EVENT_MOUSE; // TB_EVENT_KEY by default

		if ((b & 32) != 0)
		{
			event->mod |= TB_MOD_MOTION;
		}

		// the coord is 1,1 for upper left
		event->x = (uint8_t)buf[4] - 1 - 32;
		event->y = (uint8_t)buf[5] - 1 - 32;
		return 6;
	}
	else if (starts_with(buf, "\033[<") || starts_with(buf, "\033["))
	{
		// xterm 1006 extended mode or urxvt 1015 extended mode
		// xterm: \033 [ < Cb ; Cx ; Cy (M or m)
		// urxvt: \033 [ Cb ; Cx ; Cy M
		int i, mi = -1, starti = -1;
		int isM, isU, s1 = -1, s2 = -1;
		int n1 = 0, n2 = 0, n3 = 0;

		for (i = 0; i < len; i++)
		{
			// We search the first (s1) and the last (s2) ';'
			if (buf[i] == ';')
			{
				if (s1 == -1)
				{
					s1 = i;
				}

				s2 = i;
			}

			// We search for the first 'm' or 'M'
			if ((buf[i] == 'm' || buf[i] == 'M') && mi == -1)
			{
				mi = i;
				break;
			}
		}

		if (mi == -1)
		{
			return 0;
		}

		// whether it's a capital M or not
		isM = (buf[mi] == 'M');

		if (buf[2] == '<')
		{
			isU = 0;
			starti = 3;
		}
		else
		{
			isU = 1;
			starti = 2;
		}

		if (s1 == -1 || s2 == -1 || s1 == s2)
		{
			return 0;
		}

		n1 = strtoul(&buf[starti], NULL, 10);
		n2 = strtoul(&buf[s1 + 1], NULL, 10);
		n3 = strtoul(&buf[s2 + 1], NULL, 10);

		if (isU)
		{
			n1 -= 32;
		}

		switch (n1 & 3)
		{
			case 0:
				if ((n1 & 64) != 0)
				{
					event->key = TB_KEY_MOUSE_WHEEL_UP;
				}
				else
				{
					event->key = TB_KEY_MOUSE_LEFT;
				}

				break;

			case 1:
				if ((n1 & 64) != 0)
				{
					event->key = TB_KEY_MOUSE_WHEEL_DOWN;
				}
				else
				{
					event->key = TB_KEY_MOUSE_MIDDLE;
				}

				break;

			case 2:
				event->key = TB_KEY_MOUSE_RIGHT;
				break;

			case 3:
				event->key = TB_KEY_MOUSE_RELEASE;
				break;

			default:
				return mi + 1;
		}

		if (!isM)
		{
			// on xterm mouse release is signaled by lowercase m
			event->key = TB_KEY_MOUSE_RELEASE;
		}

		event->type = TB_EVENT_MOUSE; // TB_EVENT_KEY by default

		if ((n1 & 32) != 0)
		{
			event->mod |= TB_MOD_MOTION;
		}

		event->x = (uint8_t)n2 - 1;
		event->y = (uint8_t)n3 - 1;
		return mi + 1;
	}

	return 0;
}

// convert escape sequence to event, and return consumed bytes on success (failure == 0)
static int parse_escape_seq(struct tb_event* event, const char* buf, int len)
{
	int mouse_parsed = parse_mouse_event(event, buf, len);

	if (mouse_parsed != 0)
	{
		return mouse_parsed;
	}

	// it's pretty simple here, find 'starts_with' match and return success, else return failure
	int i;

	for (i = 0; keys[i]; i++)
	{
		if (starts_with(buf, keys[i]))
		{
			event->ch = 0;
			event->key = 0xFFFF - i;
			return strlen(keys[i]);
		}
	}

	return 0;
}

bool extract_event(struct tb_event* event, struct ringbuffer* inbuf,
	int inputmode)
{
	char buf[BUFFER_SIZE_MAX + 1];
	int nbytes = ringbuffer_data_size(inbuf);

	if (nbytes > BUFFER_SIZE_MAX)
	{
		nbytes = BUFFER_SIZE_MAX;
	}

	if (nbytes == 0)
	{
		return false;
	}

	ringbuffer_read(inbuf, buf, nbytes);
	buf[nbytes] = '\0';

	if (buf[0] == '\033')
	{
		int n = parse_escape_seq(event, buf, nbytes);

		if (n != 0)
		{
			bool success = true;

			if (n < 0)
			{
				success = false;
				n = -n;
			}

			ringbuffer_pop(inbuf, 0, n);
			return success;
		}
		else
		{
			// it's not escape sequence, then it's ALT or ESC, check inputmode
			if (inputmode & TB_INPUT_ESC)
			{
				// if we're in escape mode, fill ESC event, pop buffer, return success
				event->ch = 0;
				event->key = TB_KEY_ESC;
				event->mod = 0;
				ringbuffer_pop(inbuf, 0, 1);
				return true;
			}
			else if (inputmode & TB_INPUT_ALT)
			{
				// if we're in alt mode, set ALT modifier to event and redo parsing
				event->mod = TB_MOD_ALT;
				ringbuffer_pop(inbuf, 0, 1);
				return extract_event(event, inbuf, inputmode);
			}

			assert(!"never got here");
		}
	}

	//  if we're here, this is not an escape sequence and not an alt sequence
	//  so, it's a FUNCTIONAL KEY or a UNICODE character

	// first of all check if it's a functional key*/
	if ((unsigned char)buf[0] <= TB_KEY_SPACE ||
		(unsigned char)buf[0] == TB_KEY_BACKSPACE2)
	{
		// fill event, pop buffer, return success
		event->ch = 0;
		event->key = (uint16_t)buf[0];
		ringbuffer_pop(inbuf, 0, 1);
		return true;
	}

	// feh... we got utf8 here

	// check if there is all bytes
	if (nbytes >= utf8_char_length(buf[0]))
	{
		// everything ok, fill event, pop buffer, return success
		utf8_char_to_unicode(&event->ch, buf);
		event->key = 0;
		ringbuffer_pop(inbuf, 0, utf8_char_length(buf[0]));
		return true;
	}

	return false;
}
