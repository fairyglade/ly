# Dragonfail
Dragonfail is a simple library providing basic error handling functionnalities.
It was designed to be as lightweight as possible, and can be completely disabled
with only one `#define` (more on that later).

Dragonfail was designed to be fast and uses inline functions exclusively. These
calls modify a global context which is not directly accessible by the programmer.

All the error codes must be written in an enum in **your** `dragonfail_error.h` file.
Because of this rather unusual architecture, the file must be found by the compiler
when it is processing `dragonfail.c` (in addition to your own source code of course).

## Testing
Run `make` to compile an example, and `make run` to execute it.

## Defines
This header can also contain some `#define` to modify dragonfail's behaviour:
 - `DRAGONFAIL_SKIP` completely disables the whole library, making it completely
   disappear from the binary (unless your compiler is a massive douche).
 - `DRAGONFAIL_BASIC_LOG` enables the `dgn_basic_log()` function calls
 - `DRAGONFAIL_THROW_BASIC_LOG` makes `dgn_throw()` call `dgn_basic_log()` automatically
 - `DRAGONFAIL_THROW_DEBUG_LOG` also prints the file and line in which
   `dgn_throw()` is called (you don't even need to compile with symbols
   because this is achieved the smart way using simple C99 macros)
 - `DRAGONFAIL_ABORT` makes `dgn_throw()` call `abort()`

Again, these `#define` must be placed in **your** `dragonfail_error.h` file.

## Using
### TL;DR
see the `example` folder :)

### Documentation
```
char** dgn_init();
```
This intializes the context to `DGN_OK` (no error) and returns the array of strings
you can fill with log messages corresponding to the errors you added in the enum.

```
void dgn_reset();
```
This resets the context to `DGN_OK`.

```
void dgn_basic_log();
```
This prints the message corresponding to the current error to stderr.

```
void dgn_throw(enum dgn_error new_code);
```
This sets the error to the given code.

```
char dgn_catch();
```
This returns true if the context currently holds an error

## Why is the architecture so strange?
The dragonfail context is global (extern) but really *implemented* in `dragonfail.c`.
Its type depends on the size of the enum so it is *declared* in `dragonfail_private.h`:
this way we can include the user's `dragonfail_error.h` and get `DGN_SIZE`.

The inline functions need to access this context and **we want it private**, so we can't
*implement* them directly in the header as a lot of people seem to appreciate. Instead,
we will *declare* them here, and put the *implementations* in `dragonfail.c`: this way
we can access the global context without including its declaration, because it is
implemented here as well.

When you include `dragonfail.h`, you get access to the inline functions declarations
and thanks to this design any compiler will do the rest of the job automatically. Yes,
this whole thing is useless and over-engineered. And yes, I had fun doing it...

## Greetings
Jinjer for the cool music \m/
Haiku developers for indirectly giving me the idea
