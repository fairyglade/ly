#ifndef _UTILS_H_
#define _UTILS_H_

/* ncurses */
#include <form.h>

void kernel_log(int mode);
char* trim(char* s);
char* strdup(const char* src);
void error_init(WINDOW* win, int width, const char* s);
void error_print(const char* s);
chtype get_curses_char(int y, int x);
void cascade(void);

#endif /* _UTILS_H_ */
