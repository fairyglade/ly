#ifndef H_LY_ANIMATIONS
#define H_LY_ANIMATIONS

#include "termbox.h"
#include "inputs.h"
#include "draw.h"

#include <stdbool.h>
#include <stdint.h>


struct matrix_dot
{
	int val;
	bool is_head;
};

struct matrix_state
{
	struct matrix_dot** grid;
	int* length;
	int* spaces;
	int* updates;
};

struct doom_state
{
	uint8_t* buf;
};

void animate_init(struct term_buf* buf);
void animate_free(struct term_buf* buf);
void animate(struct term_buf* buf);

#endif
