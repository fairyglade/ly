#include <assert.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include "termbox.h"

struct key
{
	unsigned char x;
	unsigned char y;
	uint32_t ch;
};

#define STOP {0,0,0}
struct key K_ESC[] = {{1, 1, 'E'}, {2, 1, 'S'}, {3, 1, 'C'}, STOP};
struct key K_F1[] = {{6, 1, 'F'}, {7, 1, '1'}, STOP};
struct key K_F2[] = {{9, 1, 'F'}, {10, 1, '2'}, STOP};
struct key K_F3[] = {{12, 1, 'F'}, {13, 1, '3'}, STOP};
struct key K_F4[] = {{15, 1, 'F'}, {16, 1, '4'}, STOP};
struct key K_F5[] = {{19, 1, 'F'}, {20, 1, '5'}, STOP};
struct key K_F6[] = {{22, 1, 'F'}, {23, 1, '6'}, STOP};
struct key K_F7[] = {{25, 1, 'F'}, {26, 1, '7'}, STOP};
struct key K_F8[] = {{28, 1, 'F'}, {29, 1, '8'}, STOP};
struct key K_F9[] = {{33, 1, 'F'}, {34, 1, '9'}, STOP};
struct key K_F10[] = {{36, 1, 'F'}, {37, 1, '1'}, {38, 1, '0'}, STOP};
struct key K_F11[] = {{40, 1, 'F'}, {41, 1, '1'}, {42, 1, '1'}, STOP};
struct key K_F12[] = {{44, 1, 'F'}, {45, 1, '1'}, {46, 1, '2'}, STOP};
struct key K_PRN[] = {{50, 1, 'P'}, {51, 1, 'R'}, {52, 1, 'N'}, STOP};
struct key K_SCR[] = {{54, 1, 'S'}, {55, 1, 'C'}, {56, 1, 'R'}, STOP};
struct key K_BRK[] = {{58, 1, 'B'}, {59, 1, 'R'}, {60, 1, 'K'}, STOP};
struct key K_LED1[] = {{66, 1, '-'}, STOP};
struct key K_LED2[] = {{70, 1, '-'}, STOP};
struct key K_LED3[] = {{74, 1, '-'}, STOP};

struct key K_TILDE[] = {{1, 4, '`'}, STOP};
struct key K_TILDE_SHIFT[] = {{1, 4, '~'}, STOP};
struct key K_1[] = {{4, 4, '1'}, STOP};
struct key K_1_SHIFT[] = {{4, 4, '!'}, STOP};
struct key K_2[] = {{7, 4, '2'}, STOP};
struct key K_2_SHIFT[] = {{7, 4, '@'}, STOP};
struct key K_3[] = {{10, 4, '3'}, STOP};
struct key K_3_SHIFT[] = {{10, 4, '#'}, STOP};
struct key K_4[] = {{13, 4, '4'}, STOP};
struct key K_4_SHIFT[] = {{13, 4, '$'}, STOP};
struct key K_5[] = {{16, 4, '5'}, STOP};
struct key K_5_SHIFT[] = {{16, 4, '%'}, STOP};
struct key K_6[] = {{19, 4, '6'}, STOP};
struct key K_6_SHIFT[] = {{19, 4, '^'}, STOP};
struct key K_7[] = {{22, 4, '7'}, STOP};
struct key K_7_SHIFT[] = {{22, 4, '&'}, STOP};
struct key K_8[] = {{25, 4, '8'}, STOP};
struct key K_8_SHIFT[] = {{25, 4, '*'}, STOP};
struct key K_9[] = {{28, 4, '9'}, STOP};
struct key K_9_SHIFT[] = {{28, 4, '('}, STOP};
struct key K_0[] = {{31, 4, '0'}, STOP};
struct key K_0_SHIFT[] = {{31, 4, ')'}, STOP};
struct key K_MINUS[] = {{34, 4, '-'}, STOP};
struct key K_MINUS_SHIFT[] = {{34, 4, '_'}, STOP};
struct key K_EQUALS[] = {{37, 4, '='}, STOP};
struct key K_EQUALS_SHIFT[] = {{37, 4, '+'}, STOP};
struct key K_BACKSLASH[] = {{40, 4, '\\'}, STOP};
struct key K_BACKSLASH_SHIFT[] = {{40, 4, '|'}, STOP};
struct key K_BACKSPACE[] = {{44, 4, 0x2190}, {45, 4, 0x2500}, {46, 4, 0x2500}, STOP};
struct key K_INS[] = {{50, 4, 'I'}, {51, 4, 'N'}, {52, 4, 'S'}, STOP};
struct key K_HOM[] = {{54, 4, 'H'}, {55, 4, 'O'}, {56, 4, 'M'}, STOP};
struct key K_PGU[] = {{58, 4, 'P'}, {59, 4, 'G'}, {60, 4, 'U'}, STOP};
struct key K_K_NUMLOCK[] = {{65, 4, 'N'}, STOP};
struct key K_K_SLASH[] = {{68, 4, '/'}, STOP};
struct key K_K_STAR[] = {{71, 4, '*'}, STOP};
struct key K_K_MINUS[] = {{74, 4, '-'}, STOP};

struct key K_TAB[] = {{1, 6, 'T'}, {2, 6, 'A'}, {3, 6, 'B'}, STOP};
struct key K_q[] = {{6, 6, 'q'}, STOP};
struct key K_Q[] = {{6, 6, 'Q'}, STOP};
struct key K_w[] = {{9, 6, 'w'}, STOP};
struct key K_W[] = {{9, 6, 'W'}, STOP};
struct key K_e[] = {{12, 6, 'e'}, STOP};
struct key K_E[] = {{12, 6, 'E'}, STOP};
struct key K_r[] = {{15, 6, 'r'}, STOP};
struct key K_R[] = {{15, 6, 'R'}, STOP};
struct key K_t[] = {{18, 6, 't'}, STOP};
struct key K_T[] = {{18, 6, 'T'}, STOP};
struct key K_y[] = {{21, 6, 'y'}, STOP};
struct key K_Y[] = {{21, 6, 'Y'}, STOP};
struct key K_u[] = {{24, 6, 'u'}, STOP};
struct key K_U[] = {{24, 6, 'U'}, STOP};
struct key K_i[] = {{27, 6, 'i'}, STOP};
struct key K_I[] = {{27, 6, 'I'}, STOP};
struct key K_o[] = {{30, 6, 'o'}, STOP};
struct key K_O[] = {{30, 6, 'O'}, STOP};
struct key K_p[] = {{33, 6, 'p'}, STOP};
struct key K_P[] = {{33, 6, 'P'}, STOP};
struct key K_LSQB[] = {{36, 6, '['}, STOP};
struct key K_LCUB[] = {{36, 6, '{'}, STOP};
struct key K_RSQB[] = {{39, 6, ']'}, STOP};
struct key K_RCUB[] = {{39, 6, '}'}, STOP};
struct key K_ENTER[] =
{
	{43, 6, 0x2591}, {44, 6, 0x2591}, {45, 6, 0x2591}, {46, 6, 0x2591},
	{43, 7, 0x2591}, {44, 7, 0x2591}, {45, 7, 0x21B5}, {46, 7, 0x2591},
	{41, 8, 0x2591}, {42, 8, 0x2591}, {43, 8, 0x2591}, {44, 8, 0x2591},
	{45, 8, 0x2591}, {46, 8, 0x2591}, STOP
};
struct key K_DEL[] = {{50, 6, 'D'}, {51, 6, 'E'}, {52, 6, 'L'}, STOP};
struct key K_END[] = {{54, 6, 'E'}, {55, 6, 'N'}, {56, 6, 'D'}, STOP};
struct key K_PGD[] = {{58, 6, 'P'}, {59, 6, 'G'}, {60, 6, 'D'}, STOP};
struct key K_K_7[] = {{65, 6, '7'}, STOP};
struct key K_K_8[] = {{68, 6, '8'}, STOP};
struct key K_K_9[] = {{71, 6, '9'}, STOP};
struct key K_K_PLUS[] = {{74, 6, ' '}, {74, 7, '+'}, {74, 8, ' '}, STOP};

struct key K_CAPS[] = {{1, 8, 'C'}, {2, 8, 'A'}, {3, 8, 'P'}, {4, 8, 'S'}, STOP};
struct key K_a[] = {{7, 8, 'a'}, STOP};
struct key K_A[] = {{7, 8, 'A'}, STOP};
struct key K_s[] = {{10, 8, 's'}, STOP};
struct key K_S[] = {{10, 8, 'S'}, STOP};
struct key K_d[] = {{13, 8, 'd'}, STOP};
struct key K_D[] = {{13, 8, 'D'}, STOP};
struct key K_f[] = {{16, 8, 'f'}, STOP};
struct key K_F[] = {{16, 8, 'F'}, STOP};
struct key K_g[] = {{19, 8, 'g'}, STOP};
struct key K_G[] = {{19, 8, 'G'}, STOP};
struct key K_h[] = {{22, 8, 'h'}, STOP};
struct key K_H[] = {{22, 8, 'H'}, STOP};
struct key K_j[] = {{25, 8, 'j'}, STOP};
struct key K_J[] = {{25, 8, 'J'}, STOP};
struct key K_k[] = {{28, 8, 'k'}, STOP};
struct key K_K[] = {{28, 8, 'K'}, STOP};
struct key K_l[] = {{31, 8, 'l'}, STOP};
struct key K_L[] = {{31, 8, 'L'}, STOP};
struct key K_SEMICOLON[] = {{34, 8, ';'}, STOP};
struct key K_PARENTHESIS[] = {{34, 8, ':'}, STOP};
struct key K_QUOTE[] = {{37, 8, '\''}, STOP};
struct key K_DOUBLEQUOTE[] = {{37, 8, '"'}, STOP};
struct key K_K_4[] = {{65, 8, '4'}, STOP};
struct key K_K_5[] = {{68, 8, '5'}, STOP};
struct key K_K_6[] = {{71, 8, '6'}, STOP};

struct key K_LSHIFT[] = {{1, 10, 'S'}, {2, 10, 'H'}, {3, 10, 'I'}, {4, 10, 'F'}, {5, 10, 'T'}, STOP};
struct key K_z[] = {{9, 10, 'z'}, STOP};
struct key K_Z[] = {{9, 10, 'Z'}, STOP};
struct key K_x[] = {{12, 10, 'x'}, STOP};
struct key K_X[] = {{12, 10, 'X'}, STOP};
struct key K_c[] = {{15, 10, 'c'}, STOP};
struct key K_C[] = {{15, 10, 'C'}, STOP};
struct key K_v[] = {{18, 10, 'v'}, STOP};
struct key K_V[] = {{18, 10, 'V'}, STOP};
struct key K_b[] = {{21, 10, 'b'}, STOP};
struct key K_B[] = {{21, 10, 'B'}, STOP};
struct key K_n[] = {{24, 10, 'n'}, STOP};
struct key K_N[] = {{24, 10, 'N'}, STOP};
struct key K_m[] = {{27, 10, 'm'}, STOP};
struct key K_M[] = {{27, 10, 'M'}, STOP};
struct key K_COMMA[] = {{30, 10, ','}, STOP};
struct key K_LANB[] = {{30, 10, '<'}, STOP};
struct key K_PERIOD[] = {{33, 10, '.'}, STOP};
struct key K_RANB[] = {{33, 10, '>'}, STOP};
struct key K_SLASH[] = {{36, 10, '/'}, STOP};
struct key K_QUESTION[] = {{36, 10, '?'}, STOP};
struct key K_RSHIFT[] = {{42, 10, 'S'}, {43, 10, 'H'}, {44, 10, 'I'}, {45, 10, 'F'}, {46, 10, 'T'}, STOP};
struct key K_ARROW_UP[] = {{54, 10, '('}, {55, 10, 0x2191}, {56, 10, ')'}, STOP};
struct key K_K_1[] = {{65, 10, '1'}, STOP};
struct key K_K_2[] = {{68, 10, '2'}, STOP};
struct key K_K_3[] = {{71, 10, '3'}, STOP};
struct key K_K_ENTER[] = {{74, 10, 0x2591}, {74, 11, 0x2591}, {74, 12, 0x2591}, STOP};

struct key K_LCTRL[] = {{1, 12, 'C'}, {2, 12, 'T'}, {3, 12, 'R'}, {4, 12, 'L'}, STOP};
struct key K_LWIN[] = {{6, 12, 'W'}, {7, 12, 'I'}, {8, 12, 'N'}, STOP};
struct key K_LALT[] = {{10, 12, 'A'}, {11, 12, 'L'}, {12, 12, 'T'}, STOP};
struct key K_SPACE[] =
{
	{14, 12, ' '}, {15, 12, ' '}, {16, 12, ' '}, {17, 12, ' '}, {18, 12, ' '},
	{19, 12, 'S'}, {20, 12, 'P'}, {21, 12, 'A'}, {22, 12, 'C'}, {23, 12, 'E'},
	{24, 12, ' '}, {25, 12, ' '}, {26, 12, ' '}, {27, 12, ' '}, {28, 12, ' '},
	STOP
};
struct key K_RALT[] = {{30, 12, 'A'}, {31, 12, 'L'}, {32, 12, 'T'}, STOP};
struct key K_RWIN[] = {{34, 12, 'W'}, {35, 12, 'I'}, {36, 12, 'N'}, STOP};
struct key K_RPROP[] = {{38, 12, 'P'}, {39, 12, 'R'}, {40, 12, 'O'}, {41, 12, 'P'}, STOP};
struct key K_RCTRL[] = {{43, 12, 'C'}, {44, 12, 'T'}, {45, 12, 'R'}, {46, 12, 'L'}, STOP};
struct key K_ARROW_LEFT[] = {{50, 12, '('}, {51, 12, 0x2190}, {52, 12, ')'}, STOP};
struct key K_ARROW_DOWN[] = {{54, 12, '('}, {55, 12, 0x2193}, {56, 12, ')'}, STOP};
struct key K_ARROW_RIGHT[] = {{58, 12, '('}, {59, 12, 0x2192}, {60, 12, ')'}, STOP};
struct key K_K_0[] = {{65, 12, ' '}, {66, 12, '0'}, {67, 12, ' '}, {68, 12, ' '}, STOP};
struct key K_K_PERIOD[] = {{71, 12, '.'}, STOP};

struct combo
{
	struct key* keys[6];
};

struct combo combos[] =
{
	{{K_TILDE, K_2, K_LCTRL, K_RCTRL, 0}},
	{{K_A, K_LCTRL, K_RCTRL, 0}},
	{{K_B, K_LCTRL, K_RCTRL, 0}},
	{{K_C, K_LCTRL, K_RCTRL, 0}},
	{{K_D, K_LCTRL, K_RCTRL, 0}},
	{{K_E, K_LCTRL, K_RCTRL, 0}},
	{{K_F, K_LCTRL, K_RCTRL, 0}},
	{{K_G, K_LCTRL, K_RCTRL, 0}},
	{{K_H, K_BACKSPACE, K_LCTRL, K_RCTRL, 0}},
	{{K_I, K_TAB, K_LCTRL, K_RCTRL, 0}},
	{{K_J, K_LCTRL, K_RCTRL, 0}},
	{{K_K, K_LCTRL, K_RCTRL, 0}},
	{{K_L, K_LCTRL, K_RCTRL, 0}},
	{{K_M, K_ENTER, K_K_ENTER, K_LCTRL, K_RCTRL, 0}},
	{{K_N, K_LCTRL, K_RCTRL, 0}},
	{{K_O, K_LCTRL, K_RCTRL, 0}},
	{{K_P, K_LCTRL, K_RCTRL, 0}},
	{{K_Q, K_LCTRL, K_RCTRL, 0}},
	{{K_R, K_LCTRL, K_RCTRL, 0}},
	{{K_S, K_LCTRL, K_RCTRL, 0}},
	{{K_T, K_LCTRL, K_RCTRL, 0}},
	{{K_U, K_LCTRL, K_RCTRL, 0}},
	{{K_V, K_LCTRL, K_RCTRL, 0}},
	{{K_W, K_LCTRL, K_RCTRL, 0}},
	{{K_X, K_LCTRL, K_RCTRL, 0}},
	{{K_Y, K_LCTRL, K_RCTRL, 0}},
	{{K_Z, K_LCTRL, K_RCTRL, 0}},
	{{K_LSQB, K_ESC, K_3, K_LCTRL, K_RCTRL, 0}},
	{{K_4, K_BACKSLASH, K_LCTRL, K_RCTRL, 0}},
	{{K_RSQB, K_5, K_LCTRL, K_RCTRL, 0}},
	{{K_6, K_LCTRL, K_RCTRL, 0}},
	{{K_7, K_SLASH, K_MINUS_SHIFT, K_LCTRL, K_RCTRL, 0}},
	{{K_SPACE, 0}},
	{{K_1_SHIFT, K_LSHIFT, K_RSHIFT, 0}},
	{{K_DOUBLEQUOTE, K_LSHIFT, K_RSHIFT, 0}},
	{{K_3_SHIFT, K_LSHIFT, K_RSHIFT, 0}},
	{{K_4_SHIFT, K_LSHIFT, K_RSHIFT, 0}},
	{{K_5_SHIFT, K_LSHIFT, K_RSHIFT, 0}},
	{{K_7_SHIFT, K_LSHIFT, K_RSHIFT, 0}},
	{{K_QUOTE, 0}},
	{{K_9_SHIFT, K_LSHIFT, K_RSHIFT, 0}},
	{{K_0_SHIFT, K_LSHIFT, K_RSHIFT, 0}},
	{{K_8_SHIFT, K_K_STAR, K_LSHIFT, K_RSHIFT, 0}},
	{{K_EQUALS_SHIFT, K_K_PLUS, K_LSHIFT, K_RSHIFT, 0}},
	{{K_COMMA, 0}},
	{{K_MINUS, K_K_MINUS, 0}},
	{{K_PERIOD, K_K_PERIOD, 0}},
	{{K_SLASH, K_K_SLASH, 0}},
	{{K_0, K_K_0, 0}},
	{{K_1, K_K_1, 0}},
	{{K_2, K_K_2, 0}},
	{{K_3, K_K_3, 0}},
	{{K_4, K_K_4, 0}},
	{{K_5, K_K_5, 0}},
	{{K_6, K_K_6, 0}},
	{{K_7, K_K_7, 0}},
	{{K_8, K_K_8, 0}},
	{{K_9, K_K_9, 0}},
	{{K_PARENTHESIS, K_LSHIFT, K_RSHIFT, 0}},
	{{K_SEMICOLON, 0}},
	{{K_LANB, K_LSHIFT, K_RSHIFT, 0}},
	{{K_EQUALS, 0}},
	{{K_RANB, K_LSHIFT, K_RSHIFT, 0}},
	{{K_QUESTION, K_LSHIFT, K_RSHIFT, 0}},
	{{K_2_SHIFT, K_LSHIFT, K_RSHIFT, 0}},
	{{K_A, K_LSHIFT, K_RSHIFT, 0}},
	{{K_B, K_LSHIFT, K_RSHIFT, 0}},
	{{K_C, K_LSHIFT, K_RSHIFT, 0}},
	{{K_D, K_LSHIFT, K_RSHIFT, 0}},
	{{K_E, K_LSHIFT, K_RSHIFT, 0}},
	{{K_F, K_LSHIFT, K_RSHIFT, 0}},
	{{K_G, K_LSHIFT, K_RSHIFT, 0}},
	{{K_H, K_LSHIFT, K_RSHIFT, 0}},
	{{K_I, K_LSHIFT, K_RSHIFT, 0}},
	{{K_J, K_LSHIFT, K_RSHIFT, 0}},
	{{K_K, K_LSHIFT, K_RSHIFT, 0}},
	{{K_L, K_LSHIFT, K_RSHIFT, 0}},
	{{K_M, K_LSHIFT, K_RSHIFT, 0}},
	{{K_N, K_LSHIFT, K_RSHIFT, 0}},
	{{K_O, K_LSHIFT, K_RSHIFT, 0}},
	{{K_P, K_LSHIFT, K_RSHIFT, 0}},
	{{K_Q, K_LSHIFT, K_RSHIFT, 0}},
	{{K_R, K_LSHIFT, K_RSHIFT, 0}},
	{{K_S, K_LSHIFT, K_RSHIFT, 0}},
	{{K_T, K_LSHIFT, K_RSHIFT, 0}},
	{{K_U, K_LSHIFT, K_RSHIFT, 0}},
	{{K_V, K_LSHIFT, K_RSHIFT, 0}},
	{{K_W, K_LSHIFT, K_RSHIFT, 0}},
	{{K_X, K_LSHIFT, K_RSHIFT, 0}},
	{{K_Y, K_LSHIFT, K_RSHIFT, 0}},
	{{K_Z, K_LSHIFT, K_RSHIFT, 0}},
	{{K_LSQB, 0}},
	{{K_BACKSLASH, 0}},
	{{K_RSQB, 0}},
	{{K_6_SHIFT, K_LSHIFT, K_RSHIFT, 0}},
	{{K_MINUS_SHIFT, K_LSHIFT, K_RSHIFT, 0}},
	{{K_TILDE, 0}},
	{{K_a, 0}},
	{{K_b, 0}},
	{{K_c, 0}},
	{{K_d, 0}},
	{{K_e, 0}},
	{{K_f, 0}},
	{{K_g, 0}},
	{{K_h, 0}},
	{{K_i, 0}},
	{{K_j, 0}},
	{{K_k, 0}},
	{{K_l, 0}},
	{{K_m, 0}},
	{{K_n, 0}},
	{{K_o, 0}},
	{{K_p, 0}},
	{{K_q, 0}},
	{{K_r, 0}},
	{{K_s, 0}},
	{{K_t, 0}},
	{{K_u, 0}},
	{{K_v, 0}},
	{{K_w, 0}},
	{{K_x, 0}},
	{{K_y, 0}},
	{{K_z, 0}},
	{{K_LCUB, K_LSHIFT, K_RSHIFT, 0}},
	{{K_BACKSLASH_SHIFT, K_LSHIFT, K_RSHIFT, 0}},
	{{K_RCUB, K_LSHIFT, K_RSHIFT, 0}},
	{{K_TILDE_SHIFT, K_LSHIFT, K_RSHIFT, 0}},
	{{K_8, K_BACKSPACE, K_LCTRL, K_RCTRL, 0}}
};

struct combo func_combos[] =
{
	{{K_F1, 0}},
	{{K_F2, 0}},
	{{K_F3, 0}},
	{{K_F4, 0}},
	{{K_F5, 0}},
	{{K_F6, 0}},
	{{K_F7, 0}},
	{{K_F8, 0}},
	{{K_F9, 0}},
	{{K_F10, 0}},
	{{K_F11, 0}},
	{{K_F12, 0}},
	{{K_INS, 0}},
	{{K_DEL, 0}},
	{{K_HOM, 0}},
	{{K_END, 0}},
	{{K_PGU, 0}},
	{{K_PGD, 0}},
	{{K_ARROW_UP, 0}},
	{{K_ARROW_DOWN, 0}},
	{{K_ARROW_LEFT, 0}},
	{{K_ARROW_RIGHT, 0}}
};

void print_tb(const char* str, int x, int y, uint32_t fg, uint32_t bg)
{
	while (*str)
	{
		uint32_t uni;
		str += utf8_char_to_unicode(&uni, str);
		tb_change_cell(x, y, uni, fg, bg);
		x++;
	}
}

void printf_tb(int x, int y, uint32_t fg, uint32_t bg, const char* fmt, ...)
{
	char buf[4096];
	va_list vl;
	va_start(vl, fmt);
	vsnprintf(buf, sizeof(buf), fmt, vl);
	va_end(vl);
	print_tb(buf, x, y, fg, bg);
}

void draw_key(struct key* k, uint32_t fg, uint32_t bg)
{
	while (k->x)
	{
		tb_change_cell(k->x + 2, k->y + 4, k->ch, fg, bg);
		k++;
	}
}

void draw_keyboard()
{
	int i;
	tb_change_cell(0, 0, 0x250C, TB_WHITE, TB_DEFAULT);
	tb_change_cell(79, 0, 0x2510, TB_WHITE, TB_DEFAULT);
	tb_change_cell(0, 23, 0x2514, TB_WHITE, TB_DEFAULT);
	tb_change_cell(79, 23, 0x2518, TB_WHITE, TB_DEFAULT);

	for (i = 1; i < 79; ++i)
	{
		tb_change_cell(i, 0, 0x2500, TB_WHITE, TB_DEFAULT);
		tb_change_cell(i, 23, 0x2500, TB_WHITE, TB_DEFAULT);
		tb_change_cell(i, 17, 0x2500, TB_WHITE, TB_DEFAULT);
		tb_change_cell(i, 4, 0x2500, TB_WHITE, TB_DEFAULT);
	}

	for (i = 1; i < 23; ++i)
	{
		tb_change_cell(0, i, 0x2502, TB_WHITE, TB_DEFAULT);
		tb_change_cell(79, i, 0x2502, TB_WHITE, TB_DEFAULT);
	}

	tb_change_cell(0, 17, 0x251C, TB_WHITE, TB_DEFAULT);
	tb_change_cell(79, 17, 0x2524, TB_WHITE, TB_DEFAULT);
	tb_change_cell(0, 4, 0x251C, TB_WHITE, TB_DEFAULT);
	tb_change_cell(79, 4, 0x2524, TB_WHITE, TB_DEFAULT);

	for (i = 5; i < 17; ++i)
	{
		tb_change_cell(1, i, 0x2588, TB_YELLOW, TB_YELLOW);
		tb_change_cell(78, i, 0x2588, TB_YELLOW, TB_YELLOW);
	}

	draw_key(K_ESC, TB_WHITE, TB_BLUE);
	draw_key(K_F1, TB_WHITE, TB_BLUE);
	draw_key(K_F2, TB_WHITE, TB_BLUE);
	draw_key(K_F3, TB_WHITE, TB_BLUE);
	draw_key(K_F4, TB_WHITE, TB_BLUE);
	draw_key(K_F5, TB_WHITE, TB_BLUE);
	draw_key(K_F6, TB_WHITE, TB_BLUE);
	draw_key(K_F7, TB_WHITE, TB_BLUE);
	draw_key(K_F8, TB_WHITE, TB_BLUE);
	draw_key(K_F9, TB_WHITE, TB_BLUE);
	draw_key(K_F10, TB_WHITE, TB_BLUE);
	draw_key(K_F11, TB_WHITE, TB_BLUE);
	draw_key(K_F12, TB_WHITE, TB_BLUE);
	draw_key(K_PRN, TB_WHITE, TB_BLUE);
	draw_key(K_SCR, TB_WHITE, TB_BLUE);
	draw_key(K_BRK, TB_WHITE, TB_BLUE);
	draw_key(K_LED1, TB_WHITE, TB_BLUE);
	draw_key(K_LED2, TB_WHITE, TB_BLUE);
	draw_key(K_LED3, TB_WHITE, TB_BLUE);

	draw_key(K_TILDE, TB_WHITE, TB_BLUE);
	draw_key(K_1, TB_WHITE, TB_BLUE);
	draw_key(K_2, TB_WHITE, TB_BLUE);
	draw_key(K_3, TB_WHITE, TB_BLUE);
	draw_key(K_4, TB_WHITE, TB_BLUE);
	draw_key(K_5, TB_WHITE, TB_BLUE);
	draw_key(K_6, TB_WHITE, TB_BLUE);
	draw_key(K_7, TB_WHITE, TB_BLUE);
	draw_key(K_8, TB_WHITE, TB_BLUE);
	draw_key(K_9, TB_WHITE, TB_BLUE);
	draw_key(K_0, TB_WHITE, TB_BLUE);
	draw_key(K_MINUS, TB_WHITE, TB_BLUE);
	draw_key(K_EQUALS, TB_WHITE, TB_BLUE);
	draw_key(K_BACKSLASH, TB_WHITE, TB_BLUE);
	draw_key(K_BACKSPACE, TB_WHITE, TB_BLUE);
	draw_key(K_INS, TB_WHITE, TB_BLUE);
	draw_key(K_HOM, TB_WHITE, TB_BLUE);
	draw_key(K_PGU, TB_WHITE, TB_BLUE);
	draw_key(K_K_NUMLOCK, TB_WHITE, TB_BLUE);
	draw_key(K_K_SLASH, TB_WHITE, TB_BLUE);
	draw_key(K_K_STAR, TB_WHITE, TB_BLUE);
	draw_key(K_K_MINUS, TB_WHITE, TB_BLUE);

	draw_key(K_TAB, TB_WHITE, TB_BLUE);
	draw_key(K_q, TB_WHITE, TB_BLUE);
	draw_key(K_w, TB_WHITE, TB_BLUE);
	draw_key(K_e, TB_WHITE, TB_BLUE);
	draw_key(K_r, TB_WHITE, TB_BLUE);
	draw_key(K_t, TB_WHITE, TB_BLUE);
	draw_key(K_y, TB_WHITE, TB_BLUE);
	draw_key(K_u, TB_WHITE, TB_BLUE);
	draw_key(K_i, TB_WHITE, TB_BLUE);
	draw_key(K_o, TB_WHITE, TB_BLUE);
	draw_key(K_p, TB_WHITE, TB_BLUE);
	draw_key(K_LSQB, TB_WHITE, TB_BLUE);
	draw_key(K_RSQB, TB_WHITE, TB_BLUE);
	draw_key(K_ENTER, TB_WHITE, TB_BLUE);
	draw_key(K_DEL, TB_WHITE, TB_BLUE);
	draw_key(K_END, TB_WHITE, TB_BLUE);
	draw_key(K_PGD, TB_WHITE, TB_BLUE);
	draw_key(K_K_7, TB_WHITE, TB_BLUE);
	draw_key(K_K_8, TB_WHITE, TB_BLUE);
	draw_key(K_K_9, TB_WHITE, TB_BLUE);
	draw_key(K_K_PLUS, TB_WHITE, TB_BLUE);

	draw_key(K_CAPS, TB_WHITE, TB_BLUE);
	draw_key(K_a, TB_WHITE, TB_BLUE);
	draw_key(K_s, TB_WHITE, TB_BLUE);
	draw_key(K_d, TB_WHITE, TB_BLUE);
	draw_key(K_f, TB_WHITE, TB_BLUE);
	draw_key(K_g, TB_WHITE, TB_BLUE);
	draw_key(K_h, TB_WHITE, TB_BLUE);
	draw_key(K_j, TB_WHITE, TB_BLUE);
	draw_key(K_k, TB_WHITE, TB_BLUE);
	draw_key(K_l, TB_WHITE, TB_BLUE);
	draw_key(K_SEMICOLON, TB_WHITE, TB_BLUE);
	draw_key(K_QUOTE, TB_WHITE, TB_BLUE);
	draw_key(K_K_4, TB_WHITE, TB_BLUE);
	draw_key(K_K_5, TB_WHITE, TB_BLUE);
	draw_key(K_K_6, TB_WHITE, TB_BLUE);

	draw_key(K_LSHIFT, TB_WHITE, TB_BLUE);
	draw_key(K_z, TB_WHITE, TB_BLUE);
	draw_key(K_x, TB_WHITE, TB_BLUE);
	draw_key(K_c, TB_WHITE, TB_BLUE);
	draw_key(K_v, TB_WHITE, TB_BLUE);
	draw_key(K_b, TB_WHITE, TB_BLUE);
	draw_key(K_n, TB_WHITE, TB_BLUE);
	draw_key(K_m, TB_WHITE, TB_BLUE);
	draw_key(K_COMMA, TB_WHITE, TB_BLUE);
	draw_key(K_PERIOD, TB_WHITE, TB_BLUE);
	draw_key(K_SLASH, TB_WHITE, TB_BLUE);
	draw_key(K_RSHIFT, TB_WHITE, TB_BLUE);
	draw_key(K_ARROW_UP, TB_WHITE, TB_BLUE);
	draw_key(K_K_1, TB_WHITE, TB_BLUE);
	draw_key(K_K_2, TB_WHITE, TB_BLUE);
	draw_key(K_K_3, TB_WHITE, TB_BLUE);
	draw_key(K_K_ENTER, TB_WHITE, TB_BLUE);

	draw_key(K_LCTRL, TB_WHITE, TB_BLUE);
	draw_key(K_LWIN, TB_WHITE, TB_BLUE);
	draw_key(K_LALT, TB_WHITE, TB_BLUE);
	draw_key(K_SPACE, TB_WHITE, TB_BLUE);
	draw_key(K_RCTRL, TB_WHITE, TB_BLUE);
	draw_key(K_RPROP, TB_WHITE, TB_BLUE);
	draw_key(K_RWIN, TB_WHITE, TB_BLUE);
	draw_key(K_RALT, TB_WHITE, TB_BLUE);
	draw_key(K_ARROW_LEFT, TB_WHITE, TB_BLUE);
	draw_key(K_ARROW_DOWN, TB_WHITE, TB_BLUE);
	draw_key(K_ARROW_RIGHT, TB_WHITE, TB_BLUE);
	draw_key(K_K_0, TB_WHITE, TB_BLUE);
	draw_key(K_K_PERIOD, TB_WHITE, TB_BLUE);

	printf_tb(33, 1, TB_MAGENTA | TB_BOLD, TB_DEFAULT, "Keyboard demo!");
	printf_tb(21, 2, TB_MAGENTA, TB_DEFAULT,
		"(press CTRL+X and then CTRL+Q to exit)");
	printf_tb(15, 3, TB_MAGENTA, TB_DEFAULT,
		"(press CTRL+X and then CTRL+C to change input mode)");

	int inputmode = tb_select_input_mode(0);
	char inputmode_str[64];

	if (inputmode & TB_INPUT_ESC)
	{
		sprintf(inputmode_str, "TB_INPUT_ESC");
	}

	if (inputmode & TB_INPUT_ALT)
	{
		sprintf(inputmode_str, "TB_INPUT_ALT");
	}

	if (inputmode & TB_INPUT_MOUSE)
	{
		sprintf(inputmode_str + 12, " | TB_INPUT_MOUSE");
	}

	printf_tb(3, 18, TB_WHITE, TB_DEFAULT, "Input mode: %s", inputmode_str);
}

const char* funckeymap(int k)
{
	static const char* fcmap[] =
	{
		"CTRL+2, CTRL+~",
		"CTRL+A",
		"CTRL+B",
		"CTRL+C",
		"CTRL+D",
		"CTRL+E",
		"CTRL+F",
		"CTRL+G",
		"CTRL+H, BACKSPACE",
		"CTRL+I, TAB",
		"CTRL+J",
		"CTRL+K",
		"CTRL+L",
		"CTRL+M, ENTER",
		"CTRL+N",
		"CTRL+O",
		"CTRL+P",
		"CTRL+Q",
		"CTRL+R",
		"CTRL+S",
		"CTRL+T",
		"CTRL+U",
		"CTRL+V",
		"CTRL+W",
		"CTRL+X",
		"CTRL+Y",
		"CTRL+Z",
		"CTRL+3, ESC, CTRL+[",
		"CTRL+4, CTRL+\\",
		"CTRL+5, CTRL+]",
		"CTRL+6",
		"CTRL+7, CTRL+/, CTRL+_",
		"SPACE"
	};
	static const char* fkmap[] =
	{
		"F1",
		"F2",
		"F3",
		"F4",
		"F5",
		"F6",
		"F7",
		"F8",
		"F9",
		"F10",
		"F11",
		"F12",
		"INSERT",
		"DELETE",
		"HOME",
		"END",
		"PGUP",
		"PGDN",
		"ARROW UP",
		"ARROW DOWN",
		"ARROW LEFT",
		"ARROW RIGHT"
	};

	if (k == TB_KEY_CTRL_8)
	{
		return "CTRL+8, BACKSPACE 2";    // 0x7F
	}
	else if (k >= TB_KEY_ARROW_RIGHT && k <= 0xFFFF)
	{
		return fkmap[0xFFFF - k];
	}
	else if (k <= TB_KEY_SPACE)
	{
		return fcmap[k];
	}

	return "UNKNOWN";
}

void pretty_print_press(struct tb_event* ev)
{
	char buf[7];
	buf[utf8_unicode_to_char(buf, ev->ch)] = '\0';
	printf_tb(3, 19, TB_WHITE, TB_DEFAULT, "Key: ");
	printf_tb(8, 19, TB_YELLOW, TB_DEFAULT, "decimal: %d", ev->key);
	printf_tb(8, 20, TB_GREEN, TB_DEFAULT, "hex:     0x%X", ev->key);
	printf_tb(8, 21, TB_CYAN, TB_DEFAULT, "octal:   0%o", ev->key);
	printf_tb(8, 22, TB_RED, TB_DEFAULT, "string:  %s", funckeymap(ev->key));

	printf_tb(54, 19, TB_WHITE, TB_DEFAULT, "Char: ");
	printf_tb(60, 19, TB_YELLOW, TB_DEFAULT, "decimal: %d", ev->ch);
	printf_tb(60, 20, TB_GREEN, TB_DEFAULT, "hex:     0x%X", ev->ch);
	printf_tb(60, 21, TB_CYAN, TB_DEFAULT, "octal:   0%o", ev->ch);
	printf_tb(60, 22, TB_RED, TB_DEFAULT, "string:  %s", buf);

	printf_tb(54, 18, TB_WHITE, TB_DEFAULT, "Modifier: %s",
		(ev->mod) ? "TB_MOD_ALT" : "none");

}

void pretty_print_resize(struct tb_event* ev)
{
	printf_tb(3, 19, TB_WHITE, TB_DEFAULT, "Resize event: %d x %d", ev->w, ev->h);
}

int counter = 0;

void  pretty_print_mouse(struct tb_event* ev)
{
	printf_tb(3, 19, TB_WHITE, TB_DEFAULT, "Mouse event: %d x %d", ev->x, ev->y);
	char* btn = "";

	switch (ev->key)
	{
		case TB_KEY_MOUSE_LEFT:
			btn = "MouseLeft: %d";
			break;

		case TB_KEY_MOUSE_MIDDLE:
			btn = "MouseMiddle: %d";
			break;

		case TB_KEY_MOUSE_RIGHT:
			btn = "MouseRight: %d";
			break;

		case TB_KEY_MOUSE_WHEEL_UP:
			btn = "MouseWheelUp: %d";
			break;

		case TB_KEY_MOUSE_WHEEL_DOWN:
			btn = "MouseWheelDown: %d";
			break;

		case TB_KEY_MOUSE_RELEASE:
			btn = "MouseRelease: %d";
	}

	counter++;
	printf_tb(43, 19, TB_WHITE, TB_DEFAULT, "Key: ");
	printf_tb(48, 19, TB_YELLOW, TB_DEFAULT, btn, counter);
}

void dispatch_press(struct tb_event* ev)
{
	if (ev->mod & TB_MOD_ALT)
	{
		draw_key(K_LALT, TB_WHITE, TB_RED);
		draw_key(K_RALT, TB_WHITE, TB_RED);
	}

	struct combo* k = 0;

	if (ev->key >= TB_KEY_ARROW_RIGHT)
	{
		k = &func_combos[0xFFFF - ev->key];
	}
	else if (ev->ch < 128)
	{
		if (ev->ch == 0 && ev->key < 128)
		{
			k = &combos[ev->key];
		}
		else
		{
			k = &combos[ev->ch];
		}
	}

	if (!k)
	{
		return;
	}

	struct key** keys = k->keys;

	while (*keys)
	{
		draw_key(*keys, TB_WHITE, TB_RED);
		keys++;
	}
}

int main(int argc, char** argv)
{
	(void) argc;
	(void) argv;
	int ret;

	ret = tb_init();

	if (ret)
	{
		fprintf(stderr, "tb_init() failed with error code %d\n", ret);
		return 1;
	}

	tb_select_input_mode(TB_INPUT_ESC | TB_INPUT_MOUSE);
	struct tb_event ev;

	tb_clear();
	draw_keyboard();
	tb_present();
	int inputmode = 0;
	int ctrlxpressed = 0;

	while (tb_poll_event(&ev))
	{
		switch (ev.type)
		{
			case TB_EVENT_KEY:
				if (ev.key == TB_KEY_CTRL_Q && ctrlxpressed)
				{
					tb_shutdown();
					return 0;
				}

				if (ev.key == TB_KEY_CTRL_C && ctrlxpressed)
				{
					static int chmap[] =
					{
						TB_INPUT_ESC | TB_INPUT_MOUSE, // 101
						TB_INPUT_ALT | TB_INPUT_MOUSE, // 110
						TB_INPUT_ESC,                  // 001
						TB_INPUT_ALT,                  // 010
					};
					inputmode++;

					if (inputmode >= 4)
					{
						inputmode = 0;
					}

					tb_select_input_mode(chmap[inputmode]);
				}

				if (ev.key == TB_KEY_CTRL_X)
				{
					ctrlxpressed = 1;
				}
				else
				{
					ctrlxpressed = 0;
				}

				tb_clear();
				draw_keyboard();
				dispatch_press(&ev);
				pretty_print_press(&ev);
				tb_present();
				break;

			case TB_EVENT_RESIZE:
				tb_clear();
				draw_keyboard();
				pretty_print_resize(&ev);
				tb_present();
				break;

			case TB_EVENT_MOUSE:
				tb_clear();
				draw_keyboard();
				pretty_print_mouse(&ev);
				tb_present();
				break;

			default:
				break;
		}
	}

	tb_shutdown();
	return 0;
}
