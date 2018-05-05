#define _XOPEN_SOURCE

/* stdlib */
#include <string.h>
#include <stdlib.h>
/* linux */
#include <sys/wait.h>
#include <sys/types.h>
#include <sys/ioctl.h>
#include <linux/vt.h>
#include <unistd.h>
/* ncurses */
#include <form.h>
/* pam */
#include <security/pam_appl.h>
/* ly */
#include "lang.h"
#include "config.h"
#include "utils.h"
#include "login.h"
#include "desktop.h"
#include "ncui.h"

#define KEY_TAB_ASCII 8
#define KEY_ENTER_ASCII 10
#define KEY_BACKSPACE_ASCII 127

int main(void)
{
	FILE* console;
	/* user interface components */
	struct ncform form;
	struct ncwin win;
	/* desktop environments list */
	enum deserv_t type;
	struct delist_t* de_list;
	struct deprops_t* de_props;
	char** de_names;
	int de_count;
	int de_id;
	/* user input */
	int input_key;
	/* processing buffers */
	int fail;
	int auth_fails;
	char* username;
	char* password;
	char* cmd;
	/* gets desktop entries */
	de_list = list_de();
	de_props = de_list->props;
	de_names = de_list->names;
	de_count = de_list->count;
	de_id = 0;
	auth_fails = 0;
	/* verifies if we can access the console with enough privileges */
	console = fopen(LY_CONSOLE_DEV, "w");

	if(!console)
	{
		fprintf(stderr, "%s\n", LY_ERR_FD);
		fprintf(stderr, "%s\n", LY_ERR_FD_ADVICE);
		return 0;
	}

	kernel_log(0);
	/* initializes ncurses UI */
	init_ncurses(console);
	init_form(&form, de_names, de_count, &de_id);
	init_win(&win, &form);
	init_scene(&win, &form);
	init_draw(&win, &form);
	close(fileno(console));
	/* enables insertion mode */
	form_driver(form.form, REQ_INS_MODE);
	/* makes the password field active by default */
	set_current_field(form.form, form.fields[4]);
	form_driver(form.form, REQ_END_LINE);

	while((input_key = wgetch(win.win)))
	{
		form.active = current_field(form.form);

		switch(input_key)
		{
			case KEY_ENTER_ASCII:
				if(form.active == form.fields[4])
				{
					/* checks for buffer errors */
					if(form_driver(form.form, REQ_VALIDATION) != E_OK)
					{
						error_print(LY_ERR_NC_BUFFER);
						break;
					}

					/* stores the user inputs in processing buffers */
					username = trim(field_buffer(form.fields[2], 0));
					password = trim(field_buffer(form.fields[4], 0));
					cmd = de_props[de_id].cmd;
					type = de_props[de_id].type;

					/* saves the username and DE if enabled */
					if(LY_CFG_WRITE_SAVE)
					{
						FILE* file = fopen(LY_CFG_SAVE, "ab+");
						file = fopen(LY_CFG_SAVE, "wb");
						fprintf(file, "%s\n%d", username, de_id);
						fclose(file);
					}

					/* logs in and suspends ncurses mode if successful */
					fail = start_env(username, password, cmd, type);
					/* clears the password */
					set_field_buffer(form.fields[4], 0, "");

					if(fail)
					{
						++auth_fails;

						if(auth_fails > (LY_CFG_AUTH_TRIG - 1))
						{
							cascade();
						}
					}
					else if(LY_CFG_CLR_USR)
					{
						/* clears the username */
						set_field_buffer(form.fields[2], 0, "");
						/* sets cursor to the login field */
						set_current_field(form.form, form.fields[2]);
						break;
					}

					/* sets cursor to the password field */
					set_current_field(form.form, form.fields[4]);
					break;
				}

			case KEY_TAB_ASCII:
			case KEY_DOWN:
				form_driver(form.form, REQ_NEXT_FIELD);
				form_driver(form.form, REQ_END_LINE);
				break;

			case KEY_BTAB:
			case KEY_UP:
				form_driver(form.form, REQ_PREV_FIELD);
				form_driver(form.form, REQ_END_LINE);
				break;

			case KEY_RIGHT:
				if(form.active == form.fields[0])
				{
					de_id = ((de_id + 1) == de_count) ? 0 : de_id + 1;
					form_driver(form.form, REQ_NEXT_CHOICE);
				}
				else
				{
					form_driver(form.form, REQ_NEXT_CHAR);
				}

				break;

			case KEY_LEFT:
				if(form.active == form.fields[0])
				{
					de_id = (de_id == 0) ? (de_count - 1) : de_id - 1;
					form_driver(form.form, REQ_PREV_CHOICE);
				}
				else
				{
					form_driver(form.form, REQ_PREV_CHAR);
				}

				break;

			case KEY_BACKSPACE_ASCII:
			case KEY_BACKSPACE:
				form_driver(form.form, REQ_DEL_PREV);
				form_driver(form.form, REQ_END_LINE);
				break;

			case KEY_DC:
				form_driver(form.form, REQ_DEL_CHAR);
				break;

			case KEY_F(1):
				end_form(&form);
				endwin();
				free_list(de_list);
				execl(LY_CMD_HALT, LY_CMD_HALT, "-h", "now", NULL);
				break;

			case KEY_F(2):
				end_form(&form);
				endwin();
				free_list(de_list);
				execl(LY_CMD_HALT, LY_CMD_HALT, "-r", "now", NULL);
				break;

			default:
				form_driver(form.form, input_key);
				break;
		}
	}

	kernel_log(1);
	fclose(console);
	free_list(de_list);
	end_form(&form);
	endwin();
	return 0;
}
