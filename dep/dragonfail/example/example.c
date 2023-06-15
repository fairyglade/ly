#include <stdio.h>
#include "dragonfail.h"

int div(int num, int den)
{
	if (den == 0)
	{
		dgn_throw(DGN_DOMAIN);
		return 0;
	}

	return num / den;
}

void log_init(char** log)
{
	log[DGN_OK] = "out-of-bounds log message"; // special case
	log[DGN_NULL] = "null pointer";
	log[DGN_ALLOC] = "failed memory allocation";
	log[DGN_BOUNDS] = "out-of-bounds index";
	log[DGN_DOMAIN] = "invalid domain";
}

int main()
{
	log_init(dgn_init());

	int i;
	int q;

	for (i = -2; i < 3; ++i)
	{
		q = div(42, i);

		if (dgn_catch())
		{
			printf("skipping division by zero\n");
			dgn_reset();
			continue;
		}

		printf("42/%d = %d\n", i, q);
	}

	return 0;
}
