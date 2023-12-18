#include <stdint.h>

#define CLOCK_W 5
#define CLOCK_H 5

#define X '.'
#define _ 0

#if CLOCK_W == 5 && CLOCK_H == 5

uint32_t CLOCK_0[] = {
	X,X,X,X,X,
	X,X,_,X,X,
	X,X,_,X,X,
	X,X,_,X,X,
	X,X,X,X,X
};

uint32_t CLOCK_1[] = {
	_,_,_,X,X,
	_,_,_,X,X,
	_,_,_,X,X,
	_,_,_,X,X,
	_,_,_,X,X
};

uint32_t CLOCK_2[] = {
	X,X,X,X,X,
	_,_,_,X,X,
	X,X,X,X,X,
	X,X,_,_,_,
	X,X,X,X,X
};

uint32_t CLOCK_3[] = {
	X,X,X,X,X,
	_,_,_,X,X,
	X,X,X,X,X,
	_,_,_,X,X,
	X,X,X,X,X
};

uint32_t CLOCK_4[] = {
	X,X,_,X,X,
	X,X,_,X,X,
	X,X,X,X,X,
	_,_,_,X,X,
	_,_,_,X,X
};

uint32_t CLOCK_5[] = {
	X,X,X,X,X,
	X,X,_,_,_,
	X,X,X,X,X,
	_,_,_,X,X,
	X,X,X,X,X
};

uint32_t CLOCK_6[] = {
	X,X,X,X,X,
	X,X,_,_,_,
	X,X,X,X,X,
	X,X,_,X,X,
	X,X,X,X,X,
};

uint32_t CLOCK_7[] = {
	X,X,X,X,X,
	_,_,_,X,X,
	_,_,_,X,X,
	_,_,_,X,X,
	_,_,_,X,X
};

uint32_t CLOCK_8[] = {
	X,X,X,X,X,
	X,X,_,X,X,
	X,X,X,X,X,
	X,X,_,X,X,
	X,X,X,X,X
};

uint32_t CLOCK_9[] = {
	X,X,X,X,X,
	X,X,_,X,X,
	X,X,X,X,X,
	_,_,_,X,X,
	X,X,X,X,X
};

uint32_t CLOCK_S[] = {
	_,_,_,_,_,
	_,_,X,_,_,
	_,_,_,_,_,
	_,_,X,_,_,
	_,_,_,_,_
};

uint32_t CLOCK_E[] = {
	_,_,_,_,_,
	_,_,_,_,_,
	_,_,_,_,_,
	_,_,_,_,_,
	_,_,_,_,_
};

uint32_t CLOCK_D[] = {
	_,_,_,_,_,
	_,_,_,_,_,
	_,X,X,X,_,
	_,_,_,_,_,
	_,_,_,_,_
};

#endif

#undef X
#undef _

// I wish these were in a premade dictionary... Writing this felt like hell
uint32_t* CLOCK_CHARS[] = {CLOCK_0,CLOCK_1,CLOCK_2,CLOCK_3,CLOCK_4,CLOCK_5,CLOCK_6,CLOCK_7,CLOCK_8,CLOCK_9,CLOCK_S,CLOCK_E,CLOCK_D}; 

static inline uint32_t* CLOCK_N(char c)
{
	switch(c)
	{
		case '0':
			return CLOCK_0;
		case '1':
			return CLOCK_1;
		case '2':
			return CLOCK_2;
		case '3':
			return CLOCK_3;
		case '4':
			return CLOCK_4;
		case '5':
			return CLOCK_5;
		case '6':
			return CLOCK_6;
		case '7':
			return CLOCK_7;
		case '8':
			return CLOCK_8;
		case '9':
			return CLOCK_9;
		case ':':
			return CLOCK_S;
    case '-':
      return CLOCK_D;
		default:
			return CLOCK_E;
	}
}
