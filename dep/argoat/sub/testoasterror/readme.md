# Testoasterror
Testoasterror is a minimalistic testing library. It is written in C99
and does not use dynamic memory allocations by default.

# Testing
Run `make` and `make run`. This will execute the example in the `tests` folder.

# Using
## TL;DR
Check out the `tests` folder

## Details
Include `testoasterror.h` and compile `testoasterror.c` with your testing `main()`.

Declare an array of `bool` to hold the results of each tested expression.
Its size determines the maximum number of expression checks for the same test.
If one outreaches that limit, testoasterror will print a "fail overflow" message.
The limit is 255, the maximum for a `uint8_t`.
```
bool results[255];
```

Also declare an array of function pointers to hold your tests
```
void (*funcs[3])(struct testoasterror*) =
{
	test1,
	test2,
	test3
}
```

Then, initialize a testoasterror context, giving:
 - a pointer to the context to initialize
 - the expression results buffer
 - its length
 - the testing functions array
 - its length
```
struct testoasterror test;
testoasterror_init(&test, results, 255, funcs, 3);
```

Run the tests and you're good to go!
```
testoasterror_run(&test);
```

You can now write your tests in other C files, using the same function prototype
```
#ifndef C_TESTS
#define C_TESTS

#include "testoasterror.h"

// a test
void test1(struct testoasterror* test)
{
	// an expression check
	testoasterror(test, 1 > 0);
}

#endif
```

It is, in my opinion, a good idea to include them directly with the `main()`.
This way, the function pointers will resolve without the need for a header
(hence the include guards in the C file example above)
```
#include "tests.c"
```

Extra: to abort, call the fail function *and return*
```
testoasterror_fail(test);
```

# Greetings
nnorm for ninja-starring this repo (how can you be *this* fast?!)
