#include "configator.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

void handle_config_u8(void* data, char** value, const int pars_count)
{
	if (pars_count > 0)
	{
		*((uint8_t*) data) = atoi(*value);
	}
}

void handle_question(void* data, char** value, const int pars_count)
{
	*((uint8_t*) data) = 23;
}

int main(int argc, char** argv)
{
	uint8_t answer = 0;
	uint8_t question = 0;

	// parameters, grouped in sections
	struct configator_param* map_no_section = NULL;
	struct configator_param* map_question_section = NULL;
	struct configator_param map_test_section[] =
	{
		{"aaabbb", &answer, handle_config_u8},
		{"aabbaa", &answer, handle_config_u8},
		{"answer", &answer, handle_config_u8},
		{"cccccc", &answer, handle_config_u8},
		{"cccddd", &answer, handle_config_u8},
		{"daaaaa", &answer, handle_config_u8},
		{"ddaaaa", &answer, handle_config_u8},
		{"eeeeee", &answer, handle_config_u8}
	};
	struct configator_param* map[] =
	{
		map_no_section,
		map_question_section,
		map_test_section
	};

	// sections (used to execute functions at sections start)
	struct configator_param sections[] =
	{
		{"question", &question, handle_question},
		{"test_section", NULL, NULL},
	};

	// number of parameters, by section
	uint16_t map_len[] = {0, 0, 8};
	// number of sections
	uint16_t sections_len = 2;

	// configator object
	struct configator config;
	config.map = map;
	config.map_len = map_len;
	config.sections = sections;
	config.sections_len = sections_len;

	// execute configuration
	configator(&config, "config.ini");
	printf("question = %d\n", question);
	printf("answer = %d\n", answer);

	return 0;
}
