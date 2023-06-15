#ifndef H_DRAGONFAIL
#define H_DRAGONFAIL

#include "dragonfail_error.h"

#ifdef DRAGONFAIL_THROW_DEBUG_LOG
	#define dgn_throw(new_code) dgn_throw_extra(new_code, DGN_FILE, DGN_LINE)
	#define DGN_FILE __FILE__
	#define DGN_LINE __LINE__
	void dgn_throw_extra(enum dgn_error new_code, const char* file, unsigned int line);
#else
	void dgn_throw(enum dgn_error new_code);
#endif

char** dgn_init();
void dgn_reset();
void dgn_basic_log();
char* dgn_output_log();
enum dgn_error dgn_output_code();
char dgn_catch();

#endif
