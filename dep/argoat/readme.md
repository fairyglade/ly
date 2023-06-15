# Argoat
Argoat is a lightweight library for command-line options parsing.
This was created because most of the existing solutions rely heavily on macros,
and all of them expect you to write a giant switch to handle the given options.

Argoat allows you to deal with arguments using function pointers.
It does not use any macro, switch, or dynamic memory allocation.

Argoat supports the following syntaxes:
 - simple options    `test -a -b`
 - compound options  `test -ab`
 - assigned options  `test -c=4 -d 2`
 - long options      `test --code 4 --den 2`
 - lone dash         `test --oki - --den 2`
 - lone double-dash  `test --oki -- --doki`
 - unflagged options `test 0 -c=4 1 -d=2 3`
 - limited params    `test 0 -c 4 1 -d 2 3`

Argoat does not support the following syntaxes *on purpose*:
 - simple neighbours `test -a4`
 - custom symbols    `test +a 4`

All of that in around 200 lines of code (getopt has approximately 700).
Don't be shy, sneak a goat in your code.

## Cloning
Clone with `--recurse-submodules` to get the required submodules.

## Testing
Run `make` to compile the testing suite, and `make run` to perform the tests.

## Using
### TL;DR
```
#include "argoat.h"
#include <stdbool.h>
#include <stdio.h>

void handle_main(void* data, char** pars, const int pars_count)
{
}

void handle_bool(void* data, char** pars, const int pars_count)
{
	*((bool*) data) = true;
}

int main(int argc, char** argv)
{
	bool data1 = false;
	char* unflagged[23];

	const struct argoat_sprig sprigs[2] =
	{
		{NULL, 0, NULL, handle_main},
		{"t", 0, (void*) &data1, handle_bool}
	};

	struct argoat args = {sprigs, 2, unflagged, 0, 23};
	argoat_graze(&args, argc, argv);
	printf("%c\n", data1 ? '1' : '0');

	return 0;
}
```

### Details
Include `argoat.h` and compile `argoat.c` with your code.

Write the functions that will handle your parameters.
They will be called during the parsing process, in the order given by the user
```
void handle_main(void* data, char** pars, const int pars_count)
{
}

void handle_bool(void* data, char** pars, const int pars_count)
{
	*((bool*) data) = true;
}
```

In your `int main(int argc, char** argv)`, declare the variables to configure.
They will be passed to the corresponding functions as `void* data`
```
bool data1 = false;
```

Also declare an array of strings to store the unflagged arguments.
Just choose a size corresponding to the maximum number of unflagged arguments
your program supports, or create a null pointer if it does not use them.
```
char* unflagged[UNFLAGGED_MAX];
```

Then, declare an array of flag structures.
The first entry only has to contain the unflagged-arguments handling function.
The others must specify:
 - the name of the flag (one char for '-' prefix, multiple chars for '--')
 - the maximum number of arguments supported by this flag
 - a pointer to the data that has to be configured by the handling function
 - a pointer to the handling function
```
const struct argoat_sprig sprigs[2] =
{
	{NULL, 0, NULL, handle_main},
	{"t", 0, (void*) &data1, handle_bool}
};
```

Then, create the main argoat structure given:
 - the flags array
 - its size,
 - the unflagged string buffer
 - the initial number of unflagged arguments
 - the maximum possible
```
struct argoat args = {sprigs, 2, unflagged, 0, UNFLAGGED_MAX};
```

All that remains to do is calling the parsing function
```
argoat_graze(&args, argc, argv);
```

And using the configured data
```
printf("%c\n", data1 ? '1' : '0');
```
