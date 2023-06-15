#define _POSIX_C_SOURCE 200809L
#include "testoasterror.h"

// source include
#include "tests.c"

int main()
{
	bool results[32];
	void (*funcs[3])(struct testoasterror*) =
	{
		test1,
		test2,
		test3
	};

	struct testoasterror test;
	testoasterror_init(&test, results, 32, funcs, 3);
	testoasterror_run(&test);

	return 0;
}
