#include "configator.h"
#include <stddef.h>
#include <stdio.h>
#include <ctype.h>
#include <string.h>
#include <stdlib.h>

// returns the index of the searched element, or len if it can't be found
static uint16_t search(struct configator_param* config, uint16_t len, char* key)
{
	// strcmp indicator
	int8_t disc;
	// initial tested index
	uint16_t i = len / 2;
	// initial bounds (inclusive)
	uint16_t k = 0;
	uint16_t l = len - 1;

	// skip directly to the final check
	if (len > 1)
	{
		// as long as a match is possible
		do
		{
			disc = strcmp(config[i].key, key);

			if (disc == 0)
			{
				// found by chance
				return i;
			}
			else if (disc > 0)
			{
				l = i;
				i = (i + k) / 2; // floor
			}
			else
			{
				k = i;
				i = (i + l) / 2 + (i + l) % 2; // ceil
			}

			if (len == 2)
			{
				break;
			}
		}
		while ((k+1) != l);
	}

	if (len > 0)
	{
		// final check
		disc = strcmp(config[i].key, key);

		if (disc == 0)
		{
			// found by dichotomy
			return i;
		}
	}

	// not found
	return len;
}

static void configator_save_section(struct configator* config, char* line)
{
	char c;
	uint16_t index;
	uint16_t k = 0; // last non-space pos
	uint16_t l = 0; // second last non-space pos

	// leading spaces
	do
	{
		++line;
		c = line[0];
	}
	while ((c != '\0') && isspace(c));
	
	if (c == '[')
	{
		++line;
		c = line[0];
	}

	// trailing spaces
	for (uint16_t i = 1; c != '\0'; ++i)
	{
		if ((c != ']') && !isspace(c))
		{
			// we use two variables to avoid
			// counting the ending ']'
			l = k + 1; // we *must* increment here
			k = i;
		}

		c = line[i];
	}

	// terminator
	line[l] = '\0';

	if (l == 0)
	{
		return;
	}

	// saving
	strncpy(config->section, line, l + 1);

	// searching
	index = search(
		config->sections,
		config->sections_len,
		config->section);

#ifdef CONFIGATOR_DEBUG
		printf("[%s]\n", line);
#endif

	//  calling the function
	if (index != config->sections_len)
	{
		config->current_section = index + 1;

		if (config->sections[index].handle != NULL)
		{
			config->sections[index].handle(
				config->sections[index].data,
				NULL,
				0);
		}
	}
}

static void configator_save_param(struct configator* config, char* line)
{
	char c;
	uint16_t index;
	uint16_t i = 0;
	uint16_t k = 0;

	// leading chars
	do
	{
		++i;
		c = line[i];
	}
	while ((c != '\0') && (c != '=') && !isspace(c));

	// empty line
	if (c == '\0')
	{
		config->param[0] = '\0';
		config->value[0] = '\0';
		return;
	}

	// end of the param
	k = i;

	// spaces before next char if any
	while ((c != '\0') && isspace(c))
	{
		++i;
		c = line[i];
	}

	// that next char must be '=' 
	if (c != '=')
	{
		config->param[0] = '\0';
		config->value[0] = '\0';
		return;
	}
	else
	{
		++i;
		c = line[i];
	}

	// spaces after '='
	while ((c != '\0') && isspace(c))
	{
		++i;
		c = line[i];
	}

	line[k] = '\0';
	strncpy(config->param, line, k + 1);
	strncpy(config->value, line + i, strlen(line + i) + 1);

	// searching
	if ((config->current_section == 0) && (config->map_len[0] == 0))
	{
		return;
	}

	index = search(
		config->map[config->current_section],
		config->map_len[config->current_section],
		config->param);

#ifdef CONFIGATOR_DEBUG
		printf("%s = \"%s\"\n", config->param, config->value);
#endif

	//  calling the function
	if ((index != config->map_len[config->current_section])
	&& (config->map[config->current_section][index].handle != NULL))
	{
		char* tmp = (char*) config->value;
		config->map[config->current_section][index].handle(
			config->map[config->current_section][index].data,
			&(tmp),
			1);
	}
}

static void configator_read(FILE* fp, char* line)
{
	int c = fgetc(fp);
	uint16_t i = 0;
	uint16_t k = 0;

	if (c == EOF)
	{
		line[0] = '\0';
		return;
	}

	while ((c != '\n') && (c != EOF))
	{
		if ((i < (CONFIGATOR_MAX_LINE + 1)) // maximum len
		&&  ((i > 0) || !isspace(c))) // skips leading spaces
		{
			// used to trim trailing spaces
			// and to terminate overflowing string
			if (!isspace(c))
			{
				k = i;
			}

			line[i] = c;
			++i;
		}

		c = fgetc(fp);
	}

	if (i == (CONFIGATOR_MAX_LINE + 1))
	{
		line[k] = '\0';
	}
	else
	{
		line[k + 1] = '\0';
	}
}

int configator(struct configator* config, const char* path)
{
	FILE* fp = fopen(path, "r");

	if (fp == NULL)
	{
		return -1;
	}

	config->section[0] = '\0';
	config->param[0] = '\0';
	config->value[0] = '\0';
	config->current_section = 0;

	// event loop
	char line[CONFIGATOR_MAX_LINE + 1];

	while (1)
	{
		configator_read(fp, line);

		// end of file
		if (feof(fp))
		{
			break;
		}
		// comment
		else if (line[0] == '#')
		{
			continue;
		}
		// section
		else if ((line[0] == '[') && (line[strlen(line) - 1] == ']'))
		{
			configator_save_section(config, line);
		}
		// param
		else
		{
			configator_save_param(config, line);
		}
	}

	fclose(fp);

	return 0;
}
