#define _XOPEN_SOURCE 500

/* std lib */
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
#include <sys/wait.h>
/* ncurses */
#include <form.h>
/* ly */
#include "config.h"
#include "utils.h"
/* important stuff */
#include <ctype.h>
#include <time.h>
#include <unistd.h>

void kernel_log(int mode)
{
	pid_t pid;
	int status;
	pid = fork();
	if(pid < 0) {
		perror("fork");
		exit(1);
	}

	if(pid == 0)
	{
		if(mode)
		{
			execl("/bin/dmesg", "/bin/dmesg", "-E", NULL);
		}
		else
		{
			execl("/bin/dmesg", "/bin/dmesg", "-D", NULL);
		}
		/* execl should not return */
		perror("execl");
		exit(1);
	}

	waitpid(pid, &status, 0);
	if(!WIFEXITED(status) || WEXITSTATUS(status))
		exit(1);
}

char* trim(char* s)
{
	char* end = s + strlen(s) - 1;

	while((end > s) && isspace((unsigned char) *end))
	{
		--end;
	}

	*(end + 1) = '\0';
	return s;
}

void error_init(WINDOW* win, int width, const char* s)
{
	static WINDOW* win_stack = NULL;
	static int width_stack = 0;
	char* blank;
	int i;

	if(win)
	{
		win_stack = win;
		width_stack = width;
	}

	blank = malloc((width_stack - 1) * (sizeof(char)));

	for(i = 0; i < width_stack - 2; ++i)
	{
		blank[i] = ' ';
	}

	blank[i] = '\0';
	mvwprintw(win_stack, LY_MARGIN_V, 1, blank);
	mvwprintw(win_stack, LY_MARGIN_V, (width_stack - strlen(s)) / 2, s);
	free(blank);
}

void error_print(const char* s)
{
	error_init(NULL, 0, s);
}

chtype get_curses_char(int y, int x)
{
	return mvwinch(newscr, y, x);
}

void cascade(void)
{
	int rows;
	int cols;
	int x;
	int y;
	chtype char_cur;
	chtype char_under;
	time_t time_start;
	time_t time_end;
	time_t time_rand;
	int fps = LY_CFG_FPS;
	int frame_target = LY_CFG_FMAX;
	int frame_count;
	float time_frame;
	float time_delta = 1.0 / fps;
	getmaxyx(stdscr, rows, cols);
	time(&time_rand);
	srand((unsigned) time_rand);

	for(frame_count = 0; frame_count < frame_target; ++frame_count)
	{
		time_start = clock();

		for(y = 0; y < rows; ++y)
		{
			for(x = 0; x < cols; ++x)
			{
				char_cur = get_curses_char(y, x);

				if(isspace(char_cur & A_CHARTEXT))
				{
					continue;
				}

				char_under = get_curses_char(y + 1, x);

				if(!isspace(char_under & A_CHARTEXT))
				{
					continue;
				}

				if(((rand() % 10) > LY_CFG_FCHANCE) && (frame_count > 0))
				{
					continue;
				}

				mvaddch(y, x, ' ');
				mvaddch(y + 1, x, char_cur);
			}
		}

		refresh();
		time_end = clock();
		time_frame = (time_end - time_start) / CLOCKS_PER_SEC;

		if(time_frame < time_delta)
		{
			usleep((time_delta - time_frame) * 1000000);
		}
	}
}
