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
	bool data2 = false;
	bool data3 = false;
	char* unflagged[UNFLAGGED_MAX];

	const struct argoat_sprig sprigs[4] =
	{
		{NULL, 0, NULL, handle_main},
		{"long", 0, (void*) &data1, handle_bool},
		{"mighty", 0, (void*) &data2, handle_bool},
		{"options", 0, (void*) &data3, handle_bool},
	};

	struct argoat args = {sprigs, 4, unflagged, 0, UNFLAGGED_MAX};

	argoat_graze(&args, argc, argv);
	
	printf("t%c%c%c\n",
		data1 ? 'l' : ' ',
		data2 ? 'm' : ' ',
		data3 ? 'o' : ' ');

	return 0;
}
