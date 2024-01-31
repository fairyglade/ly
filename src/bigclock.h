#include <stdint.h>

#define CLOCK_W 5
#define CLOCK_H 5

#if defined(__linux__) || defined(__FreeBSD__)
	#define X 0x2593
	#define _ 0x0000
#else
	#define X '#'
	#define _ 0
#endif

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

//Farsi digits

uint32_t CLOCK_1_0[] = {
	_,_,_,_,_,
	_,_,X,_,_,
	_,X,_,X,_,
	_,_,X,_,_,
	_,_,_,_,_
};

uint32_t CLOCK_1_1[] = {
	_,_,X,_,_,
	_,_,X,_,_,
	_,_,X,_,_,
	_,_,X,_,_,
	_,_,X,_,_
};

uint32_t CLOCK_1_2[] = {
	_,X,_,X,_,
	_,X,X,X,_,
	_,X,_,_,_,
	_,X,_,_,_,
	_,X,_,_,_
};

uint32_t CLOCK_1_3[] = {
	X,_,X,_,X,
	X,X,X,X,X,
	X,_,_,_,_,
	X,_,_,_,_,
	X,_,_,_,_
};

uint32_t CLOCK_1_4[] = {
	_,X,_,X,X,
	_,X,_,X,_,
	_,X,X,X,X,
	_,X,_,_,_,
	_,X,_,_,_
};

uint32_t CLOCK_1_5[] = {
	_,_,X,_,_,
	_,X,_,X,_,
	X,_,_,_,X,
	X,_,X,_,X,
	_,X,X,X,_
};

uint32_t CLOCK_1_6[] = {
	_,X,_,X,_,
	_,X,X,X,_,
	_,_,_,X,_,
	_,_,_,X,_,
	_,_,_,X,_
};

uint32_t CLOCK_1_7[] = {
	X,_,_,_,X,
	X,_,_,_,X,
	_,X,_,X,_,
	_,X,_,X,_,
	_,_,X,_,_

};

uint32_t CLOCK_1_8[] = {
	_,_,X,_,_,
	_,X,_,X,_,
	_,X,_,X,_,
	X,_,_,_,X,
	X,_,_,_,X
};

uint32_t CLOCK_1_9[] = {
	_,X,X,X,_,
	_,X,_,X,_,
	_,X,X,X,_,
	_,_,_,X,_,
	_,_,_,X,_
};

uint32_t CLOCK_1_S[] = {
	_,_,_,_,_,
	_,_,X,_,_,
	_,_,_,_,_,
	_,_,X,_,_,
	_,_,_,_,_
};

uint32_t CLOCK_1_E[] = {
	_,_,_,_,_,
	_,_,_,_,_,
	_,_,_,_,_,
	_,_,_,_,_,
	_,_,_,_,_
};

#endif

#undef X
#undef _

static inline uint32_t* CLOCK_N(uint8_t bigclock_lang, char c)
{
	if (bigclock_lang == 1) {
		switch(c)
		{
			case '0':
				return CLOCK_1_0;
			case '1':
				return CLOCK_1_1;
			case '2':
				return CLOCK_1_2;
			case '3':
				return CLOCK_1_3;
			case '4':
				return CLOCK_1_4;
			case '5':
				return CLOCK_1_5;
			case '6':
				return CLOCK_1_6;
			case '7':
				return CLOCK_1_7;
			case '8':
				return CLOCK_1_8;
			case '9':
				return CLOCK_1_9;
			case ':':
				return CLOCK_1_S;
			default:
				return CLOCK_1_E;
		}
	}
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
		default:
			return CLOCK_E;
	}
}
