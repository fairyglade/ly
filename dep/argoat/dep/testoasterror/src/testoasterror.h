#ifndef H_TESTOASTERROR
#define H_TESTOASTERROR

#include <stdint.h>
#include <stdbool.h>

// main structure
struct testoasterror
{
	// this is a test library so we handle all weird cases
	bool testing;
	
	// test results for one function
	bool* results;
	bool* results_cur;
	bool* results_end;

	// whether the function made too much tests for the results array
	bool failoverflow; // <3
	// execution fail
	bool failexec;

	// test functions
	void (**funcs)(struct testoasterror*);
	uint16_t funcs_index;
	uint16_t funcs_count;
};

// testoasterror can be static if you want it to (:
void testoasterror_init(
	struct testoasterror* test,
	bool* results,
	uint8_t max,
	void (**funcs)(struct testoasterror*),
	uint16_t count);
bool testoasterror_run(struct testoasterror* test);
bool testoasterror(struct testoasterror* test, bool expr);
void testoasterror_count(struct testoasterror* test, uint16_t count);
void testoasterror_fail(struct testoasterror* test);

#endif
