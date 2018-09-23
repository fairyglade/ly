#ifndef H_DRAW
#define H_DRAW

#include "widgets.h"
#include "cylgom.h"

struct box
{
	u32 left_up;
	u32 left_down;
	u32 right_up;
	u32 right_down;
	u32 top;
	u32 bot;
	u32 left;
	u32 right;
};

void draw_init();
void draw_box();
void draw_labels();
void draw_f_commands();
void draw_lock_state();
void draw_desktop(struct desktop* target);
void draw_input(struct input* input);
void draw_input_mask(struct input* input);
void position_input(struct desktop* desktop, struct input* login, struct input* password);
void animate();
void cascade();

#endif
