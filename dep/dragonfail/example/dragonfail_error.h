#ifndef H_DRAGONFAIL_ERROR
#define H_DRAGONFAIL_ERROR

enum dgn_error
{
	DGN_OK, // do not remove

	DGN_NULL,
	DGN_ALLOC,
	DGN_BOUNDS,
	DGN_DOMAIN,

	DGN_SIZE, // do not remove
};

//#define DRAGONFAIL_SKIP
#define DRAGONFAIL_BASIC_LOG
#define DRAGONFAIL_THROW_BASIC_LOG
#define DRAGONFAIL_THROW_DEBUG_LOG
//#define DRAGONFAIL_ABORT

#endif
