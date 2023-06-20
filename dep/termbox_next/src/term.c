#include <sys/stat.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "term.h"
#define ENTER_MOUSE_SEQ "\x1b[?1000h\x1b[?1002h\x1b[?1015h\x1b[?1006h"
#define EXIT_MOUSE_SEQ "\x1b[?1006l\x1b[?1015l\x1b[?1002l\x1b[?1000l"

#define EUNSUPPORTED_TERM -1

// rxvt-256color
static const char* rxvt_256color_keys[] =
{
	"\033[11~", "\033[12~", "\033[13~", "\033[14~", "\033[15~", "\033[17~",
	"\033[18~", "\033[19~", "\033[20~", "\033[21~", "\033[23~", "\033[24~",
	"\033[2~", "\033[3~", "\033[7~", "\033[8~", "\033[5~", "\033[6~",
	"\033[A", "\033[B", "\033[D", "\033[C", NULL
};
static const char* rxvt_256color_funcs[] =
{
	"\0337\033[?47h", "\033[2J\033[?47l\0338", "\033[?25h", "\033[?25l",
	"\033[H\033[2J", "\033[m", "\033[4m", "\033[1m", "\033[5m", "\033[7m",
	"\033=", "\033>", ENTER_MOUSE_SEQ, EXIT_MOUSE_SEQ,
};

// Eterm
static const char* eterm_keys[] =
{
	"\033[11~", "\033[12~", "\033[13~", "\033[14~", "\033[15~", "\033[17~",
	"\033[18~", "\033[19~", "\033[20~", "\033[21~", "\033[23~", "\033[24~",
	"\033[2~", "\033[3~", "\033[7~", "\033[8~", "\033[5~", "\033[6~",
	"\033[A", "\033[B", "\033[D", "\033[C", NULL
};
static const char* eterm_funcs[] =
{
	"\0337\033[?47h", "\033[2J\033[?47l\0338", "\033[?25h", "\033[?25l",
	"\033[H\033[2J", "\033[m", "\033[4m", "\033[1m", "\033[5m", "\033[7m",
	"", "", "", "",
};

// screen
static const char* screen_keys[] =
{
	"\033OP", "\033OQ", "\033OR", "\033OS", "\033[15~", "\033[17~",
	"\033[18~", "\033[19~", "\033[20~", "\033[21~", "\033[23~", "\033[24~",
	"\033[2~", "\033[3~", "\033[1~", "\033[4~", "\033[5~", "\033[6~",
	"\033OA", "\033OB", "\033OD", "\033OC", NULL
};
static const char* screen_funcs[] =
{
	"\033[?1049h", "\033[?1049l", "\033[34h\033[?25h", "\033[?25l",
	"\033[H\033[J", "\033[m", "\033[4m", "\033[1m", "\033[5m", "\033[7m",
	"\033[?1h\033=", "\033[?1l\033>", ENTER_MOUSE_SEQ, EXIT_MOUSE_SEQ,
};

// rxvt-unicode
static const char* rxvt_unicode_keys[] =
{
	"\033[11~", "\033[12~", "\033[13~", "\033[14~", "\033[15~", "\033[17~",
	"\033[18~", "\033[19~", "\033[20~", "\033[21~", "\033[23~", "\033[24~",
	"\033[2~", "\033[3~", "\033[7~", "\033[8~", "\033[5~", "\033[6~",
	"\033[A", "\033[B", "\033[D", "\033[C", NULL
};
static const char* rxvt_unicode_funcs[] =
{
	"\033[?1049h", "\033[r\033[?1049l", "\033[?25h", "\033[?25l",
	"\033[H\033[2J", "\033[m\033(B", "\033[4m", "\033[1m", "\033[5m",
	"\033[7m", "\033=", "\033>", ENTER_MOUSE_SEQ, EXIT_MOUSE_SEQ,
};

// linux
static const char* linux_keys[] =
{
	"\033[[A", "\033[[B", "\033[[C", "\033[[D", "\033[[E", "\033[17~",
	"\033[18~", "\033[19~", "\033[20~", "\033[21~", "\033[23~", "\033[24~",
	"\033[2~", "\033[3~", "\033[1~", "\033[4~", "\033[5~", "\033[6~",
	"\033[A", "\033[B", "\033[D", "\033[C", NULL
};
static const char* linux_funcs[] =
{
	"", "", "\033[?25h\033[?0c", "\033[?25l\033[?1c", "\033[H\033[J",
	"\033[0;10m", "\033[4m", "\033[1m", "\033[5m", "\033[7m", "", "", "", "",
};

// xterm
static const char* xterm_keys[] =
{
	"\033OP", "\033OQ", "\033OR", "\033OS", "\033[15~", "\033[17~", "\033[18~",
	"\033[19~", "\033[20~", "\033[21~", "\033[23~", "\033[24~", "\033[2~",
	"\033[3~", "\033OH", "\033OF", "\033[5~", "\033[6~", "\033OA", "\033OB",
	"\033OD", "\033OC", NULL
};
static const char* xterm_funcs[] =
{
	"\033[?1049h", "\033[?1049l", "\033[?12l\033[?25h", "\033[?25l",
	"\033[H\033[2J", "\033(B\033[m", "\033[4m", "\033[1m", "\033[5m", "\033[7m",
	"\033[?1h\033=", "\033[?1l\033>", ENTER_MOUSE_SEQ, EXIT_MOUSE_SEQ,
};

struct term
{
	const char* name;
	const char** keys;
	const char** funcs;
};

static struct term terms[] =
{
	{"rxvt-256color", rxvt_256color_keys, rxvt_256color_funcs},
	{"Eterm", eterm_keys, eterm_funcs},
	{"screen", screen_keys, screen_funcs},
	{"rxvt-unicode", rxvt_unicode_keys, rxvt_unicode_funcs},
	{"linux", linux_keys, linux_funcs},
	{"xterm", xterm_keys, xterm_funcs},
	{0, 0, 0},
};

static int init_from_terminfo = 0;
const char** keys;
const char** funcs;

static int try_compatible(const char* term, const char* name,
	const char** tkeys, const char** tfuncs)
{
	if (strstr(term, name))
	{
		keys = tkeys;
		funcs = tfuncs;
		return 0;
	}

	return EUNSUPPORTED_TERM;
}

static int init_term_builtin(void)
{
	int i;
	const char* term = getenv("TERM");

	if (term)
	{
		for (i = 0; terms[i].name; i++)
		{
			if (!strcmp(terms[i].name, term))
			{
				keys = terms[i].keys;
				funcs = terms[i].funcs;
				return 0;
			}
		}

		// let's do some heuristic, maybe it's a compatible terminal
		if (try_compatible(term, "xterm", xterm_keys, xterm_funcs) == 0)
		{
			return 0;
		}

		if (try_compatible(term, "rxvt", rxvt_unicode_keys, rxvt_unicode_funcs) == 0)
		{
			return 0;
		}

		if (try_compatible(term, "linux", linux_keys, linux_funcs) == 0)
		{
			return 0;
		}

		if (try_compatible(term, "Eterm", eterm_keys, eterm_funcs) == 0)
		{
			return 0;
		}

		if (try_compatible(term, "screen", screen_keys, screen_funcs) == 0)
		{
			return 0;
		}

		// let's assume that 'cygwin' is xterm compatible
		if (try_compatible(term, "cygwin", xterm_keys, xterm_funcs) == 0)
		{
			return 0;
		}
	}

	return EUNSUPPORTED_TERM;
}

// terminfo
static char* read_file(const char* file)
{
	FILE* f = fopen(file, "rb");

	if (!f)
	{
		return 0;
	}

	struct stat st;

	if (fstat(fileno(f), &st) != 0)
	{
		fclose(f);
		return 0;
	}

	char* data = malloc(st.st_size);

	if (!data)
	{
		fclose(f);
		return 0;
	}

	if (fread(data, 1, st.st_size, f) != (size_t)st.st_size)
	{
		fclose(f);
		free(data);
		return 0;
	}

	fclose(f);
	return data;
}

static char* terminfo_try_path(const char* path, const char* term)
{
	char tmp[4096];
	snprintf(tmp, sizeof(tmp), "%s/%c/%s", path, term[0], term);
	tmp[sizeof(tmp) - 1] = '\0';
	char* data = read_file(tmp);

	if (data)
	{
		return data;
	}

	// fallback to darwin specific dirs structure
	snprintf(tmp, sizeof(tmp), "%s/%x/%s", path, term[0], term);
	tmp[sizeof(tmp) - 1] = '\0';
	return read_file(tmp);
}

static char* load_terminfo(void)
{
	char tmp[4096];
	const char* term = getenv("TERM");

	if (!term)
	{
		return 0;
	}

	// if TERMINFO is set, no other directory should be searched
	const char* terminfo = getenv("TERMINFO");

	if (terminfo)
	{
		return terminfo_try_path(terminfo, term);
	}

	// next, consider ~/.terminfo
	const char* home = getenv("HOME");

	if (home)
	{
		snprintf(tmp, sizeof(tmp), "%s/.terminfo", home);
		tmp[sizeof(tmp) - 1] = '\0';
		char* data = terminfo_try_path(tmp, term);

		if (data)
		{
			return data;
		}
	}

	// next, TERMINFO_DIRS
	const char* dirs = getenv("TERMINFO_DIRS");

	if (dirs)
	{
		snprintf(tmp, sizeof(tmp), "%s", dirs);
		tmp[sizeof(tmp) - 1] = '\0';
		char* dir = strtok(tmp, ":");

		while (dir)
		{
			const char* cdir = dir;

			if (strcmp(cdir, "") == 0)
			{
				cdir = "/usr/share/terminfo";
			}

			char* data = terminfo_try_path(cdir, term);

			if (data)
			{
				return data;
			}

			dir = strtok(0, ":");
		}
	}

	// fallback to /usr/share/terminfo
	return terminfo_try_path("/usr/share/terminfo", term);
}

#define TI_MAGIC 0432
#define TI_ALT_MAGIC 542
#define TI_HEADER_LENGTH 12
#define TB_KEYS_NUM 22

static const char* terminfo_copy_string(char* data, int str, int table)
{
	const int16_t off = *(int16_t*)(data + str);
	const char* src = data + table + off;
	int len = strlen(src);
	char* dst = malloc(len + 1);
	strcpy(dst, src);
	return dst;
}

const int16_t ti_funcs[] =
{
	28, 40, 16, 13, 5, 39, 36, 27, 26, 34, 89, 88,
};

const int16_t ti_keys[] =
{
	// apparently not a typo; 67 is F10 for whatever reason
	66, 68, 69, 70, 71, 72, 73, 74, 75, 67, 216, 217, 77, 59, 76, 164, 82,
	81, 87, 61, 79, 83,
};

int init_term(void)
{
	int i;
	char* data = load_terminfo();

	if (!data)
	{
		init_from_terminfo = 0;
		return init_term_builtin();
	}

	int16_t* header = (int16_t*)data;

	const int number_sec_len = header[0] == TI_ALT_MAGIC ? 4 : 2;

	if ((header[1] + header[2]) % 2)
	{
		// old quirk to align everything on word boundaries
		header[2] += 1;
	}

	const int str_offset = TI_HEADER_LENGTH +
		header[1] + header[2] +	number_sec_len * header[3];
	const int table_offset = str_offset + 2 * header[4];

	keys = malloc(sizeof(const char*) * (TB_KEYS_NUM + 1));

	for (i = 0; i < TB_KEYS_NUM; i++)
	{
		keys[i] = terminfo_copy_string(data,
				str_offset + 2 * ti_keys[i], table_offset);
	}

	keys[i] = NULL;

	funcs = malloc(sizeof(const char*) * T_FUNCS_NUM);

	// the last two entries are reserved for mouse. because the table offset is
	// not there, the two entries have to fill in manually
	for (i = 0; i < T_FUNCS_NUM - 2; i++)
	{
		funcs[i] = terminfo_copy_string(data,
				str_offset + 2 * ti_funcs[i], table_offset);
	}

	funcs[T_FUNCS_NUM - 2] = ENTER_MOUSE_SEQ;
	funcs[T_FUNCS_NUM - 1] = EXIT_MOUSE_SEQ;
	init_from_terminfo = 1;
	free(data);
	return 0;
}

void shutdown_term(void)
{
	if (init_from_terminfo)
	{
		int i;

		for (i = 0; i < TB_KEYS_NUM; i++)
		{
			free((void*)keys[i]);
		}

		// the last two entries are reserved for mouse. because the table offset
		// is not there, the two entries have to fill in manually and do not
		// need to be freed.
		for (i = 0; i < T_FUNCS_NUM - 2; i++)
		{
			free((void*)funcs[i]);
		}

		free(keys);
		free(funcs);
	}
}
