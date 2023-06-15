#include "argoat.h"
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>

// executes the function for unflagged pars
void argoat_unflagged_sacrifice(const struct argoat* args)
{
	args->sprigs[0].func(args->sprigs[0].data,
		args->unflagged,
		args->unflagged_count);
}

// returns 1 to increment the pars counter if the one given is flagged
// otherwise we store the unflagged par in the buffer and return 0
int argoat_increment_pars(struct argoat* args, char* flag, char* pars)
{
	// unflagged pars
	if (flag == NULL)
	{
		// tests bounds and saves
		int count = args->unflagged_count;

		if (count < args->unflagged_max)
		{
			args->unflagged[count] = pars;
			++args->unflagged_count;
		}

		return 0;
	}
	// flagged pars
	else
	{
		return 1;
	}
}

// function execution
void argoat_sacrifice(struct argoat* args,
	char* flag,
	char** pars,
	int pars_count)
{
	// first flag found or tag compound passed
	if (flag == NULL)
	{
		return;
	}

	// handles flags with '='
	int flag_len;
	char* eq = strchr(flag, '=');

	if (eq != NULL)
	{
		flag_len = eq - flag;
	}
	else
	{
		flag_len = strlen(flag); // safe
	}

	// searches the tag in the argoat structure
	// we initialize i to 1 to skip the programm execution command
	int i = 1;
	int len = args->sprigs_count;

	while(i < len)
	{
		// as we use strncmp we must test the sizes to avoid collisions
		if ((strncmp(args->sprigs[i].flag, flag, flag_len) == 0)
		&& (((int) strlen(args->sprigs[i].flag)) == flag_len)) // safe
		{
			break;
		}

		++i;
	}

	// the flag was not registered
	if (i == len)
	{
		return;
	}

	// handles flags with '='
	// maximum number of pars passed to the function
	int max;

	if (eq != NULL)
	{
		// moves past the '=' char
		++eq; 
		// moves the pars pointer to the flag
		--pars;

		// flag with '=' means we wave an additionnal parameter
		++pars_count;
		// which will be the only one (the others are left unflagged)
		max = 1;

		// copies the par following '=' at the beginning of the flag
		memcpy(pars[0], eq, strlen(eq) + 1); // safe
	}
	else
	{
		max = args->sprigs[i].pars_max;
	}

	// saves pars exceeding the limit
	if (pars_count > max)
	{
		for(int k = max; k < pars_count; ++k)
		{
			// leverages the pars incrementation side-effects
			argoat_increment_pars(args, NULL, pars[k]);
		}

		// fixes the number of pars given to the function
		pars_count = max;
	}

	// calls the approriate function
	args->sprigs[i].func(args->sprigs[i].data, pars, pars_count);
}

// executes functions without pars for compound tags
void argoat_compound(struct argoat* args, char** pars)
{
	// currently processed char/flag
	int scroll = 1;
	char flag[2]; // safe

	flag[1] = '\0';

	// if this function is excuted this means there is at least one flag
	// therefore it is safe to test the condition for the next char only
	do
	{
		flag[0] = pars[0][scroll];
		argoat_sacrifice(args, flag, pars, 0);
		++scroll;
	}
	while(pars[0][scroll] != '\0');
}

// executes functions with pars for each flag
void argoat_graze(struct argoat* args, int argc, char** argv)
{
	int pars_count = 0;
	char** pars = NULL;
	char* flag = NULL;
	char dash;

	// skips the program execution command
	++argv;
	--argc;

	// identifies every element in argv and executes the right
	// handling functions during the process
	for (int i = 0; i < argc; ++i)
	{
		// will be tested to identify lone dashes and long flags
		dash = argv[i][1];

		// pars
		if (argv[i][0] != '-')
		{
			pars_count += argoat_increment_pars(args,
				flag,
				argv[i]);
		}
		// lone dash pars
		else if (dash == '\0')
		{
			pars_count += argoat_increment_pars(args,
				flag,
				argv[i]);
		}
		// very probably long flags
		else if (dash == '-')
		{
			// lone double-dash pars
			if (argv[i][2] == '\0')
			{
				pars_count += argoat_increment_pars(args,
					flag,
					argv[i]);
			}
			// long flags
			else
			{
				// executes for previous flag
				argoat_sacrifice(args, flag, pars, pars_count);
				// starts a new flag scope
				flag = argv[i] + 2;
				pars = argv + i + 1;
				pars_count = 0;
			}
		}
		// flags
		else
		{
			// executes for previous flag
			argoat_sacrifice(args, flag, pars, pars_count);

			// compound flags (eg "-xvzf") directly executes
			if ((argv[i][2] != '=') && (argv[i][2] != '\0'))
			{
				// to get rid of the dash
				argoat_compound(args, argv + i);
				flag = NULL;
				pars = NULL;
			}
			// simple flags
			else
			{
				flag = argv[i] + 1;
				pars = argv + i + 1;
			}

			pars_count = 0;
		}
	}

	// we call the function corresponding to the last flag
	argoat_sacrifice(args, flag, pars, pars_count);
	// we call the function handling unflagged pars
	if (args->unflagged_max > 0)
	{
		argoat_unflagged_sacrifice(args);
	}
}
