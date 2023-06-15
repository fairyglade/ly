#include "dragonfail.h"
#include "dragonfail_private.h"
#include "dragonfail_error.h"

#ifdef DRAGONFAIL_BASIC_LOG
#include <stdio.h>
#endif

#ifdef DRAGONFAIL_ABORT
#include <stdlib.h>
#endif

// extern
struct dgn dgn;

inline char** dgn_init()
{
	#ifndef DRAGONFAIL_SKIP
		dgn.error = DGN_OK;
		return dgn.log;
	#else
		return NULL;
	#endif
}

inline void dgn_reset()
{
	#ifndef DRAGONFAIL_SKIP
		dgn.error = DGN_OK;
	#endif
}

inline void dgn_basic_log()
{
	#ifdef DRAGONFAIL_BASIC_LOG
	#ifndef DRAGONFAIL_SKIP
		if (dgn.error < DGN_SIZE)
		{
			fprintf(stderr, "%s\n", dgn.log[dgn.error]);
		}
		else
		{
			fprintf(stderr, "%s\n", dgn.log[0]);
		}
	#endif
	#endif
}

inline char* dgn_output_log()
{
	if (dgn.error < DGN_SIZE)
	{
		return dgn.log[dgn.error];
	}
	else
	{
		return dgn.log[0];
	}
}

enum dgn_error dgn_output_code()
{
	return dgn.error;
}

#ifdef DRAGONFAIL_THROW_DEBUG_LOG
inline void dgn_throw_extra(
	enum dgn_error new_code,
	const char* file,
	unsigned int line)
#else
inline void dgn_throw(
	enum dgn_error new_code)
#endif
{
	#ifndef DRAGONFAIL_SKIP
		dgn.error = new_code;

		#ifdef DRAGONFAIL_THROW_BASIC_LOG
		#ifdef DRAGONFAIL_BASIC_LOG
			#ifdef DRAGONFAIL_THROW_DEBUG_LOG
				fprintf(
					stderr,
					"error in %s line %u: ",
					file,
					line);
			#endif

			dgn_basic_log();
		#endif
		#endif

		#ifdef DRAGONFAIL_ABORT
			abort();
		#endif
	#endif
}

inline char dgn_catch()
{
	#ifndef DRAGONFAIL_SKIP
		return (dgn.error != DGN_OK);
	#else
		return 0;
	#endif
}
