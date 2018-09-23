#ifndef H_UTIL
#define H_UTIL

#include "widgets.h"

void hostname(char** out);
void free_hostname();
void switch_tty();
void save(struct desktop* desktop, struct input* login);
void load(struct desktop* desktop, struct input* login);

#endif
