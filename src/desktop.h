#ifndef _DESKTOP_H_
#define _DESKTOP_H_

enum deserv_t {shell, xorg, xinitrc, wayland};

struct deprops_t
{
	char* cmd;
	enum deserv_t type;
};

struct delist_t
{
	char** names;
	struct deprops_t* props;
	int count;
};

struct delist_t* init_list(int count);
void end_list(struct delist_t* list, int count);
void get_props(FILE* file, char** name, char** command);
struct delist_t* list_de(void);
void free_list(struct delist_t* list);

#endif /* _DESKTOP_H_ */
