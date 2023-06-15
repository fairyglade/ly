#ifndef C_TESTS
#define C_TESTS

#include "testoasterror.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

void test_tool(struct testoasterror* test, uint8_t id, char* args, char* cmp)
{
	char* ret;
	char buf[32];
	char cmd[128];
	char cmp_ln[16];

	snprintf(cmd, 128, "./argoat_sample_%u %s 2>&1", id, args);
	snprintf(cmp_ln, 16, "%s\n", cmp);

	FILE* fp = popen(cmd, "r");
	testoasterror(test, fp != NULL);

	ret = fgets(buf, 32, fp);
	testoasterror(test, (ret != NULL) && (strcmp(buf, cmp_ln) == 0));
	fclose(fp);
}

void test1(struct testoasterror* test)
{
	test_tool(test, 1, "", "t   ");

	test_tool(test, 1, "-l", "tl  ");
	test_tool(test, 1, "-m", "t m ");
	test_tool(test, 1, "-o", "t  o");

	test_tool(test, 1, "--l", "tl  ");
	test_tool(test, 1, "--long", "t   ");

	test_tool(test, 1, "-lmo", "tlmo");
	test_tool(test, 1, "-lm -o", "tlmo");
	test_tool(test, 1, "-l -m -o", "tlmo");

	test_tool(test, 1, "-l 1 -m 2 -o 3", "tlmo");

	test_tool(test, 1, "-l - -m", "tlm ");
	test_tool(test, 1, "-l --m 3", "tlm ");
	test_tool(test, 1, "-l --m=3", "tlm ");
}

void test2(struct testoasterror* test)
{
	test_tool(test, 2, "--long", "tl  ");
	test_tool(test, 2, "--mighty", "t m ");
	test_tool(test, 2, "--options", "t  o");

	test_tool(test, 2, "-l", "t   ");
	test_tool(test, 2, "-long", "t   ");

	test_tool(test, 2, "--long --mighty --options", "tlmo");
	test_tool(test, 2, "0 --long 1 --mighty 2 --options 3", "0123tlmo");
	test_tool(test, 2, "0 --long=1 --mighty 2 --options 3", "023tlmo");
	test_tool(test, 2, "0 --long=1 4 --mighty 2 --options 3", "0423tlmo");

	test_tool(test, 2, "0 --long - --mighty -- --options 3", "0---3tlmo");
}

void test3(struct testoasterror* test)
{
	test_tool(test, 3, "-t", "tl0");
	test_tool(test, 3, "--tau", "t 0");
	test_tool(test, 3, "--text", "t 0");

	test_tool(test, 3, "-t --tau 3 4 5", "5tl7");
	test_tool(test, 3, "--tau=3 4 5", "45t 0");
	test_tool(test, 3, "--text one two", "twot 0one");

	test_tool(test, 3, "--text= one two", "onetwot 0");
}

#endif
