#ifndef H_LY_DRAW
#define H_LY_DRAW

#include "termbox.h"
#include "inputs.h"

#include <stdbool.h>
#include <stdint.h>

struct box
{
	uint32_t left_up;
	uint32_t left_down;
	uint32_t right_up;
	uint32_t right_down;
	uint32_t top;
	uint32_t bot;
	uint32_t left;
	uint32_t right;
};

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

union anim_state
{
	struct doom_state* doom;
	struct matrix_state* matrix;
};

struct term_buf
{
	uint16_t width;
	uint16_t height;
	uint16_t init_width;
	uint16_t init_height;

	struct box box_chars;
	char* info_line;
	uint16_t labels_max_len;
	uint16_t box_x;
	uint16_t box_y;
	uint16_t box_width;
	uint16_t box_height;

	union anim_state astate;
};

void draw_init(struct term_buf* buf);
void draw_free(struct term_buf* buf);
void draw_box(struct term_buf* buf);

struct tb_cell* strn_cell(char* s, uint16_t len);
struct tb_cell* str_cell(char* s);

void draw_labels(struct term_buf* buf);
void draw_key_hints();
void draw_lock_state(struct term_buf* buf);
void draw_desktop(struct desktop* target);
void draw_input(struct text* input);
void draw_input_mask(struct text* input);

void position_input(
	struct term_buf* buf,
	struct desktop* desktop,
	struct text* login,
	struct text* password);

void animate_init(struct term_buf* buf);
void animate(struct term_buf* buf);
bool cascade(struct term_buf* buf, uint8_t* fails);

void draw_bigclock(struct term_buf *buf);
void draw_clock(struct term_buf *buf);

#endif
