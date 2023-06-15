#ifndef C_TESTS
#define C_TESTS

#include "testoasterror.h"
#include <string.h>

void test1(struct testoasterror* test)
{
	testoasterror(test, 1 == 1);
}

void test2(struct testoasterror* test)
{
	testoasterror(test, 0 == 0);
	testoasterror(test, 1 == 1);
	testoasterror(test, 2 == 2);
}

void test3(struct testoasterror* test)
{
	bool res;

	res = testoasterror(test, strcmp("fuck", "shit") == 0);

	if (!res)
	{
		testoasterror_fail(test);
		return;
	}

	testoasterror(test, 0 == 0);
}

#endif
