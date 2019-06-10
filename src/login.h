#ifndef H_LY_LOGIN
#define H_LY_LOGIN

#include "draw.h"
#include "inputs.h"

void auth(
	struct desktop* desktop,
	struct text* login,
	struct text* password,
	struct term_buf* buf);

#endif
