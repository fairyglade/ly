#ifndef H_ARGOAT
#define H_ARGOAT

// flag-processor
struct argoat_sprig
{
	// dash-prefixed option
	const char* flag;
	// maximum pars
	const int pars_max;
	// pre-loaded data for the function
	void* data;
	// function executed upon detection
	void (* const func)(void* data, char** pars, const int pars_count);
};

// main structure
struct argoat
{
	// the flags-processor list, with handling functions etc.
	const struct argoat_sprig* sprigs;
	// size of the list above
	const int sprigs_count;
	// unflagged tags buffer
	char** unflagged;
	int unflagged_count;
	int unflagged_max;
};

void argoat_unflagged_sacrifice(const struct argoat* args);
int argoat_increment_pars(struct argoat* args, char* flag, char* pars);
void argoat_sacrifice(struct argoat* args, char* flag, char** pars, int pars_count);
void argoat_compound(struct argoat* args, char** pars);
void argoat_graze(struct argoat* args, int argc, char** argv);

#endif
