#include "testoasterror.h"

// source include
#include "tests.c"

#define COUNT_RESULTS 2
#define COUNT_FUNCS 3

int main()
{
	bool results[COUNT_RESULTS];
	void (*funcs[COUNT_FUNCS])(struct testoasterror*) =
	{
		test1,
		test2,
		test3
	};

	struct testoasterror test;
	testoasterror_init(&test, results, COUNT_RESULTS, funcs, COUNT_FUNCS);
	testoasterror_run(&test);

	return 0;
}
