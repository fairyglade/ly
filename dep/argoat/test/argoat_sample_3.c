#include "argoat.h"
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#define UNFLAGGED_MAX 4

void handle_bool(void* data, char** pars, const int pars_count)
{
	*((bool*) data) = true;
}

void handle_add(void* data, char** pars, const int pars_count)
{
	if (pars_count < 2)
	{
		return;
	}

	*((int*) data) = atoi(pars[0]) + atoi(pars[1]); // safe for testing
}

void handle_string(void* data, char** pars, const int pars_count)
{
	if (pars_count < 1)
	{
		return;
	}

	*((char**) data) = pars[0];
}

void handle_main(void* data, char** pars, const int pars_count)
{
	if (pars_count > UNFLAGGED_MAX)
	{
		return;
	}

	for (int i = 0; i < pars_count; ++i)
	{
		printf("%s", pars[i]);
	}

	return;
}

int main(int argc, char** argv)
{
	bool data1 = false;
	int data2 = 0;
	char* data3 = "";

	char* unflagged[UNFLAGGED_MAX];

	const struct argoat_sprig sprigs[4] =
	{
		{NULL, 0, NULL, handle_main},
		{"tau", 2, (void*) &data2, handle_add},
		{"t", 0, (void*) &data1, handle_bool},
		{"text", 1, (void*) &data3, handle_string},
	};

	struct argoat args = {sprigs, 4, unflagged, 0, UNFLAGGED_MAX};

	argoat_graze(&args, argc, argv);
	
	printf("t%c%d%s\n", data1 ? 'l' : ' ', data2, data3);

	return 0;
}
