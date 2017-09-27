#ifndef _LOGIN_H_
#define _LOGIN_H_

#include <security/pam_appl.h>
#include <pwd.h>
#include "desktop.h"

int login_conv(int num_msg, const struct pam_message** msg,
struct pam_response** resp, void* appdata_ptr);
int start_env(const char* username, const char* password,
const char* de_command, enum deserv_t display_server);
void launch_xorg(struct passwd* pwd, pam_handle_t* pam_handle,
const char* de_command, const char* display_name, const char* vt,
int xinitrc);
void launch_wayland(struct passwd* pwd, pam_handle_t* pam_handle,
const char* de_command);
void launch_shell(struct passwd* pwd, pam_handle_t* pam_handle);
void destroy_env(void);
void init_xdg(const char* tty_id, const char* display_name,
enum deserv_t display_server);
int init_env(pam_handle_t* pam_handle, struct passwd* pw);
void reset_terminal(struct passwd* pwd);
int get_free_display(void);

#endif /* _LOGIN_H_ */
