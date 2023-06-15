#include "testoasterror.h"
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>

void testoasterror_init(
	struct testoasterror* test,
	bool* results,
	uint8_t max,
	void (**funcs)(struct testoasterror*),
	uint16_t count)
{
	test->testing = false;
	test->results = results;
	test->results_end = results + max;

	test->funcs = funcs;
	test->funcs_count = count;
}

bool testoasterror_log(struct testoasterror* test)
{
	bool* results = test->results;
	uint8_t max = test->results_cur - results;
	uint8_t passed_expr = 0;

	// checks the saved status of all processed expressions
	for (uint8_t i = 0; i < max; ++i)
	{
		if (results[i])
		{
			++passed_expr;
		}
		else
		{
			// first fail
			if (passed_expr == i)
			{
				fprintf(stderr, "failed expression ids:");
			}

			fprintf(stderr, " %u", i);
		}
	}

	// newline if we printed any failed expression id
	if (passed_expr != max)
	{
		fprintf(stderr, "\n");
	}

	if (test->failexec)
	{
		fprintf(
			stderr,
			"aborted before expression: %u\n",
			max);
	}

	// expressions summary
	fprintf(
		stderr, 
		"expressions: %u passed, %u failed\n",
		passed_expr,
		max - passed_expr);

	return (passed_expr == max);
}

bool testoasterror_run(struct testoasterror* test)
{
	// don't run tests in tests...
	if (test->testing == true)
	{
		return false;
	}

	char* result;
	bool func_passed;
	uint16_t tests_passed = 0;

	fprintf(
		stderr,
		"running %u tests with %u expr slots\n\n",
		test->funcs_count,
		(uint8_t) (test->results_end - test->results));

	// runs the test functions from the given function pointers
	for (uint16_t i = 0; i < test->funcs_count; ++i)
	{
		// resets the expr results
		test->results_cur = test->results;
		test->failoverflow = false;
		test->failexec = false;

		// runs the test
		test->funcs_index = i;
		test->funcs[i](test);

		// outputs info (a fail overflow is considered a fail)
		func_passed = testoasterror_log(test)
			&& !test->failoverflow
			&& !test->failexec;
		tests_passed += func_passed;

		// generates a message describing the test results
		if (test->failoverflow == true)
		{
			result = "encountered a fail overflow";
		}
		else if (test->failexec == true)
		{
			result = "aborted";
		}
		else
		{
			result = func_passed ? "passed" : "failed";
		}

		// test status
		fprintf(stderr, "test #%u %s\n\n", i, result);
	}

	// tests summary
	fprintf(
		stderr,
		"tests: %u passed, %u failed\n",
		tests_passed,
		test->funcs_count - tests_passed);

	return (test->funcs_count == tests_passed);
}

// save a test status
bool testoasterror(struct testoasterror* test, bool expr)
{
	if (test->results_cur < test->results_end)
	{
		*(test->results_cur) = expr;
		++(test->results_cur);
	}
	else
	{
		test->failoverflow = true;
	}

	return expr;
}

// handles set execution fails
void testoasterror_fail(struct testoasterror* test)
{
	test->failexec = true;
}
