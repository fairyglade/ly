#ifndef H_CONFIGATOR
#define H_CONFIGATOR

#include <stdint.h>

#define CONFIGATOR_MAX_LINE 80

#if 0
#define CONFIGATOR_DEBUG
#endif

struct configator_param
{
	char* key;
	void* data;
	void (*handle)(void* data, char** value, const int pars_count);
};

struct configator
{
	char section[CONFIGATOR_MAX_LINE];
	char param[CONFIGATOR_MAX_LINE];
	char value[CONFIGATOR_MAX_LINE];
	uint16_t current_section;

	struct configator_param** map;
	struct configator_param* sections;

	uint16_t* map_len;
	uint16_t sections_len;
};

int configator(struct configator* config, const char* path);

#endif
