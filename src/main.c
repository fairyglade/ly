#include "argoat.h"
#include "configator.h"
#include "dragonfail.h"
#include "termbox.h"
#include "ctypes.h"

#include "draw.h"
#include "inputs.h"
#include "login.h"
#include "utils.h"
#include "config.h"

#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>

#define ARG_COUNT 5
// things you can define:
// GIT_VERSION_STRING
// RUNIT

// global
struct lang lang;
struct config config;

// args handles
void arg_help(void* data, char** pars, const int pars_count)
{
	printf("RTFM\n");
}

void arg_version(void* data, char** pars, const int pars_count)
{
#ifdef GIT_VERSION_STRING
	printf("Ly version %s\n", GIT_VERSION_STRING);
#else
	printf("Ly version unknown\n");
#endif
}

// low-level error messages
void log_init(char** log)
{
	log[DGN_OK] = lang.err_dgn_oob;
	log[DGN_NULL] = lang.err_null;
	log[DGN_ALLOC] = lang.err_alloc;
	log[DGN_BOUNDS] = lang.err_bounds;
	log[DGN_DOMAIN] = lang.err_domain; 
	log[DGN_MLOCK] = lang.err_mlock;
	log[DGN_XSESSIONS_DIR] = lang.err_xsessions_dir;
	log[DGN_XSESSIONS_OPEN] = lang.err_xsessions_open;
	log[DGN_PATH] = lang.err_path;
	log[DGN_CHDIR] = lang.err_chdir;
	log[DGN_PWNAM] = lang.err_pwnam;
	log[DGN_USER_INIT] = lang.err_user_init;
	log[DGN_USER_GID] = lang.err_user_gid;
	log[DGN_USER_UID] = lang.err_user_uid;
	log[DGN_PAM] = lang.err_pam;
	log[DGN_HOSTNAME] = lang.err_hostname;
}

// ly!
int main(int argc, char** argv)
{
	// init error lib
	log_init(dgn_init());

	// load config
	config_defaults();
	lang_defaults();

	config_load();

	if (strcmp(config.lang, "en") != 0)
	{
		lang_load();
	}

	// parse args
	const struct argoat_sprig sprigs[ARG_COUNT] =
	{
		{NULL, 0, NULL, NULL},
		{"help", 0, NULL, arg_help},
		{"h", 0, NULL, arg_help},
		{"version", 0, NULL, arg_version},
		{"v", 0, NULL, arg_version},
	};

	struct argoat args = {sprigs, ARG_COUNT, NULL, 0, 0};
	argoat_graze(&args, argc, argv);

	// init inputs
	struct desktop desktop;
	struct text login;
	struct text password;
	input_desktop(&desktop);
	input_text(&login, config.max_login_len);
	input_text(&password, config.max_password_len);

	if (dgn_catch())
	{
		config_free();
		lang_free();
		return 1;
	}

	void* input_structs[3] =
	{
		(void*) &desktop,
		(void*) &login,
		(void*) &password,
	};

	void (*input_handles[3]) (void*, struct tb_event*) =
	{
		handle_desktop,
		handle_text,
		handle_text,
	};

	desktop_load(&desktop);
	load(&desktop, &login);

	// start termbox
	tb_init();
	tb_select_output_mode(TB_OUTPUT_256);
	tb_clear();

	// init visible elements
	struct tb_event event;
	struct term_buf buf;
	u8 active_input = config.default_input;

	(*input_handles[active_input])(input_structs[active_input], NULL);

	// init drawing stuff
	draw_init(&buf);

	if (config.animate)
	{
		animate_init(&buf);

		if (dgn_catch())
		{
			config.animate = false;
			dgn_reset();
		}
	}

	// init state info
	int error;
	bool run = true;
	bool update = true;
	bool reboot = false;
	bool shutdown = false;
	u8 auth_fails = 0;

	switch_tty(&buf);

	// main loop
	while (run)
	{
		if (update)
		{
			if (auth_fails < 10)
			{
				tb_clear();
				animate(&buf);
				draw_box(&buf);
				draw_labels(&buf);
				draw_f_commands();
				draw_lock_state(&buf);
				position_input(&buf, &desktop, &login, &password);
				draw_desktop(&desktop);
				draw_input(&login);
				draw_input_mask(&password);
				update = config.animate;
			}
			else
			{
				usleep(10000);
				update = cascade(&buf, &auth_fails);
			}

			tb_present();
		}

		error = tb_peek_event(&event, config.min_refresh_delta);

		if (error < 0)
		{
			continue;
		}

		if (event.type == TB_EVENT_KEY)
		{
			if (event.key == TB_KEY_F1)
			{
				shutdown = true;
				break;
			}
			else if (event.key == TB_KEY_F2)
			{
				reboot = true;
				break;
			}
			else if (event.key == TB_KEY_CTRL_C)
			{
				break;
			}
			else if ((event.key == TB_KEY_ARROW_UP) && (active_input > 0))
			{
				--active_input;
				update = true;
			}
			else if (((event.key == TB_KEY_ARROW_DOWN)
				|| (event.key == TB_KEY_ENTER))
				&& (active_input < 2))
			{
				++active_input;
				update = true;
			}
			else if (event.key == TB_KEY_TAB)
			{
				++active_input;

				if (active_input > 2)
				{
					active_input = 0;
				}

				update = true;
			}
			else if (event.key == TB_KEY_ENTER)
			{
				save(&desktop, &login);
				auth(&desktop, &login, &password, &buf);
				update = true;

				if (dgn_catch())
				{
					++auth_fails;

					if (dgn_output_code() != DGN_PAM)
					{
						buf.info_line = dgn_output_log();
					}

					dgn_reset();
				}
				else
				{
					buf.info_line = lang.logout;
				}

				load(&desktop, &login);
			}
			else
			{
				(*input_handles[active_input])(
					input_structs[active_input],
					&event);
				update = true;
			}
		}
	}

	// stop termbox
	tb_shutdown();

	// free inputs
	input_desktop_free(&desktop);
	input_text_free(&login);
	input_text_free(&password);
	free_hostname();

	// unload config
	draw_free(&buf);
	lang_free();

	if (shutdown)
	{
		execl("/bin/sh", "sh", "-c", config.shutdown_cmd, NULL);
	}

	if (reboot)
	{
		execl("/bin/sh", "sh", "-c", config.restart_cmd, NULL);
	}

	config_free();

	return 0;
}
