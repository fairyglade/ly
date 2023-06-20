# Configator
Configator is a lightweight library for ini config file parsing.
This was created to make it easy following the "DRY" coding rule
without using macros, and with flexibility in mind.

It integrates very well with the [Argoat](https://github.com/nullgemm/argoat.git)
arguments parser library, by using the same function pointers format.
This way, you can easily load settings from an ini file while overloading them
with command-line arguments if needed: the handling functions will be the same.

Configator does not use any macro or dynamic memory allocation,
and was built in less than 350 lines of C99 code.

## Testing
Run `make` to compile an example executable and perform basic testing

## Using
### TL;DR
Please see `example.c` for the condensed version
(or better, read the actual documentation below).
It is a bit too long to be copied here twice...

### Details
Include `argoat.h` and compile `argoat.c` with your code.

Write the functions that will handle your parameters.
They will be called during the parsing process, in the order given by the user
```
void handle_config_u8(void* data, char** value, const int pars_count)
{
	if (pars_count > 0)
	{
		*((uint8_t*) data) = atoi(*value);
	}
}
```

In your `main`, declare the variables to configure.
They will be passed to the corresponding functions as `void* data`
```
	uint8_t answer = 0;
```

Declare the arrays of parameters by section, starting with the general section.
If you don't want to handle parameters in some section, just declare it `NULL`.
```
struct configator_param* map_no_section = NULL;
```

Declare real sections parameters afterwards
```
struct configator_param map_test_section[] =
{
	{"ping", &answer, handle_config_u8},
	{"pong", &answer, handle_config_u8},
};
```

Then group them in the map
```
struct configator_param* map[] =
{
	map_no_section,
	map_test_section
};
```

And declare the sections array. Configator will execute the pointed function
with `NULL` arguments at the beginning of each detected section.
You can also declare sections with `NULL` parameters, in which case nothing
will be executed.
```
struct configator_param sections[] =
{
	{"network_test", &answer, handle_config_u8},
};
```

Don't forget to put the right numbers in the lenght variables
```
uint16_t map_len[] = {0, 2};
uint16_t sections_len = 1;
```

Then initialize and use configator
```
struct configator config;
config.map = map;
config.map_len = map_len;
config.sections = sections;
config.sections_len = sections_len;

configator(&config, "config.ini");
printf("answer = %d\n", answer);
```
