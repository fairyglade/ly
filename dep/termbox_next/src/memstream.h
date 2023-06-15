#ifndef H_MEMSTREAM
#define H_MEMSTREAM

#include <stddef.h>
#include <stdio.h>

struct memstream
{
	size_t  pos;
	size_t capa;
	int file;
	unsigned char* data;
};

void memstream_init(struct memstream* s, int fd, void* buffer, size_t len);
void memstream_flush(struct memstream* s);
void memstream_write(struct memstream* s, void* source, size_t len);
void memstream_puts(struct memstream* s, const char* str);

#endif
