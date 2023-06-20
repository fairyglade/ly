#ifndef H_RINGBUFFER
#define H_RINGBUFFER

#include <stddef.h>

#define ERINGBUFFER_ALLOC_FAIL -1

struct ringbuffer
{
	char* buf;
	size_t size;

	char* begin;
	char* end;
};

int init_ringbuffer(struct ringbuffer* r, size_t size);
void free_ringbuffer(struct ringbuffer* r);
void clear_ringbuffer(struct ringbuffer* r);
size_t ringbuffer_free_space(struct ringbuffer* r);
size_t ringbuffer_data_size(struct ringbuffer* r);
void ringbuffer_push(struct ringbuffer* r, const void* data, size_t size);
void ringbuffer_pop(struct ringbuffer* r, void* data, size_t size);
void ringbuffer_read(struct ringbuffer* r, void* data, size_t size);

#endif
