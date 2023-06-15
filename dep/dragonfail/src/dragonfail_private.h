#ifndef H_DRAGONFAIL_PRIVATE
#define H_DRAGONFAIL_PRIVATE

#include "dragonfail_error.h"

struct dgn
{
	enum dgn_error error;
	char* log[DGN_SIZE];
};

extern struct dgn dgn;

#endif
