#include "cylgom.h"
#include "termbox.h"
#include "draw.h"
#include "desktop.h"
#include "config.h"
#include "inputs.h"
#include "login.h"
#include "util.h"
#include <unistd.h>
#include <stdio.h>
#include <string.h>

enum active_input {INPUT_DESKTOP, INPUT_LOGIN, INPUT_PASSWORD};
enum shutdown {SHUTDOWN_NO, SHUTDOWN_YES, SHUTDOWN_REBOOT};

bool args(int argc, char** argv)
{
	char* arg;

	while (argc > 0)
	{
		arg = argv[argc - 1];

		if (strcmp(arg, "-v") == 0
			|| strcmp(arg, "--version") == 0)
		{
			printf("ly version %s\n", GIT_VERSION_STRING);
			return false;
		}

		--argc;
	}

	return true;
}

int main(int argc, char** argv)
{
	struct desktop desktop;
	struct input login;
	struct input password;
	struct tb_event event;
	enum shutdown shutdown = SHUTDOWN_NO;
	enum active_input active_input;
	enum err error = OK;
	enum err status;

	if (!args(argc, argv))
	{
		return 0;
	}

	void* input_structs[3] = 
	{
		(void*) &desktop, 
		(void*) &login, 
		(void*) &password
	};

	void (*input_handles[3]) (void*, struct tb_event*) =
	{
		handle_desktop,
		handle_text,
		handle_text
	};

	active_input = INPUT_PASSWORD;
	config_load("/etc/ly/config.ini");

	widget_desktop(&desktop);
	widget_input(&login, config.max_login_len);
	widget_input(&password, config.max_password_len);

	desktop_load(&desktop);

	tb_init();
	tb_select_output_mode(TB_OUTPUT_TRUECOLOR);
	tb_clear();

	draw_init();
	draw_box();
	draw_labels();
	draw_f_commands();
	draw_lock_state();

	position_input(&desktop, &login, &password);
	load(&desktop, &login);
	draw_desktop(&desktop);
	draw_input(&login);
	draw_input_mask(&password);

	(*input_handles[active_input])(input_structs[active_input], NULL);

	tb_present();

	switch_tty();

	bool run = true;

	while (run)
	{
		error = tb_peek_event(&event, config.min_refresh_delta);

		if (error < 0)
		{
			continue;
		}

		if (event.type == TB_EVENT_KEY)
		{
			if (event.key == TB_KEY_F1)
			{
				shutdown = SHUTDOWN_YES;
				break;
			}
			else if (event.key == TB_KEY_F2)
			{
				shutdown = SHUTDOWN_REBOOT;
				break;
			}
			else if (event.key == TB_KEY_CTRL_C)
			{
				break;
			}
			else if ((event.key == TB_KEY_ARROW_UP) && (active_input > 0))
			{
				--active_input;
			}
			else if (((event.key == TB_KEY_ARROW_DOWN) || (event.key == TB_KEY_ENTER))
				&& (active_input < 2))
			{
				++active_input;
			}
			else if (event.key == TB_KEY_ENTER)
			{
				save(&desktop, &login);
				status = login_desktop(&desktop, &login, &password);
				load(&desktop, &login);
				error = 1; // triggers cursor and screen update

				if (status != OK)
				{
					++config.auth_fails;
					config.old_min_refresh_delta = config.min_refresh_delta;
					config.old_force_update = config.force_update;
					config.min_refresh_delta = 10;
					config.force_update = true;
				}
			}
		}

		if (error > 0)
		{
			// calls the apropriate function depending on the active input
			(*input_handles[active_input])(input_structs[active_input], &event);
		}

		if (config.force_update || (error > 0))
		{
			if (config.auth_fails < 10)
			{
				tb_clear();

				draw_init();
				animate();
				draw_box();
				draw_labels();
				draw_f_commands();
				draw_lock_state();

				position_input(&desktop, &login, &password);
				draw_desktop(&desktop);
				draw_input(&login);
				draw_input_mask(&password);
			}
			else
			{
				cascade();
			}
		}

		tb_present();
	}

	// TODO error
	tb_shutdown();

	widget_desktop_free(&desktop);
	widget_input_free(&login);
	widget_input_free(&password);
	config_lang_free();
	free_hostname();

	if (shutdown == SHUTDOWN_YES)
	{
		execl(config.shutdown_cmd, config.shutdown_cmd, "-h", "now", NULL);
	}
	if (shutdown == SHUTDOWN_REBOOT)
	{
		execl(config.shutdown_cmd, config.shutdown_cmd, "-r", "now", NULL);
	}

	config_config_free();

	return 0;
}
