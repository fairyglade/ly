/*
MIT License

Copyright (c) 2010-2020 nsf <no.smile.face@gmail.com>
              2015-2025 Adam Saponara <as@php.net>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

#ifndef TERMBOX_H_INCL
#define TERMBOX_H_INCL

#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE
#endif

#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE
#endif

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <termios.h>
#include <unistd.h>
#include <wchar.h>
#include <wctype.h>

#ifdef PATH_MAX
#define TB_PATH_MAX PATH_MAX
#else
#define TB_PATH_MAX 4096
#endif

#ifdef __cplusplus
extern "C" {
#endif

// __ffi_start

#define TB_VERSION_STR "2.6.0-dev"

/* The following compile-time options are supported:
 *
 *     TB_OPT_ATTR_W: Integer width of `fg` and `bg` attributes. Valid values
 *                    (assuming system support) are 16, 32, and 64. (See
 *                    `uintattr_t`). 32 or 64 enables output mode
 *                    `TB_OUTPUT_TRUECOLOR`. 64 enables additional style
 *                    attributes. (See `tb_set_output_mode`.) Larger values
 *                    consume more memory in exchange for more features.
 *                    Defaults to 16.
 *
 *        TB_OPT_EGC: If set, enable extended grapheme cluster support
 *                    (`tb_extend_cell`, `tb_set_cell_ex`). Consumes more
 *                    memory. Defaults off.
 *
 * TB_OPT_PRINTF_BUF: Write buffer size for printf operations. Represents the
 *                    largest string that can be sent in one call to
 *                    `tb_print*` and `tb_send*` functions. Defaults to 4096.
 *
 *   TB_OPT_READ_BUF: Read buffer size for tty reads. Defaults to 64.
 *
 * TB_OPT_LIBC_WCHAR: If set, use libc's `wcwidth(3)`, `iswprint(3)`, etc
 *                    instead of the built-in Unicode-aware versions. Note,
 *                    libc's are locale-dependent and the caller must
 *                    `setlocale(3)` `LC_CTYPE` to UTF-8. Defaults to built-in.
 *
 *  TB_OPT_TRUECOLOR: Deprecated. Sets TB_OPT_ATTR_W to 32 if not already set.
 */

#if defined(TB_LIB_OPTS) || 0 // __tb_lib_opts
/* Ensure consistent compile-time options when using as a shared library */
#undef TB_OPT_ATTR_W
#undef TB_OPT_EGC
#undef TB_OPT_PRINTF_BUF
#undef TB_OPT_READ_BUF
#undef TB_OPT_LIBC_WCHAR
#define TB_OPT_ATTR_W 64
#define TB_OPT_EGC
#endif

/* Ensure sane `TB_OPT_ATTR_W` (16, 32, or 64) */
#if defined TB_OPT_ATTR_W && TB_OPT_ATTR_W == 16
#elif defined TB_OPT_ATTR_W && TB_OPT_ATTR_W == 32
#elif defined TB_OPT_ATTR_W && TB_OPT_ATTR_W == 64
#else
#undef TB_OPT_ATTR_W
#if defined TB_OPT_TRUECOLOR // Deprecated. Back-compat for old flag.
#define TB_OPT_ATTR_W 32
#else
#define TB_OPT_ATTR_W 16
#endif
#endif

/* ASCII key constants (`tb_event.key`) */
#define TB_KEY_CTRL_TILDE       0x00
#define TB_KEY_CTRL_2           0x00 // clash with `CTRL_TILDE`
#define TB_KEY_CTRL_A           0x01
#define TB_KEY_CTRL_B           0x02
#define TB_KEY_CTRL_C           0x03
#define TB_KEY_CTRL_D           0x04
#define TB_KEY_CTRL_E           0x05
#define TB_KEY_CTRL_F           0x06
#define TB_KEY_CTRL_G           0x07
#define TB_KEY_BACKSPACE        0x08
#define TB_KEY_CTRL_H           0x08 // clash with `CTRL_BACKSPACE`
#define TB_KEY_TAB              0x09
#define TB_KEY_CTRL_I           0x09 // clash with `TAB`
#define TB_KEY_CTRL_J           0x0a
#define TB_KEY_CTRL_K           0x0b
#define TB_KEY_CTRL_L           0x0c
#define TB_KEY_ENTER            0x0d
#define TB_KEY_CTRL_M           0x0d // clash with `ENTER`
#define TB_KEY_CTRL_N           0x0e
#define TB_KEY_CTRL_O           0x0f
#define TB_KEY_CTRL_P           0x10
#define TB_KEY_CTRL_Q           0x11
#define TB_KEY_CTRL_R           0x12
#define TB_KEY_CTRL_S           0x13
#define TB_KEY_CTRL_T           0x14
#define TB_KEY_CTRL_U           0x15
#define TB_KEY_CTRL_V           0x16
#define TB_KEY_CTRL_W           0x17
#define TB_KEY_CTRL_X           0x18
#define TB_KEY_CTRL_Y           0x19
#define TB_KEY_CTRL_Z           0x1a
#define TB_KEY_ESC              0x1b
#define TB_KEY_CTRL_LSQ_BRACKET 0x1b // clash with 'ESC'
#define TB_KEY_CTRL_3           0x1b // clash with 'ESC'
#define TB_KEY_CTRL_4           0x1c
#define TB_KEY_CTRL_BACKSLASH   0x1c // clash with 'CTRL_4'
#define TB_KEY_CTRL_5           0x1d
#define TB_KEY_CTRL_RSQ_BRACKET 0x1d // clash with 'CTRL_5'
#define TB_KEY_CTRL_6           0x1e
#define TB_KEY_CTRL_7           0x1f
#define TB_KEY_CTRL_SLASH       0x1f // clash with 'CTRL_7'
#define TB_KEY_CTRL_UNDERSCORE  0x1f // clash with 'CTRL_7'
#define TB_KEY_SPACE            0x20
#define TB_KEY_BACKSPACE2       0x7f
#define TB_KEY_CTRL_8           0x7f // clash with 'BACKSPACE2'

#define tb_key_i(i)             0xffff - (i)
/* Terminal-dependent key constants (`tb_event.key`) and terminfo caps */
/* BEGIN codegen h */
/* Produced by ./codegen.sh on Tue, 03 Sep 2024 04:17:47 +0000 */
#define TB_KEY_F1               (0xffff - 0)
#define TB_KEY_F2               (0xffff - 1)
#define TB_KEY_F3               (0xffff - 2)
#define TB_KEY_F4               (0xffff - 3)
#define TB_KEY_F5               (0xffff - 4)
#define TB_KEY_F6               (0xffff - 5)
#define TB_KEY_F7               (0xffff - 6)
#define TB_KEY_F8               (0xffff - 7)
#define TB_KEY_F9               (0xffff - 8)
#define TB_KEY_F10              (0xffff - 9)
#define TB_KEY_F11              (0xffff - 10)
#define TB_KEY_F12              (0xffff - 11)
#define TB_KEY_INSERT           (0xffff - 12)
#define TB_KEY_DELETE           (0xffff - 13)
#define TB_KEY_HOME             (0xffff - 14)
#define TB_KEY_END              (0xffff - 15)
#define TB_KEY_PGUP             (0xffff - 16)
#define TB_KEY_PGDN             (0xffff - 17)
#define TB_KEY_ARROW_UP         (0xffff - 18)
#define TB_KEY_ARROW_DOWN       (0xffff - 19)
#define TB_KEY_ARROW_LEFT       (0xffff - 20)
#define TB_KEY_ARROW_RIGHT      (0xffff - 21)
#define TB_KEY_BACK_TAB         (0xffff - 22)
#define TB_KEY_MOUSE_LEFT       (0xffff - 23)
#define TB_KEY_MOUSE_RIGHT      (0xffff - 24)
#define TB_KEY_MOUSE_MIDDLE     (0xffff - 25)
#define TB_KEY_MOUSE_RELEASE    (0xffff - 26)
#define TB_KEY_MOUSE_WHEEL_UP   (0xffff - 27)
#define TB_KEY_MOUSE_WHEEL_DOWN (0xffff - 28)

#define TB_CAP_F1               0
#define TB_CAP_F2               1
#define TB_CAP_F3               2
#define TB_CAP_F4               3
#define TB_CAP_F5               4
#define TB_CAP_F6               5
#define TB_CAP_F7               6
#define TB_CAP_F8               7
#define TB_CAP_F9               8
#define TB_CAP_F10              9
#define TB_CAP_F11              10
#define TB_CAP_F12              11
#define TB_CAP_INSERT           12
#define TB_CAP_DELETE           13
#define TB_CAP_HOME             14
#define TB_CAP_END              15
#define TB_CAP_PGUP             16
#define TB_CAP_PGDN             17
#define TB_CAP_ARROW_UP         18
#define TB_CAP_ARROW_DOWN       19
#define TB_CAP_ARROW_LEFT       20
#define TB_CAP_ARROW_RIGHT      21
#define TB_CAP_BACK_TAB         22
#define TB_CAP__COUNT_KEYS      23
#define TB_CAP_ENTER_CA         23
#define TB_CAP_EXIT_CA          24
#define TB_CAP_SHOW_CURSOR      25
#define TB_CAP_HIDE_CURSOR      26
#define TB_CAP_CLEAR_SCREEN     27
#define TB_CAP_SGR0             28
#define TB_CAP_UNDERLINE        29
#define TB_CAP_BOLD             30
#define TB_CAP_BLINK            31
#define TB_CAP_ITALIC           32
#define TB_CAP_REVERSE          33
#define TB_CAP_ENTER_KEYPAD     34
#define TB_CAP_EXIT_KEYPAD      35
#define TB_CAP_DIM              36
#define TB_CAP_INVISIBLE        37
#define TB_CAP__COUNT           38
/* END codegen h */

/* Some hard-coded caps */
#define TB_HARDCAP_ENTER_MOUSE  "\x1b[?1000h\x1b[?1002h\x1b[?1015h\x1b[?1006h"
#define TB_HARDCAP_EXIT_MOUSE   "\x1b[?1006l\x1b[?1015l\x1b[?1002l\x1b[?1000l"
#define TB_HARDCAP_STRIKEOUT    "\x1b[9m"
#define TB_HARDCAP_UNDERLINE_2  "\x1b[21m"
#define TB_HARDCAP_OVERLINE     "\x1b[53m"

/* Colors (numeric) and attributes (bitwise) (`tb_cell.fg`, `tb_cell.bg`) */
#define TB_DEFAULT              0x0000
#define TB_BLACK                0x0001
#define TB_RED                  0x0002
#define TB_GREEN                0x0003
#define TB_YELLOW               0x0004
#define TB_BLUE                 0x0005
#define TB_MAGENTA              0x0006
#define TB_CYAN                 0x0007
#define TB_WHITE                0x0008

#if TB_OPT_ATTR_W == 16
#define TB_BOLD      0x0100
#define TB_UNDERLINE 0x0200
#define TB_REVERSE   0x0400
#define TB_ITALIC    0x0800
#define TB_BLINK     0x1000
#define TB_HI_BLACK  0x2000
#define TB_BRIGHT    0x4000
#define TB_DIM       0x8000
#define TB_256_BLACK TB_HI_BLACK // `TB_256_BLACK` is deprecated
#else
// `TB_OPT_ATTR_W` is 32 or 64
#define TB_BOLD                0x01000000
#define TB_UNDERLINE           0x02000000
#define TB_REVERSE             0x04000000
#define TB_ITALIC              0x08000000
#define TB_BLINK               0x10000000
#define TB_HI_BLACK            0x20000000
#define TB_BRIGHT              0x40000000
#define TB_DIM                 0x80000000
#define TB_TRUECOLOR_BOLD      TB_BOLD // `TB_TRUECOLOR_*` is deprecated
#define TB_TRUECOLOR_UNDERLINE TB_UNDERLINE
#define TB_TRUECOLOR_REVERSE   TB_REVERSE
#define TB_TRUECOLOR_ITALIC    TB_ITALIC
#define TB_TRUECOLOR_BLINK     TB_BLINK
#define TB_TRUECOLOR_BLACK     TB_HI_BLACK
#endif

#if TB_OPT_ATTR_W == 64
#define TB_STRIKEOUT   0x0000000100000000
#define TB_UNDERLINE_2 0x0000000200000000
#define TB_OVERLINE    0x0000000400000000
#define TB_INVISIBLE   0x0000000800000000
#endif

/* Event types (`tb_event.type`) */
#define TB_EVENT_KEY        1
#define TB_EVENT_RESIZE     2
#define TB_EVENT_MOUSE      3

/* Key modifiers (bitwise) (`tb_event.mod`) */
#define TB_MOD_ALT          1
#define TB_MOD_CTRL         2
#define TB_MOD_SHIFT        4
#define TB_MOD_MOTION       8

/* Input modes (bitwise) (`tb_set_input_mode`) */
#define TB_INPUT_CURRENT    0
#define TB_INPUT_ESC        1
#define TB_INPUT_ALT        2
#define TB_INPUT_MOUSE      4

/* Output modes (`tb_set_output_mode`) */
#define TB_OUTPUT_CURRENT   0
#define TB_OUTPUT_NORMAL    1
#define TB_OUTPUT_256       2
#define TB_OUTPUT_216       3
#define TB_OUTPUT_GRAYSCALE 4
#if TB_OPT_ATTR_W >= 32
#define TB_OUTPUT_TRUECOLOR 5
#endif

/* Common function return values unless otherwise noted.
 *
 * Library behavior is undefined after receiving `TB_ERR_MEM`. Callers may
 * attempt reinitializing by freeing memory, invoking `tb_shutdown`, then
 * `tb_init`.
 */
#define TB_OK                   0
#define TB_ERR                  -1
#define TB_ERR_NEED_MORE        -2
#define TB_ERR_INIT_ALREADY     -3
#define TB_ERR_INIT_OPEN        -4
#define TB_ERR_MEM              -5
#define TB_ERR_NO_EVENT         -6
#define TB_ERR_NO_TERM          -7
#define TB_ERR_NOT_INIT         -8
#define TB_ERR_OUT_OF_BOUNDS    -9
#define TB_ERR_READ             -10
#define TB_ERR_RESIZE_IOCTL     -11
#define TB_ERR_RESIZE_PIPE      -12
#define TB_ERR_RESIZE_SIGACTION -13
#define TB_ERR_POLL             -14
#define TB_ERR_TCGETATTR        -15
#define TB_ERR_TCSETATTR        -16
#define TB_ERR_UNSUPPORTED_TERM -17
#define TB_ERR_RESIZE_WRITE     -18
#define TB_ERR_RESIZE_POLL      -19
#define TB_ERR_RESIZE_READ      -20
#define TB_ERR_RESIZE_SSCANF    -21
#define TB_ERR_CAP_COLLISION    -22

#define TB_ERR_SELECT           TB_ERR_POLL
#define TB_ERR_RESIZE_SELECT    TB_ERR_RESIZE_POLL

/* Deprecated. Function types to be used with `tb_set_func`. */
#define TB_FUNC_EXTRACT_PRE     0
#define TB_FUNC_EXTRACT_POST    1

/* Define this to set the size of the buffer used in `tb_printf`
 * and `tb_sendf`
 */
#ifndef TB_OPT_PRINTF_BUF
#define TB_OPT_PRINTF_BUF 4096
#endif

/* Define this to set the size of the read buffer used when reading
 * from the tty
 */
#ifndef TB_OPT_READ_BUF
#define TB_OPT_READ_BUF 64
#endif

/* Define this for limited back compat with termbox v1 */
#ifdef TB_OPT_V1_COMPAT
#define tb_change_cell          tb_set_cell
#define tb_put_cell(x, y, c)    tb_set_cell((x), (y), (c)->ch, (c)->fg, (c)->bg)
#define tb_set_clear_attributes tb_set_clear_attrs
#define tb_select_input_mode    tb_set_input_mode
#define tb_select_output_mode   tb_set_output_mode
#endif

/* Define these to swap in a different allocator */
#ifndef tb_malloc
#define tb_malloc  malloc
#define tb_realloc realloc
#define tb_free    free
#endif

#if TB_OPT_ATTR_W == 64
typedef uint64_t uintattr_t;
#elif TB_OPT_ATTR_W == 32
typedef uint32_t uintattr_t;
#else // 16
typedef uint16_t uintattr_t;
#endif

/* A cell in a 2d grid representing the terminal screen.
 *
 * The terminal screen is represented as 2d array of cells. The structure is
 * optimized for dealing with single-width (`wcwidth==1`) Unicode codepoints,
 * however some support for grapheme clusters (e.g., combining diacritical
 * marks) and wide codepoints (e.g., Hiragana) is provided through `ech`,
 * `nech`, and `cech` via `tb_set_cell_ex`. `ech` is only valid when `nech>0`,
 * otherwise `ch` is used.
 *
 * For non-single-width codepoints, given `N=wcwidth(ch)/wcswidth(ech)`:
 *
 * when `N==0`: termbox forces a single-width cell. Callers should avoid this
 *              if aiming to render text accurately. Callers may use
 *              `tb_set_cell_ex` or `tb_print*` to render `N==0` combining
 *              characters.
 *
 *  when `N>1`: termbox zeroes out the following `N-1` cells and skips sending
 *              them to the tty. So, e.g., if the caller sets `x=0,y=0` to an
 *              `N==2` codepoint, the caller's next set should be at `x=2,y=0`.
 *              Anything set at `x=1,y=0` will be ignored. If there are not
 *              enough columns remaining on the line to render `N` width, spaces
 *              are sent instead.
 *
 * See `tb_present` for implementation.
 */
struct tb_cell {
    uint32_t ch;   // a Unicode codepoint
    uintattr_t fg; // bitwise foreground attributes
    uintattr_t bg; // bitwise background attributes
#ifdef TB_OPT_EGC
    uint32_t *ech; // a grapheme cluster of Unicode codepoints, 0-terminated
    size_t nech;   // num elements in ech, 0 means use ch instead of ech
    size_t cech;   // num elements allocated for ech
#endif
};

/* An incoming event from the tty.
 *
 * Given the event type, the following fields are relevant:
 *
 *    when `TB_EVENT_KEY`: `key` xor `ch` (one will be zero) and `mod`. Note
 *                         there is overlap between `TB_MOD_CTRL` and
 *                         `TB_KEY_CTRL_*`. `TB_MOD_CTRL` and `TB_MOD_SHIFT` are
 *                         only set as modifiers to `TB_KEY_ARROW_*`.
 *
 * when `TB_EVENT_RESIZE`: `w` and `h`
 *
 *  when `TB_EVENT_MOUSE`: `key` (`TB_KEY_MOUSE_*`), `x`, and `y`
 */
struct tb_event {
    uint8_t type; // one of `TB_EVENT_*` constants
    uint8_t mod;  // bitwise `TB_MOD_*` constants
    uint16_t key; // one of `TB_KEY_*` constants
    uint32_t ch;  // a Unicode codepoint
    int32_t w;    // resize width
    int32_t h;    // resize height
    int32_t x;    // mouse x
    int32_t y;    // mouse y
};

/* Initialize the termbox library. This function should be called before any
 * other functions. `tb_init` is equivalent to `tb_init_file("/dev/tty")`. After
 * successful initialization, the library must be finalized using `tb_shutdown`.
 */
int tb_init(void);
int tb_init_file(const char *path);
int tb_init_fd(int ttyfd);
int tb_init_rwfd(int rfd, int wfd);
int tb_shutdown(void);

/* Return the size of the internal back buffer (which is the same as terminal's
 * window size in rows and columns). The internal buffer can be resized after
 * `tb_clear` or `tb_present` calls. Both dimensions have an unspecified
 * negative value when called before `tb_init` or after `tb_shutdown`.
 */
int tb_width(void);
int tb_height(void);

/* Clear the internal back buffer using `TB_DEFAULT` or the attributes set by
 * `tb_set_clear_attrs`.
 */
int tb_clear(void);
int tb_set_clear_attrs(uintattr_t fg, uintattr_t bg);

/* Synchronize the internal back buffer with the terminal by writing to tty. */
int tb_present(void);

/* Clear the internal front buffer effectively forcing a complete re-render of
 * the back buffer to the tty. It is not necessary to call this under normal
 * circumstances.
 */
int tb_invalidate(void);

/* Set the position of the cursor. Upper-left cell is (0, 0). */
int tb_set_cursor(int cx, int cy);
int tb_hide_cursor(void);

/* Set cell contents in the internal back buffer at the specified position.
 *
 * Use `tb_set_cell_ex` for rendering grapheme clusters (e.g., combining
 * diacritical marks).
 *
 * Calling `tb_set_cell(x, y, ch, fg, bg)` is equivalent to
 * `tb_set_cell_ex(x, y, &ch, 1, fg, bg)`.
 *
 * `tb_extend_cell` is a shortcut for appending 1 codepoint to `tb_cell.ech`.
 *
 * Non-printable (`iswprint(3)`) codepoints are replaced with `U+FFFD` at render
 * time.
 */
int tb_set_cell(int x, int y, uint32_t ch, uintattr_t fg, uintattr_t bg);
int tb_set_cell_ex(int x, int y, uint32_t *ch, size_t nch, uintattr_t fg,
    uintattr_t bg);
int tb_extend_cell(int x, int y, uint32_t ch);

/* Get cell at specified position.
 *
 * If position is valid, function returns TB_OK and cell contents are copied to
 * `cell`. Note if `nech>0`, then `ech` will be a pointer to memory which may
 * be invalid or freed after subsequent library calls. Callers must copy this
 * memory if they need to persist it for some reason. Modifying memory at `ech`
 * results in undefined behavior.
 *
 * If `back` is non-zero, return cells from the internal back buffer. Otherwise,
 * return cells from the front buffer. Note the front buffer is updated on each
 * call to tb_present(), whereas the back buffer is updated immediately by
 * tb_set_cell() and other functions that mutate cell contents.
 */
int tb_get_cell(int x, int y, int back, struct tb_cell *cell);

/* Set the input mode. Termbox has two input modes:
 *
 * 1. `TB_INPUT_ESC`
 *    When escape (`\x1b`) is in the buffer and there's no match for an escape
 *    sequence, a key event for `TB_KEY_ESC` is returned.
 *
 * 2. `TB_INPUT_ALT`
 *    When escape (`\x1b`) is in the buffer and there's no match for an escape
 *    sequence, the next keyboard event is returned with a `TB_MOD_ALT`
 *    modifier.
 *
 * You can also apply `TB_INPUT_MOUSE` via bitwise OR operation to either of the
 * modes (e.g., `TB_INPUT_ESC | TB_INPUT_MOUSE`) to receive `TB_EVENT_MOUSE`
 * events. If none of the main two modes were set, but the mouse mode was,
 * `TB_INPUT_ESC` is used. If for some reason you've decided to use
 * `TB_INPUT_ESC | TB_INPUT_ALT`, it will behave as if only `TB_INPUT_ESC` was
 * selected.
 *
 * If mode is `TB_INPUT_CURRENT`, return the current input mode.
 *
 * The default input mode is `TB_INPUT_ESC`.
 */
int tb_set_input_mode(int mode);

/* Set the output mode. Termbox has multiple output modes:
 *
 * 1. `TB_OUTPUT_NORMAL`     => [0..8]
 *
 *    This mode provides 8 different colors:
 *      `TB_BLACK`, `TB_RED`, `TB_GREEN`, `TB_YELLOW`,
 *      `TB_BLUE`, `TB_MAGENTA`, `TB_CYAN`, `TB_WHITE`
 *
 *    Plus `TB_DEFAULT` which skips sending a color code (i.e., uses the
 *    terminal's default color).
 *
 *    Colors (including `TB_DEFAULT`) may be bitwise OR'd with attributes:
 *      `TB_BOLD`, `TB_UNDERLINE`, `TB_REVERSE`, `TB_ITALIC`, `TB_BLINK`,
 *      `TB_BRIGHT`, `TB_DIM`
 *
 *    The following style attributes are also available if compiled with
 *    `TB_OPT_ATTR_W` set to 64:
 *      `TB_STRIKEOUT`, `TB_UNDERLINE_2`, `TB_OVERLINE`, `TB_INVISIBLE`
 *
 *    As in all modes, the value 0 is interpreted as `TB_DEFAULT` for
 *    convenience.
 *
 *    Some notes: `TB_REVERSE` and `TB_BRIGHT` can be applied as either `fg` or
 *    `bg` attributes for the same effect. The rest of the attributes apply to
 *    `fg` only and are ignored as `bg` attributes.
 *
 *    Example usage: `tb_set_cell(x, y, '@', TB_BLACK | TB_BOLD, TB_RED)`
 *
 * 2. `TB_OUTPUT_256`        => [0..255] + `TB_HI_BLACK`
 *
 *    In this mode you get 256 distinct colors (plus default):
 *                0x00   (1): `TB_DEFAULT`
 *       `TB_HI_BLACK`   (1): `TB_BLACK` in `TB_OUTPUT_NORMAL`
 *          0x01..0x07   (7): the next 7 colors as in `TB_OUTPUT_NORMAL`
 *          0x08..0x0f   (8): bright versions of the above
 *          0x10..0xe7 (216): 216 different colors
 *          0xe8..0xff  (24): 24 different shades of gray
 *
 *    All `TB_*` style attributes except `TB_BRIGHT` may be bitwise OR'd as in
 *    `TB_OUTPUT_NORMAL`.
 *
 *    Note `TB_HI_BLACK` must be used for black, as 0x00 represents default.
 *
 * 3. `TB_OUTPUT_216`        => [0..216]
 *
 *    This mode supports the 216-color range of `TB_OUTPUT_256` only, but you
 *    don't need to provide an offset:
 *                0x00   (1): `TB_DEFAULT`
 *          0x01..0xd8 (216): 216 different colors
 *
 * 4. `TB_OUTPUT_GRAYSCALE`  => [0..24]
 *
 *    This mode supports the 24-color range of `TB_OUTPUT_256` only, but you
 *    don't need to provide an offset:
 *                0x00   (1): `TB_DEFAULT`
 *          0x01..0x18  (24): 24 different shades of gray
 *
 * 5. `TB_OUTPUT_TRUECOLOR`  => [0x000000..0xffffff] + `TB_HI_BLACK`
 *
 *    This mode provides 24-bit color on supported terminals. The format is
 *    0xRRGGBB.
 *
 *    All `TB_*` style attributes except `TB_BRIGHT` may be bitwise OR'd as in
 *    `TB_OUTPUT_NORMAL`.
 *
 *    Note `TB_HI_BLACK` must be used for black, as 0x000000 represents default.
 *
 * To use the terminal default color (i.e., to not send an escape code), pass
 * `TB_DEFAULT`. For convenience, the value 0 is interpreted as `TB_DEFAULT` in
 * all modes.
 *
 * Note, cell attributes persist after switching output modes. Any translation
 * between, for example, `TB_OUTPUT_NORMAL`'s `TB_RED` and
 * `TB_OUTPUT_TRUECOLOR`'s 0xff0000 must be performed by the caller. Also note
 * that cells previously rendered in one mode may persist unchanged until the
 * front buffer is cleared (such as after a resize event) at which point it will
 * be re-interpreted and flushed according to the current mode. Callers may
 * invoke `tb_invalidate` if it is desirable to immediately re-interpret and
 * flush the entire screen according to the current mode.
 *
 * Note, not all terminals support all output modes, especially beyond
 * `TB_OUTPUT_NORMAL`. There is also no very reliable way to determine color
 * support dynamically. If portability is desired, callers are recommended to
 * use `TB_OUTPUT_NORMAL` or make output mode end-user configurable. The same
 * advice applies to style attributes.
 *
 * If mode is `TB_OUTPUT_CURRENT`, return the current output mode.
 *
 * The default output mode is `TB_OUTPUT_NORMAL`.
 */
int tb_set_output_mode(int mode);

/* Wait for an event up to `timeout_ms` milliseconds and populate `event` with
 * it. If no event is available within the timeout period, `TB_ERR_NO_EVENT`
 * is returned. On a resize event, the underlying `select(2)` call may be
 * interrupted, yielding a return code of `TB_ERR_POLL`. In this case, you may
 * check `errno` via `tb_last_errno`. If it's `EINTR`, you may elect to ignore
 * that and call `tb_peek_event` again.
 */
int tb_peek_event(struct tb_event *event, int timeout_ms);

/* Same as `tb_peek_event` except no timeout. */
int tb_poll_event(struct tb_event *event);

/* Internal termbox fds that can be used with `poll(2)`, `select(2)`, etc.
 * externally. Callers must invoke `tb_poll_event` or `tb_peek_event` if
 * fds become readable.
 */
int tb_get_fds(int *ttyfd, int *resizefd);

/* Print and printf functions. Specify param `out_w` to determine width of
 * printed string. Strings are interpreted as UTF-8.
 *
 * Non-printable characters (`iswprint(3)`) and truncated UTF-8 byte sequences
 * are replaced with U+FFFD.
 *
 * Newlines (`\n`) are supported with the caveat that `out_w` will return the
 * width of the string as if it were on a single line.
 *
 * If the starting coordinate is out of bounds, `TB_ERR_OUT_OF_BOUNDS` is
 * returned. If the starting coordinate is in bounds, but goes out of bounds,
 * then the out-of-bounds portions of the string are ignored.
 *
 * For finer control, use `tb_set_cell`.
 */
int tb_print(int x, int y, uintattr_t fg, uintattr_t bg, const char *str);
int tb_printf(int x, int y, uintattr_t fg, uintattr_t bg, const char *fmt, ...);
int tb_print_ex(int x, int y, uintattr_t fg, uintattr_t bg, size_t *out_w,
    const char *str);
int tb_printf_ex(int x, int y, uintattr_t fg, uintattr_t bg, size_t *out_w,
    const char *fmt, ...);

/* Send raw bytes to terminal. */
int tb_send(const char *buf, size_t nbuf);
int tb_sendf(const char *fmt, ...);

/* Deprecated. Set custom callbacks. `fn_type` is one of `TB_FUNC_*` constants,
 * `fn` is a compatible function pointer, or NULL to clear.
 *
 * `TB_FUNC_EXTRACT_PRE`:
 *   If specified, invoke this function BEFORE termbox tries to extract any
 *   escape sequences from the input buffer.
 *
 * `TB_FUNC_EXTRACT_POST`:
 *   If specified, invoke this function AFTER termbox tries (and fails) to
 *   extract any escape sequences from the input buffer.
 */
int tb_set_func(int fn_type, int (*fn)(struct tb_event *, size_t *));

/* Return byte length of codepoint given first byte of UTF-8 sequence (1-6). */
int tb_utf8_char_length(char c);

/* Convert UTF-8 null-terminated byte sequence to UTF-32 codepoint.
 *
 * If `c` is an empty C string, return 0. `out` is left unchanged.
 *
 * If a null byte is encountered in the middle of the codepoint, return a
 * negative number indicating how many bytes were processed. `out` is left
 * unchanged.
 *
 * Otherwise, return byte length of codepoint (1-6).
 */
int tb_utf8_char_to_unicode(uint32_t *out, const char *c);

/* Convert UTF-32 codepoint to UTF-8 null-terminated byte sequence.
 *
 * `out` must be char[7] or greater. Return byte length of codepoint (1-6).
 */
int tb_utf8_unicode_to_char(char *out, uint32_t c);

/* Library utility functions */
int tb_last_errno(void);
const char *tb_strerror(int err);
struct tb_cell *tb_cell_buffer(void); // Deprecated
int tb_has_truecolor(void);
int tb_has_egc(void);
int tb_attr_width(void);
const char *tb_version(void);
int tb_iswprint(uint32_t ch);
int tb_wcwidth(uint32_t ch);

/* Deprecation notice!
 *
 * The following will be removed in version 3.x (ABI version 3):
 *
 *   TB_256_BLACK           (use TB_HI_BLACK)
 *   TB_OPT_TRUECOLOR       (use TB_OPT_ATTR_W)
 *   TB_TRUECOLOR_BOLD      (use TB_BOLD)
 *   TB_TRUECOLOR_UNDERLINE (use TB_UNDERLINE)
 *   TB_TRUECOLOR_REVERSE   (use TB_REVERSE)
 *   TB_TRUECOLOR_ITALIC    (use TB_ITALIC)
 *   TB_TRUECOLOR_BLINK     (use TB_BLINK)
 *   TB_TRUECOLOR_BLACK     (use TB_HI_BLACK)
 *   tb_cell_buffer
 *   tb_set_func
 *   TB_FUNC_EXTRACT_PRE
 *   TB_FUNC_EXTRACT_POST
 */

#ifdef __cplusplus
}
#endif

#endif // TERMBOX_H_INCL

#ifdef TB_IMPL

#define if_err_return(rv, expr)                                                \
    if (((rv) = (expr)) != TB_OK) return (rv)
#define if_err_break(rv, expr)                                                 \
    if (((rv) = (expr)) != TB_OK) break
#define if_ok_return(rv, expr)                                                 \
    if (((rv) = (expr)) == TB_OK) return (rv)
#define if_ok_or_need_more_return(rv, expr)                                    \
    if (((rv) = (expr)) == TB_OK || (rv) == TB_ERR_NEED_MORE) return (rv)

#define send_literal(rv, a)                                                    \
    if_err_return((rv), bytebuf_nputs(&global.out, (a), sizeof(a) - 1))

#define send_num(rv, nbuf, n)                                                  \
    if_err_return((rv),                                                        \
        bytebuf_nputs(&global.out, (nbuf), convert_num((n), (nbuf))))

#define snprintf_or_return(rv, str, sz, fmt, ...)                              \
    do {                                                                       \
        (rv) = snprintf((str), (sz), (fmt), __VA_ARGS__);                      \
        if ((rv) < 0 || (rv) >= (int)(sz)) return TB_ERR;                      \
    } while (0)

#define if_not_init_return()                                                   \
    if (!global.initialized) return TB_ERR_NOT_INIT

struct bytebuf_t {
    char *buf;
    size_t len;
    size_t cap;
};

struct cellbuf_t {
    int width;
    int height;
    struct tb_cell *cells;
};

struct cap_trie_t {
    char c;
    struct cap_trie_t *children;
    size_t nchildren;
    int is_leaf;
    uint16_t key;
    uint8_t mod;
};

struct tb_global_t {
    int ttyfd;
    int rfd;
    int wfd;
    int ttyfd_open;
    int resize_pipefd[2];
    int width;
    int height;
    int cursor_x;
    int cursor_y;
    int last_x;
    int last_y;
    uintattr_t fg;
    uintattr_t bg;
    uintattr_t last_fg;
    uintattr_t last_bg;
    int input_mode;
    int output_mode;
    char *terminfo;
    size_t nterminfo;
    const char *caps[TB_CAP__COUNT];
    struct cap_trie_t cap_trie;
    struct bytebuf_t in;
    struct bytebuf_t out;
    struct cellbuf_t back;
    struct cellbuf_t front;
    struct termios orig_tios;
    int has_orig_tios;
    int last_errno;
    int initialized;
    int (*fn_extract_esc_pre)(struct tb_event *, size_t *);
    int (*fn_extract_esc_post)(struct tb_event *, size_t *);
    char errbuf[1024];
};

static struct tb_global_t global = {0};

/* BEGIN codegen c */
/* Produced by ./codegen.sh on Tue, 03 Sep 2024 04:17:48 +0000 */

static const int16_t terminfo_cap_indexes[] = {
    66,  // kf1 (TB_CAP_F1)
    68,  // kf2 (TB_CAP_F2)
    69,  // kf3 (TB_CAP_F3)
    70,  // kf4 (TB_CAP_F4)
    71,  // kf5 (TB_CAP_F5)
    72,  // kf6 (TB_CAP_F6)
    73,  // kf7 (TB_CAP_F7)
    74,  // kf8 (TB_CAP_F8)
    75,  // kf9 (TB_CAP_F9)
    67,  // kf10 (TB_CAP_F10)
    216, // kf11 (TB_CAP_F11)
    217, // kf12 (TB_CAP_F12)
    77,  // kich1 (TB_CAP_INSERT)
    59,  // kdch1 (TB_CAP_DELETE)
    76,  // khome (TB_CAP_HOME)
    164, // kend (TB_CAP_END)
    82,  // kpp (TB_CAP_PGUP)
    81,  // knp (TB_CAP_PGDN)
    87,  // kcuu1 (TB_CAP_ARROW_UP)
    61,  // kcud1 (TB_CAP_ARROW_DOWN)
    79,  // kcub1 (TB_CAP_ARROW_LEFT)
    83,  // kcuf1 (TB_CAP_ARROW_RIGHT)
    148, // kcbt (TB_CAP_BACK_TAB)
    28,  // smcup (TB_CAP_ENTER_CA)
    40,  // rmcup (TB_CAP_EXIT_CA)
    16,  // cnorm (TB_CAP_SHOW_CURSOR)
    13,  // civis (TB_CAP_HIDE_CURSOR)
    5,   // clear (TB_CAP_CLEAR_SCREEN)
    39,  // sgr0 (TB_CAP_SGR0)
    36,  // smul (TB_CAP_UNDERLINE)
    27,  // bold (TB_CAP_BOLD)
    26,  // blink (TB_CAP_BLINK)
    311, // sitm (TB_CAP_ITALIC)
    34,  // rev (TB_CAP_REVERSE)
    89,  // smkx (TB_CAP_ENTER_KEYPAD)
    88,  // rmkx (TB_CAP_EXIT_KEYPAD)
    30,  // dim (TB_CAP_DIM)
    32,  // invis (TB_CAP_INVISIBLE)
};

// xterm
static const char *xterm_caps[] = {
    "\033OP",                  // kf1 (TB_CAP_F1)
    "\033OQ",                  // kf2 (TB_CAP_F2)
    "\033OR",                  // kf3 (TB_CAP_F3)
    "\033OS",                  // kf4 (TB_CAP_F4)
    "\033[15~",                // kf5 (TB_CAP_F5)
    "\033[17~",                // kf6 (TB_CAP_F6)
    "\033[18~",                // kf7 (TB_CAP_F7)
    "\033[19~",                // kf8 (TB_CAP_F8)
    "\033[20~",                // kf9 (TB_CAP_F9)
    "\033[21~",                // kf10 (TB_CAP_F10)
    "\033[23~",                // kf11 (TB_CAP_F11)
    "\033[24~",                // kf12 (TB_CAP_F12)
    "\033[2~",                 // kich1 (TB_CAP_INSERT)
    "\033[3~",                 // kdch1 (TB_CAP_DELETE)
    "\033OH",                  // khome (TB_CAP_HOME)
    "\033OF",                  // kend (TB_CAP_END)
    "\033[5~",                 // kpp (TB_CAP_PGUP)
    "\033[6~",                 // knp (TB_CAP_PGDN)
    "\033OA",                  // kcuu1 (TB_CAP_ARROW_UP)
    "\033OB",                  // kcud1 (TB_CAP_ARROW_DOWN)
    "\033OD",                  // kcub1 (TB_CAP_ARROW_LEFT)
    "\033OC",                  // kcuf1 (TB_CAP_ARROW_RIGHT)
    "\033[Z",                  // kcbt (TB_CAP_BACK_TAB)
    "\033[?1049h\033[22;0;0t", // smcup (TB_CAP_ENTER_CA)
    "\033[?1049l\033[23;0;0t", // rmcup (TB_CAP_EXIT_CA)
    "\033[?12l\033[?25h",      // cnorm (TB_CAP_SHOW_CURSOR)
    "\033[?25l",               // civis (TB_CAP_HIDE_CURSOR)
    "\033[H\033[2J",           // clear (TB_CAP_CLEAR_SCREEN)
    "\033(B\033[m",            // sgr0 (TB_CAP_SGR0)
    "\033[4m",                 // smul (TB_CAP_UNDERLINE)
    "\033[1m",                 // bold (TB_CAP_BOLD)
    "\033[5m",                 // blink (TB_CAP_BLINK)
    "\033[3m",                 // sitm (TB_CAP_ITALIC)
    "\033[7m",                 // rev (TB_CAP_REVERSE)
    "\033[?1h\033=",           // smkx (TB_CAP_ENTER_KEYPAD)
    "\033[?1l\033>",           // rmkx (TB_CAP_EXIT_KEYPAD)
    "\033[2m",                 // dim (TB_CAP_DIM)
    "\033[8m",                 // invis (TB_CAP_INVISIBLE)
};

// linux
static const char *linux_caps[] = {
    "\033[[A",           // kf1 (TB_CAP_F1)
    "\033[[B",           // kf2 (TB_CAP_F2)
    "\033[[C",           // kf3 (TB_CAP_F3)
    "\033[[D",           // kf4 (TB_CAP_F4)
    "\033[[E",           // kf5 (TB_CAP_F5)
    "\033[17~",          // kf6 (TB_CAP_F6)
    "\033[18~",          // kf7 (TB_CAP_F7)
    "\033[19~",          // kf8 (TB_CAP_F8)
    "\033[20~",          // kf9 (TB_CAP_F9)
    "\033[21~",          // kf10 (TB_CAP_F10)
    "\033[23~",          // kf11 (TB_CAP_F11)
    "\033[24~",          // kf12 (TB_CAP_F12)
    "\033[2~",           // kich1 (TB_CAP_INSERT)
    "\033[3~",           // kdch1 (TB_CAP_DELETE)
    "\033[1~",           // khome (TB_CAP_HOME)
    "\033[4~",           // kend (TB_CAP_END)
    "\033[5~",           // kpp (TB_CAP_PGUP)
    "\033[6~",           // knp (TB_CAP_PGDN)
    "\033[A",            // kcuu1 (TB_CAP_ARROW_UP)
    "\033[B",            // kcud1 (TB_CAP_ARROW_DOWN)
    "\033[D",            // kcub1 (TB_CAP_ARROW_LEFT)
    "\033[C",            // kcuf1 (TB_CAP_ARROW_RIGHT)
    "\033\011",          // kcbt (TB_CAP_BACK_TAB)
    "",                  // smcup (TB_CAP_ENTER_CA)
    "",                  // rmcup (TB_CAP_EXIT_CA)
    "\033[?25h\033[?0c", // cnorm (TB_CAP_SHOW_CURSOR)
    "\033[?25l\033[?1c", // civis (TB_CAP_HIDE_CURSOR)
    "\033[H\033[J",      // clear (TB_CAP_CLEAR_SCREEN)
    "\033[m\017",        // sgr0 (TB_CAP_SGR0)
    "\033[4m",           // smul (TB_CAP_UNDERLINE)
    "\033[1m",           // bold (TB_CAP_BOLD)
    "\033[5m",           // blink (TB_CAP_BLINK)
    "",                  // sitm (TB_CAP_ITALIC)
    "\033[7m",           // rev (TB_CAP_REVERSE)
    "",                  // smkx (TB_CAP_ENTER_KEYPAD)
    "",                  // rmkx (TB_CAP_EXIT_KEYPAD)
    "\033[2m",           // dim (TB_CAP_DIM)
    "",                  // invis (TB_CAP_INVISIBLE)
};

// screen
static const char *screen_caps[] = {
    "\033OP",            // kf1 (TB_CAP_F1)
    "\033OQ",            // kf2 (TB_CAP_F2)
    "\033OR",            // kf3 (TB_CAP_F3)
    "\033OS",            // kf4 (TB_CAP_F4)
    "\033[15~",          // kf5 (TB_CAP_F5)
    "\033[17~",          // kf6 (TB_CAP_F6)
    "\033[18~",          // kf7 (TB_CAP_F7)
    "\033[19~",          // kf8 (TB_CAP_F8)
    "\033[20~",          // kf9 (TB_CAP_F9)
    "\033[21~",          // kf10 (TB_CAP_F10)
    "\033[23~",          // kf11 (TB_CAP_F11)
    "\033[24~",          // kf12 (TB_CAP_F12)
    "\033[2~",           // kich1 (TB_CAP_INSERT)
    "\033[3~",           // kdch1 (TB_CAP_DELETE)
    "\033[1~",           // khome (TB_CAP_HOME)
    "\033[4~",           // kend (TB_CAP_END)
    "\033[5~",           // kpp (TB_CAP_PGUP)
    "\033[6~",           // knp (TB_CAP_PGDN)
    "\033OA",            // kcuu1 (TB_CAP_ARROW_UP)
    "\033OB",            // kcud1 (TB_CAP_ARROW_DOWN)
    "\033OD",            // kcub1 (TB_CAP_ARROW_LEFT)
    "\033OC",            // kcuf1 (TB_CAP_ARROW_RIGHT)
    "\033[Z",            // kcbt (TB_CAP_BACK_TAB)
    "\033[?1049h",       // smcup (TB_CAP_ENTER_CA)
    "\033[?1049l",       // rmcup (TB_CAP_EXIT_CA)
    "\033[34h\033[?25h", // cnorm (TB_CAP_SHOW_CURSOR)
    "\033[?25l",         // civis (TB_CAP_HIDE_CURSOR)
    "\033[H\033[J",      // clear (TB_CAP_CLEAR_SCREEN)
    "\033[m\017",        // sgr0 (TB_CAP_SGR0)
    "\033[4m",           // smul (TB_CAP_UNDERLINE)
    "\033[1m",           // bold (TB_CAP_BOLD)
    "\033[5m",           // blink (TB_CAP_BLINK)
    "",                  // sitm (TB_CAP_ITALIC)
    "\033[7m",           // rev (TB_CAP_REVERSE)
    "\033[?1h\033=",     // smkx (TB_CAP_ENTER_KEYPAD)
    "\033[?1l\033>",     // rmkx (TB_CAP_EXIT_KEYPAD)
    "\033[2m",           // dim (TB_CAP_DIM)
    "",                  // invis (TB_CAP_INVISIBLE)
};

// rxvt-256color
static const char *rxvt_256color_caps[] = {
    "\033[11~",              // kf1 (TB_CAP_F1)
    "\033[12~",              // kf2 (TB_CAP_F2)
    "\033[13~",              // kf3 (TB_CAP_F3)
    "\033[14~",              // kf4 (TB_CAP_F4)
    "\033[15~",              // kf5 (TB_CAP_F5)
    "\033[17~",              // kf6 (TB_CAP_F6)
    "\033[18~",              // kf7 (TB_CAP_F7)
    "\033[19~",              // kf8 (TB_CAP_F8)
    "\033[20~",              // kf9 (TB_CAP_F9)
    "\033[21~",              // kf10 (TB_CAP_F10)
    "\033[23~",              // kf11 (TB_CAP_F11)
    "\033[24~",              // kf12 (TB_CAP_F12)
    "\033[2~",               // kich1 (TB_CAP_INSERT)
    "\033[3~",               // kdch1 (TB_CAP_DELETE)
    "\033[7~",               // khome (TB_CAP_HOME)
    "\033[8~",               // kend (TB_CAP_END)
    "\033[5~",               // kpp (TB_CAP_PGUP)
    "\033[6~",               // knp (TB_CAP_PGDN)
    "\033[A",                // kcuu1 (TB_CAP_ARROW_UP)
    "\033[B",                // kcud1 (TB_CAP_ARROW_DOWN)
    "\033[D",                // kcub1 (TB_CAP_ARROW_LEFT)
    "\033[C",                // kcuf1 (TB_CAP_ARROW_RIGHT)
    "\033[Z",                // kcbt (TB_CAP_BACK_TAB)
    "\0337\033[?47h",        // smcup (TB_CAP_ENTER_CA)
    "\033[2J\033[?47l\0338", // rmcup (TB_CAP_EXIT_CA)
    "\033[?25h",             // cnorm (TB_CAP_SHOW_CURSOR)
    "\033[?25l",             // civis (TB_CAP_HIDE_CURSOR)
    "\033[H\033[2J",         // clear (TB_CAP_CLEAR_SCREEN)
    "\033[m\017",            // sgr0 (TB_CAP_SGR0)
    "\033[4m",               // smul (TB_CAP_UNDERLINE)
    "\033[1m",               // bold (TB_CAP_BOLD)
    "\033[5m",               // blink (TB_CAP_BLINK)
    "",                      // sitm (TB_CAP_ITALIC)
    "\033[7m",               // rev (TB_CAP_REVERSE)
    "\033=",                 // smkx (TB_CAP_ENTER_KEYPAD)
    "\033>",                 // rmkx (TB_CAP_EXIT_KEYPAD)
    "",                      // dim (TB_CAP_DIM)
    "",                      // invis (TB_CAP_INVISIBLE)
};

// rxvt-unicode
static const char *rxvt_unicode_caps[] = {
    "\033[11~",           // kf1 (TB_CAP_F1)
    "\033[12~",           // kf2 (TB_CAP_F2)
    "\033[13~",           // kf3 (TB_CAP_F3)
    "\033[14~",           // kf4 (TB_CAP_F4)
    "\033[15~",           // kf5 (TB_CAP_F5)
    "\033[17~",           // kf6 (TB_CAP_F6)
    "\033[18~",           // kf7 (TB_CAP_F7)
    "\033[19~",           // kf8 (TB_CAP_F8)
    "\033[20~",           // kf9 (TB_CAP_F9)
    "\033[21~",           // kf10 (TB_CAP_F10)
    "\033[23~",           // kf11 (TB_CAP_F11)
    "\033[24~",           // kf12 (TB_CAP_F12)
    "\033[2~",            // kich1 (TB_CAP_INSERT)
    "\033[3~",            // kdch1 (TB_CAP_DELETE)
    "\033[7~",            // khome (TB_CAP_HOME)
    "\033[8~",            // kend (TB_CAP_END)
    "\033[5~",            // kpp (TB_CAP_PGUP)
    "\033[6~",            // knp (TB_CAP_PGDN)
    "\033[A",             // kcuu1 (TB_CAP_ARROW_UP)
    "\033[B",             // kcud1 (TB_CAP_ARROW_DOWN)
    "\033[D",             // kcub1 (TB_CAP_ARROW_LEFT)
    "\033[C",             // kcuf1 (TB_CAP_ARROW_RIGHT)
    "\033[Z",             // kcbt (TB_CAP_BACK_TAB)
    "\033[?1049h",        // smcup (TB_CAP_ENTER_CA)
    "\033[r\033[?1049l",  // rmcup (TB_CAP_EXIT_CA)
    "\033[?12l\033[?25h", // cnorm (TB_CAP_SHOW_CURSOR)
    "\033[?25l",          // civis (TB_CAP_HIDE_CURSOR)
    "\033[H\033[2J",      // clear (TB_CAP_CLEAR_SCREEN)
    "\033[m\033(B",       // sgr0 (TB_CAP_SGR0)
    "\033[4m",            // smul (TB_CAP_UNDERLINE)
    "\033[1m",            // bold (TB_CAP_BOLD)
    "\033[5m",            // blink (TB_CAP_BLINK)
    "\033[3m",            // sitm (TB_CAP_ITALIC)
    "\033[7m",            // rev (TB_CAP_REVERSE)
    "\033=",              // smkx (TB_CAP_ENTER_KEYPAD)
    "\033>",              // rmkx (TB_CAP_EXIT_KEYPAD)
    "",                   // dim (TB_CAP_DIM)
    "",                   // invis (TB_CAP_INVISIBLE)
};

// Eterm
static const char *eterm_caps[] = {
    "\033[11~",              // kf1 (TB_CAP_F1)
    "\033[12~",              // kf2 (TB_CAP_F2)
    "\033[13~",              // kf3 (TB_CAP_F3)
    "\033[14~",              // kf4 (TB_CAP_F4)
    "\033[15~",              // kf5 (TB_CAP_F5)
    "\033[17~",              // kf6 (TB_CAP_F6)
    "\033[18~",              // kf7 (TB_CAP_F7)
    "\033[19~",              // kf8 (TB_CAP_F8)
    "\033[20~",              // kf9 (TB_CAP_F9)
    "\033[21~",              // kf10 (TB_CAP_F10)
    "\033[23~",              // kf11 (TB_CAP_F11)
    "\033[24~",              // kf12 (TB_CAP_F12)
    "\033[2~",               // kich1 (TB_CAP_INSERT)
    "\033[3~",               // kdch1 (TB_CAP_DELETE)
    "\033[7~",               // khome (TB_CAP_HOME)
    "\033[8~",               // kend (TB_CAP_END)
    "\033[5~",               // kpp (TB_CAP_PGUP)
    "\033[6~",               // knp (TB_CAP_PGDN)
    "\033[A",                // kcuu1 (TB_CAP_ARROW_UP)
    "\033[B",                // kcud1 (TB_CAP_ARROW_DOWN)
    "\033[D",                // kcub1 (TB_CAP_ARROW_LEFT)
    "\033[C",                // kcuf1 (TB_CAP_ARROW_RIGHT)
    "",                      // kcbt (TB_CAP_BACK_TAB)
    "\0337\033[?47h",        // smcup (TB_CAP_ENTER_CA)
    "\033[2J\033[?47l\0338", // rmcup (TB_CAP_EXIT_CA)
    "\033[?25h",             // cnorm (TB_CAP_SHOW_CURSOR)
    "\033[?25l",             // civis (TB_CAP_HIDE_CURSOR)
    "\033[H\033[2J",         // clear (TB_CAP_CLEAR_SCREEN)
    "\033[m\017",            // sgr0 (TB_CAP_SGR0)
    "\033[4m",               // smul (TB_CAP_UNDERLINE)
    "\033[1m",               // bold (TB_CAP_BOLD)
    "\033[5m",               // blink (TB_CAP_BLINK)
    "",                      // sitm (TB_CAP_ITALIC)
    "\033[7m",               // rev (TB_CAP_REVERSE)
    "",                      // smkx (TB_CAP_ENTER_KEYPAD)
    "",                      // rmkx (TB_CAP_EXIT_KEYPAD)
    "",                      // dim (TB_CAP_DIM)
    "",                      // invis (TB_CAP_INVISIBLE)
};

static struct {
    const char *name;
    const char **caps;
    const char *alias;
} builtin_terms[] = {
    {"xterm",         xterm_caps,         ""    },
    {"linux",         linux_caps,         ""    },
    {"screen",        screen_caps,        "tmux"},
    {"rxvt-256color", rxvt_256color_caps, ""    },
    {"rxvt-unicode",  rxvt_unicode_caps,  "rxvt"},
    {"Eterm",         eterm_caps,         ""    },
    {NULL,            NULL,               NULL  },
};

/* END codegen c */

static struct {
    const char *cap;
    const uint16_t key;
    const uint8_t mod;
} builtin_mod_caps[] = {
    // xterm arrows
    {"\x1b[1;2A",    TB_KEY_ARROW_UP,    TB_MOD_SHIFT                           },
    {"\x1b[1;3A",    TB_KEY_ARROW_UP,    TB_MOD_ALT                             },
    {"\x1b[1;4A",    TB_KEY_ARROW_UP,    TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[1;5A",    TB_KEY_ARROW_UP,    TB_MOD_CTRL                            },
    {"\x1b[1;6A",    TB_KEY_ARROW_UP,    TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[1;7A",    TB_KEY_ARROW_UP,    TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b[1;8A",    TB_KEY_ARROW_UP,    TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},

    {"\x1b[1;2B",    TB_KEY_ARROW_DOWN,  TB_MOD_SHIFT                           },
    {"\x1b[1;3B",    TB_KEY_ARROW_DOWN,  TB_MOD_ALT                             },
    {"\x1b[1;4B",    TB_KEY_ARROW_DOWN,  TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[1;5B",    TB_KEY_ARROW_DOWN,  TB_MOD_CTRL                            },
    {"\x1b[1;6B",    TB_KEY_ARROW_DOWN,  TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[1;7B",    TB_KEY_ARROW_DOWN,  TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b[1;8B",    TB_KEY_ARROW_DOWN,  TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},

    {"\x1b[1;2C",    TB_KEY_ARROW_RIGHT, TB_MOD_SHIFT                           },
    {"\x1b[1;3C",    TB_KEY_ARROW_RIGHT, TB_MOD_ALT                             },
    {"\x1b[1;4C",    TB_KEY_ARROW_RIGHT, TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[1;5C",    TB_KEY_ARROW_RIGHT, TB_MOD_CTRL                            },
    {"\x1b[1;6C",    TB_KEY_ARROW_RIGHT, TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[1;7C",    TB_KEY_ARROW_RIGHT, TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b[1;8C",    TB_KEY_ARROW_RIGHT, TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},

    {"\x1b[1;2D",    TB_KEY_ARROW_LEFT,  TB_MOD_SHIFT                           },
    {"\x1b[1;3D",    TB_KEY_ARROW_LEFT,  TB_MOD_ALT                             },
    {"\x1b[1;4D",    TB_KEY_ARROW_LEFT,  TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[1;5D",    TB_KEY_ARROW_LEFT,  TB_MOD_CTRL                            },
    {"\x1b[1;6D",    TB_KEY_ARROW_LEFT,  TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[1;7D",    TB_KEY_ARROW_LEFT,  TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b[1;8D",    TB_KEY_ARROW_LEFT,  TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},

    // xterm keys
    {"\x1b[1;2H",    TB_KEY_HOME,        TB_MOD_SHIFT                           },
    {"\x1b[1;3H",    TB_KEY_HOME,        TB_MOD_ALT                             },
    {"\x1b[1;4H",    TB_KEY_HOME,        TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[1;5H",    TB_KEY_HOME,        TB_MOD_CTRL                            },
    {"\x1b[1;6H",    TB_KEY_HOME,        TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[1;7H",    TB_KEY_HOME,        TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b[1;8H",    TB_KEY_HOME,        TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},

    {"\x1b[1;2F",    TB_KEY_END,         TB_MOD_SHIFT                           },
    {"\x1b[1;3F",    TB_KEY_END,         TB_MOD_ALT                             },
    {"\x1b[1;4F",    TB_KEY_END,         TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[1;5F",    TB_KEY_END,         TB_MOD_CTRL                            },
    {"\x1b[1;6F",    TB_KEY_END,         TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[1;7F",    TB_KEY_END,         TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b[1;8F",    TB_KEY_END,         TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},

    {"\x1b[2;2~",    TB_KEY_INSERT,      TB_MOD_SHIFT                           },
    {"\x1b[2;3~",    TB_KEY_INSERT,      TB_MOD_ALT                             },
    {"\x1b[2;4~",    TB_KEY_INSERT,      TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[2;5~",    TB_KEY_INSERT,      TB_MOD_CTRL                            },
    {"\x1b[2;6~",    TB_KEY_INSERT,      TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[2;7~",    TB_KEY_INSERT,      TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b[2;8~",    TB_KEY_INSERT,      TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},

    {"\x1b[3;2~",    TB_KEY_DELETE,      TB_MOD_SHIFT                           },
    {"\x1b[3;3~",    TB_KEY_DELETE,      TB_MOD_ALT                             },
    {"\x1b[3;4~",    TB_KEY_DELETE,      TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[3;5~",    TB_KEY_DELETE,      TB_MOD_CTRL                            },
    {"\x1b[3;6~",    TB_KEY_DELETE,      TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[3;7~",    TB_KEY_DELETE,      TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b[3;8~",    TB_KEY_DELETE,      TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},

    {"\x1b[5;2~",    TB_KEY_PGUP,        TB_MOD_SHIFT                           },
    {"\x1b[5;3~",    TB_KEY_PGUP,        TB_MOD_ALT                             },
    {"\x1b[5;4~",    TB_KEY_PGUP,        TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[5;5~",    TB_KEY_PGUP,        TB_MOD_CTRL                            },
    {"\x1b[5;6~",    TB_KEY_PGUP,        TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[5;7~",    TB_KEY_PGUP,        TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b[5;8~",    TB_KEY_PGUP,        TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},

    {"\x1b[6;2~",    TB_KEY_PGDN,        TB_MOD_SHIFT                           },
    {"\x1b[6;3~",    TB_KEY_PGDN,        TB_MOD_ALT                             },
    {"\x1b[6;4~",    TB_KEY_PGDN,        TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[6;5~",    TB_KEY_PGDN,        TB_MOD_CTRL                            },
    {"\x1b[6;6~",    TB_KEY_PGDN,        TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[6;7~",    TB_KEY_PGDN,        TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b[6;8~",    TB_KEY_PGDN,        TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},

    {"\x1b[1;2P",    TB_KEY_F1,          TB_MOD_SHIFT                           },
    {"\x1b[1;3P",    TB_KEY_F1,          TB_MOD_ALT                             },
    {"\x1b[1;4P",    TB_KEY_F1,          TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[1;5P",    TB_KEY_F1,          TB_MOD_CTRL                            },
    {"\x1b[1;6P",    TB_KEY_F1,          TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[1;7P",    TB_KEY_F1,          TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b[1;8P",    TB_KEY_F1,          TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},

    {"\x1b[1;2Q",    TB_KEY_F2,          TB_MOD_SHIFT                           },
    {"\x1b[1;3Q",    TB_KEY_F2,          TB_MOD_ALT                             },
    {"\x1b[1;4Q",    TB_KEY_F2,          TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[1;5Q",    TB_KEY_F2,          TB_MOD_CTRL                            },
    {"\x1b[1;6Q",    TB_KEY_F2,          TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[1;7Q",    TB_KEY_F2,          TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b[1;8Q",    TB_KEY_F2,          TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},

    {"\x1b[1;2R",    TB_KEY_F3,          TB_MOD_SHIFT                           },
    {"\x1b[1;3R",    TB_KEY_F3,          TB_MOD_ALT                             },
    {"\x1b[1;4R",    TB_KEY_F3,          TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[1;5R",    TB_KEY_F3,          TB_MOD_CTRL                            },
    {"\x1b[1;6R",    TB_KEY_F3,          TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[1;7R",    TB_KEY_F3,          TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b[1;8R",    TB_KEY_F3,          TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},

    {"\x1b[1;2S",    TB_KEY_F4,          TB_MOD_SHIFT                           },
    {"\x1b[1;3S",    TB_KEY_F4,          TB_MOD_ALT                             },
    {"\x1b[1;4S",    TB_KEY_F4,          TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[1;5S",    TB_KEY_F4,          TB_MOD_CTRL                            },
    {"\x1b[1;6S",    TB_KEY_F4,          TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[1;7S",    TB_KEY_F4,          TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b[1;8S",    TB_KEY_F4,          TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},

    {"\x1b[15;2~",   TB_KEY_F5,          TB_MOD_SHIFT                           },
    {"\x1b[15;3~",   TB_KEY_F5,          TB_MOD_ALT                             },
    {"\x1b[15;4~",   TB_KEY_F5,          TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[15;5~",   TB_KEY_F5,          TB_MOD_CTRL                            },
    {"\x1b[15;6~",   TB_KEY_F5,          TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[15;7~",   TB_KEY_F5,          TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b[15;8~",   TB_KEY_F5,          TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},

    {"\x1b[17;2~",   TB_KEY_F6,          TB_MOD_SHIFT                           },
    {"\x1b[17;3~",   TB_KEY_F6,          TB_MOD_ALT                             },
    {"\x1b[17;4~",   TB_KEY_F6,          TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[17;5~",   TB_KEY_F6,          TB_MOD_CTRL                            },
    {"\x1b[17;6~",   TB_KEY_F6,          TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[17;7~",   TB_KEY_F6,          TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b[17;8~",   TB_KEY_F6,          TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},

    {"\x1b[18;2~",   TB_KEY_F7,          TB_MOD_SHIFT                           },
    {"\x1b[18;3~",   TB_KEY_F7,          TB_MOD_ALT                             },
    {"\x1b[18;4~",   TB_KEY_F7,          TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[18;5~",   TB_KEY_F7,          TB_MOD_CTRL                            },
    {"\x1b[18;6~",   TB_KEY_F7,          TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[18;7~",   TB_KEY_F7,          TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b[18;8~",   TB_KEY_F7,          TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},

    {"\x1b[19;2~",   TB_KEY_F8,          TB_MOD_SHIFT                           },
    {"\x1b[19;3~",   TB_KEY_F8,          TB_MOD_ALT                             },
    {"\x1b[19;4~",   TB_KEY_F8,          TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[19;5~",   TB_KEY_F8,          TB_MOD_CTRL                            },
    {"\x1b[19;6~",   TB_KEY_F8,          TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[19;7~",   TB_KEY_F8,          TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b[19;8~",   TB_KEY_F8,          TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},

    {"\x1b[20;2~",   TB_KEY_F9,          TB_MOD_SHIFT                           },
    {"\x1b[20;3~",   TB_KEY_F9,          TB_MOD_ALT                             },
    {"\x1b[20;4~",   TB_KEY_F9,          TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[20;5~",   TB_KEY_F9,          TB_MOD_CTRL                            },
    {"\x1b[20;6~",   TB_KEY_F9,          TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[20;7~",   TB_KEY_F9,          TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b[20;8~",   TB_KEY_F9,          TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},

    {"\x1b[21;2~",   TB_KEY_F10,         TB_MOD_SHIFT                           },
    {"\x1b[21;3~",   TB_KEY_F10,         TB_MOD_ALT                             },
    {"\x1b[21;4~",   TB_KEY_F10,         TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[21;5~",   TB_KEY_F10,         TB_MOD_CTRL                            },
    {"\x1b[21;6~",   TB_KEY_F10,         TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[21;7~",   TB_KEY_F10,         TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b[21;8~",   TB_KEY_F10,         TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},

    {"\x1b[23;2~",   TB_KEY_F11,         TB_MOD_SHIFT                           },
    {"\x1b[23;3~",   TB_KEY_F11,         TB_MOD_ALT                             },
    {"\x1b[23;4~",   TB_KEY_F11,         TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[23;5~",   TB_KEY_F11,         TB_MOD_CTRL                            },
    {"\x1b[23;6~",   TB_KEY_F11,         TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[23;7~",   TB_KEY_F11,         TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b[23;8~",   TB_KEY_F11,         TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},

    {"\x1b[24;2~",   TB_KEY_F12,         TB_MOD_SHIFT                           },
    {"\x1b[24;3~",   TB_KEY_F12,         TB_MOD_ALT                             },
    {"\x1b[24;4~",   TB_KEY_F12,         TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[24;5~",   TB_KEY_F12,         TB_MOD_CTRL                            },
    {"\x1b[24;6~",   TB_KEY_F12,         TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[24;7~",   TB_KEY_F12,         TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b[24;8~",   TB_KEY_F12,         TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},

    // rxvt arrows
    {"\x1b[a",       TB_KEY_ARROW_UP,    TB_MOD_SHIFT                           },
    {"\x1b\x1b[A",   TB_KEY_ARROW_UP,    TB_MOD_ALT                             },
    {"\x1b\x1b[a",   TB_KEY_ARROW_UP,    TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1bOa",       TB_KEY_ARROW_UP,    TB_MOD_CTRL                            },
    {"\x1b\x1bOa",   TB_KEY_ARROW_UP,    TB_MOD_CTRL | TB_MOD_ALT               },

    {"\x1b[b",       TB_KEY_ARROW_DOWN,  TB_MOD_SHIFT                           },
    {"\x1b\x1b[B",   TB_KEY_ARROW_DOWN,  TB_MOD_ALT                             },
    {"\x1b\x1b[b",   TB_KEY_ARROW_DOWN,  TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1bOb",       TB_KEY_ARROW_DOWN,  TB_MOD_CTRL                            },
    {"\x1b\x1bOb",   TB_KEY_ARROW_DOWN,  TB_MOD_CTRL | TB_MOD_ALT               },

    {"\x1b[c",       TB_KEY_ARROW_RIGHT, TB_MOD_SHIFT                           },
    {"\x1b\x1b[C",   TB_KEY_ARROW_RIGHT, TB_MOD_ALT                             },
    {"\x1b\x1b[c",   TB_KEY_ARROW_RIGHT, TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1bOc",       TB_KEY_ARROW_RIGHT, TB_MOD_CTRL                            },
    {"\x1b\x1bOc",   TB_KEY_ARROW_RIGHT, TB_MOD_CTRL | TB_MOD_ALT               },

    {"\x1b[d",       TB_KEY_ARROW_LEFT,  TB_MOD_SHIFT                           },
    {"\x1b\x1b[D",   TB_KEY_ARROW_LEFT,  TB_MOD_ALT                             },
    {"\x1b\x1b[d",   TB_KEY_ARROW_LEFT,  TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1bOd",       TB_KEY_ARROW_LEFT,  TB_MOD_CTRL                            },
    {"\x1b\x1bOd",   TB_KEY_ARROW_LEFT,  TB_MOD_CTRL | TB_MOD_ALT               },

    // rxvt keys
    {"\x1b[7$",      TB_KEY_HOME,        TB_MOD_SHIFT                           },
    {"\x1b\x1b[7~",  TB_KEY_HOME,        TB_MOD_ALT                             },
    {"\x1b\x1b[7$",  TB_KEY_HOME,        TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[7^",      TB_KEY_HOME,        TB_MOD_CTRL                            },
    {"\x1b[7@",      TB_KEY_HOME,        TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b\x1b[7^",  TB_KEY_HOME,        TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b\x1b[7@",  TB_KEY_HOME,        TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},

    {"\x1b\x1b[8~",  TB_KEY_END,         TB_MOD_ALT                             },
    {"\x1b\x1b[8$",  TB_KEY_END,         TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[8^",      TB_KEY_END,         TB_MOD_CTRL                            },
    {"\x1b\x1b[8^",  TB_KEY_END,         TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b\x1b[8@",  TB_KEY_END,         TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},
    {"\x1b[8@",      TB_KEY_END,         TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[8$",      TB_KEY_END,         TB_MOD_SHIFT                           },

    {"\x1b\x1b[2~",  TB_KEY_INSERT,      TB_MOD_ALT                             },
    {"\x1b\x1b[2$",  TB_KEY_INSERT,      TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[2^",      TB_KEY_INSERT,      TB_MOD_CTRL                            },
    {"\x1b\x1b[2^",  TB_KEY_INSERT,      TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b\x1b[2@",  TB_KEY_INSERT,      TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},
    {"\x1b[2@",      TB_KEY_INSERT,      TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[2$",      TB_KEY_INSERT,      TB_MOD_SHIFT                           },

    {"\x1b\x1b[3~",  TB_KEY_DELETE,      TB_MOD_ALT                             },
    {"\x1b\x1b[3$",  TB_KEY_DELETE,      TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[3^",      TB_KEY_DELETE,      TB_MOD_CTRL                            },
    {"\x1b\x1b[3^",  TB_KEY_DELETE,      TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b\x1b[3@",  TB_KEY_DELETE,      TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},
    {"\x1b[3@",      TB_KEY_DELETE,      TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[3$",      TB_KEY_DELETE,      TB_MOD_SHIFT                           },

    {"\x1b\x1b[5~",  TB_KEY_PGUP,        TB_MOD_ALT                             },
    {"\x1b\x1b[5$",  TB_KEY_PGUP,        TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[5^",      TB_KEY_PGUP,        TB_MOD_CTRL                            },
    {"\x1b\x1b[5^",  TB_KEY_PGUP,        TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b\x1b[5@",  TB_KEY_PGUP,        TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},
    {"\x1b[5@",      TB_KEY_PGUP,        TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[5$",      TB_KEY_PGUP,        TB_MOD_SHIFT                           },

    {"\x1b\x1b[6~",  TB_KEY_PGDN,        TB_MOD_ALT                             },
    {"\x1b\x1b[6$",  TB_KEY_PGDN,        TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[6^",      TB_KEY_PGDN,        TB_MOD_CTRL                            },
    {"\x1b\x1b[6^",  TB_KEY_PGDN,        TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b\x1b[6@",  TB_KEY_PGDN,        TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},
    {"\x1b[6@",      TB_KEY_PGDN,        TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[6$",      TB_KEY_PGDN,        TB_MOD_SHIFT                           },

    {"\x1b\x1b[11~", TB_KEY_F1,          TB_MOD_ALT                             },
    {"\x1b\x1b[23~", TB_KEY_F1,          TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[11^",     TB_KEY_F1,          TB_MOD_CTRL                            },
    {"\x1b\x1b[11^", TB_KEY_F1,          TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b\x1b[23^", TB_KEY_F1,          TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},
    {"\x1b[23^",     TB_KEY_F1,          TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[23~",     TB_KEY_F1,          TB_MOD_SHIFT                           },

    {"\x1b\x1b[12~", TB_KEY_F2,          TB_MOD_ALT                             },
    {"\x1b\x1b[24~", TB_KEY_F2,          TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[12^",     TB_KEY_F2,          TB_MOD_CTRL                            },
    {"\x1b\x1b[12^", TB_KEY_F2,          TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b\x1b[24^", TB_KEY_F2,          TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},
    {"\x1b[24^",     TB_KEY_F2,          TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[24~",     TB_KEY_F2,          TB_MOD_SHIFT                           },

    {"\x1b\x1b[13~", TB_KEY_F3,          TB_MOD_ALT                             },
    {"\x1b\x1b[25~", TB_KEY_F3,          TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[13^",     TB_KEY_F3,          TB_MOD_CTRL                            },
    {"\x1b\x1b[13^", TB_KEY_F3,          TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b\x1b[25^", TB_KEY_F3,          TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},
    {"\x1b[25^",     TB_KEY_F3,          TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[25~",     TB_KEY_F3,          TB_MOD_SHIFT                           },

    {"\x1b\x1b[14~", TB_KEY_F4,          TB_MOD_ALT                             },
    {"\x1b\x1b[26~", TB_KEY_F4,          TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[14^",     TB_KEY_F4,          TB_MOD_CTRL                            },
    {"\x1b\x1b[14^", TB_KEY_F4,          TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b\x1b[26^", TB_KEY_F4,          TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},
    {"\x1b[26^",     TB_KEY_F4,          TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[26~",     TB_KEY_F4,          TB_MOD_SHIFT                           },

    {"\x1b\x1b[15~", TB_KEY_F5,          TB_MOD_ALT                             },
    {"\x1b\x1b[28~", TB_KEY_F5,          TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[15^",     TB_KEY_F5,          TB_MOD_CTRL                            },
    {"\x1b\x1b[15^", TB_KEY_F5,          TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b\x1b[28^", TB_KEY_F5,          TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},
    {"\x1b[28^",     TB_KEY_F5,          TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[28~",     TB_KEY_F5,          TB_MOD_SHIFT                           },

    {"\x1b\x1b[17~", TB_KEY_F6,          TB_MOD_ALT                             },
    {"\x1b\x1b[29~", TB_KEY_F6,          TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[17^",     TB_KEY_F6,          TB_MOD_CTRL                            },
    {"\x1b\x1b[17^", TB_KEY_F6,          TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b\x1b[29^", TB_KEY_F6,          TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},
    {"\x1b[29^",     TB_KEY_F6,          TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[29~",     TB_KEY_F6,          TB_MOD_SHIFT                           },

    {"\x1b\x1b[18~", TB_KEY_F7,          TB_MOD_ALT                             },
    {"\x1b\x1b[31~", TB_KEY_F7,          TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[18^",     TB_KEY_F7,          TB_MOD_CTRL                            },
    {"\x1b\x1b[18^", TB_KEY_F7,          TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b\x1b[31^", TB_KEY_F7,          TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},
    {"\x1b[31^",     TB_KEY_F7,          TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[31~",     TB_KEY_F7,          TB_MOD_SHIFT                           },

    {"\x1b\x1b[19~", TB_KEY_F8,          TB_MOD_ALT                             },
    {"\x1b\x1b[32~", TB_KEY_F8,          TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[19^",     TB_KEY_F8,          TB_MOD_CTRL                            },
    {"\x1b\x1b[19^", TB_KEY_F8,          TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b\x1b[32^", TB_KEY_F8,          TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},
    {"\x1b[32^",     TB_KEY_F8,          TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[32~",     TB_KEY_F8,          TB_MOD_SHIFT                           },

    {"\x1b\x1b[20~", TB_KEY_F9,          TB_MOD_ALT                             },
    {"\x1b\x1b[33~", TB_KEY_F9,          TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[20^",     TB_KEY_F9,          TB_MOD_CTRL                            },
    {"\x1b\x1b[20^", TB_KEY_F9,          TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b\x1b[33^", TB_KEY_F9,          TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},
    {"\x1b[33^",     TB_KEY_F9,          TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[33~",     TB_KEY_F9,          TB_MOD_SHIFT                           },

    {"\x1b\x1b[21~", TB_KEY_F10,         TB_MOD_ALT                             },
    {"\x1b\x1b[34~", TB_KEY_F10,         TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[21^",     TB_KEY_F10,         TB_MOD_CTRL                            },
    {"\x1b\x1b[21^", TB_KEY_F10,         TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b\x1b[34^", TB_KEY_F10,         TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},
    {"\x1b[34^",     TB_KEY_F10,         TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[34~",     TB_KEY_F10,         TB_MOD_SHIFT                           },

    {"\x1b\x1b[23~", TB_KEY_F11,         TB_MOD_ALT                             },
    {"\x1b\x1b[23$", TB_KEY_F11,         TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[23^",     TB_KEY_F11,         TB_MOD_CTRL                            },
    {"\x1b\x1b[23^", TB_KEY_F11,         TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b\x1b[23@", TB_KEY_F11,         TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},
    {"\x1b[23@",     TB_KEY_F11,         TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[23$",     TB_KEY_F11,         TB_MOD_SHIFT                           },

    {"\x1b\x1b[24~", TB_KEY_F12,         TB_MOD_ALT                             },
    {"\x1b\x1b[24$", TB_KEY_F12,         TB_MOD_ALT | TB_MOD_SHIFT              },
    {"\x1b[24^",     TB_KEY_F12,         TB_MOD_CTRL                            },
    {"\x1b\x1b[24^", TB_KEY_F12,         TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1b\x1b[24@", TB_KEY_F12,         TB_MOD_CTRL | TB_MOD_ALT | TB_MOD_SHIFT},
    {"\x1b[24@",     TB_KEY_F12,         TB_MOD_CTRL | TB_MOD_SHIFT             },
    {"\x1b[24$",     TB_KEY_F12,         TB_MOD_SHIFT                           },

    // linux console/putty arrows
    {"\x1b[A",       TB_KEY_ARROW_UP,    TB_MOD_SHIFT                           },
    {"\x1b[B",       TB_KEY_ARROW_DOWN,  TB_MOD_SHIFT                           },
    {"\x1b[C",       TB_KEY_ARROW_RIGHT, TB_MOD_SHIFT                           },
    {"\x1b[D",       TB_KEY_ARROW_LEFT,  TB_MOD_SHIFT                           },

    // more putty arrows
    {"\x1bOA",       TB_KEY_ARROW_UP,    TB_MOD_CTRL                            },
    {"\x1b\x1bOA",   TB_KEY_ARROW_UP,    TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1bOB",       TB_KEY_ARROW_DOWN,  TB_MOD_CTRL                            },
    {"\x1b\x1bOB",   TB_KEY_ARROW_DOWN,  TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1bOC",       TB_KEY_ARROW_RIGHT, TB_MOD_CTRL                            },
    {"\x1b\x1bOC",   TB_KEY_ARROW_RIGHT, TB_MOD_CTRL | TB_MOD_ALT               },
    {"\x1bOD",       TB_KEY_ARROW_LEFT,  TB_MOD_CTRL                            },
    {"\x1b\x1bOD",   TB_KEY_ARROW_LEFT,  TB_MOD_CTRL | TB_MOD_ALT               },

    {NULL,           0,                  0                                      },
};

static const unsigned char utf8_length[256] = {1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 1, 1};

static const unsigned char utf8_mask[6] = {0x7f, 0x1f, 0x0f, 0x07, 0x03, 0x01};

#ifndef TB_OPT_LIBC_WCHAR
static struct {
    uint32_t range_start;
    uint32_t range_end;
    int width; // -1 means iswprint==0, otherwise wcwidth value (0, 1, or 2)
} wcwidth_table[] = {
    // clang-format off
    {0x000001, 0x00001f, -1}, {0x000020, 0x00007e,  1}, {0x00007f, 0x00009f, -1},
    {0x0000a0, 0x0002ff,  1}, {0x000300, 0x00036f,  0}, {0x000370, 0x000377,  1},
    {0x000378, 0x000379, -1}, {0x00037a, 0x00037f,  1}, {0x000380, 0x000383, -1},
    {0x000384, 0x00038a,  1}, {0x00038b, 0x00038b, -1}, {0x00038c, 0x00038c,  1},
    {0x00038d, 0x00038d, -1}, {0x00038e, 0x0003a1,  1}, {0x0003a2, 0x0003a2, -1},
    {0x0003a3, 0x000482,  1}, {0x000483, 0x000489,  0}, {0x00048a, 0x00052f,  1},
    {0x000530, 0x000530, -1}, {0x000531, 0x000556,  1}, {0x000557, 0x000558, -1},
    {0x000559, 0x00058a,  1}, {0x00058b, 0x00058c, -1}, {0x00058d, 0x00058f,  1},
    {0x000590, 0x000590, -1}, {0x000591, 0x0005bd,  0}, {0x0005be, 0x0005be,  1},
    {0x0005bf, 0x0005bf,  0}, {0x0005c0, 0x0005c0,  1}, {0x0005c1, 0x0005c2,  0},
    {0x0005c3, 0x0005c3,  1}, {0x0005c4, 0x0005c5,  0}, {0x0005c6, 0x0005c6,  1},
    {0x0005c7, 0x0005c7,  0}, {0x0005c8, 0x0005cf, -1}, {0x0005d0, 0x0005ea,  1},
    {0x0005eb, 0x0005ee, -1}, {0x0005ef, 0x0005f4,  1}, {0x0005f5, 0x0005ff, -1},
    {0x000600, 0x00060f,  1}, {0x000610, 0x00061a,  0}, {0x00061b, 0x00061b,  1},
    {0x00061c, 0x00061c,  0}, {0x00061d, 0x00064a,  1}, {0x00064b, 0x00065f,  0},
    {0x000660, 0x00066f,  1}, {0x000670, 0x000670,  0}, {0x000671, 0x0006d5,  1},
    {0x0006d6, 0x0006dc,  0}, {0x0006dd, 0x0006de,  1}, {0x0006df, 0x0006e4,  0},
    {0x0006e5, 0x0006e6,  1}, {0x0006e7, 0x0006e8,  0}, {0x0006e9, 0x0006e9,  1},
    {0x0006ea, 0x0006ed,  0}, {0x0006ee, 0x00070d,  1}, {0x00070e, 0x00070e, -1},
    {0x00070f, 0x000710,  1}, {0x000711, 0x000711,  0}, {0x000712, 0x00072f,  1},
    {0x000730, 0x00074a,  0}, {0x00074b, 0x00074c, -1}, {0x00074d, 0x0007a5,  1},
    {0x0007a6, 0x0007b0,  0}, {0x0007b1, 0x0007b1,  1}, {0x0007b2, 0x0007bf, -1},
    {0x0007c0, 0x0007ea,  1}, {0x0007eb, 0x0007f3,  0}, {0x0007f4, 0x0007fa,  1},
    {0x0007fb, 0x0007fc, -1}, {0x0007fd, 0x0007fd,  0}, {0x0007fe, 0x000815,  1},
    {0x000816, 0x000819,  0}, {0x00081a, 0x00081a,  1}, {0x00081b, 0x000823,  0},
    {0x000824, 0x000824,  1}, {0x000825, 0x000827,  0}, {0x000828, 0x000828,  1},
    {0x000829, 0x00082d,  0}, {0x00082e, 0x00082f, -1}, {0x000830, 0x00083e,  1},
    {0x00083f, 0x00083f, -1}, {0x000840, 0x000858,  1}, {0x000859, 0x00085b,  0},
    {0x00085c, 0x00085d, -1}, {0x00085e, 0x00085e,  1}, {0x00085f, 0x00085f, -1},
    {0x000860, 0x00086a,  1}, {0x00086b, 0x00086f, -1}, {0x000870, 0x00088e,  1},
    {0x00088f, 0x00088f, -1}, {0x000890, 0x000891,  1}, {0x000892, 0x000896, -1},
    {0x000897, 0x00089f,  0}, {0x0008a0, 0x0008c9,  1}, {0x0008ca, 0x0008e1,  0},
    {0x0008e2, 0x0008e2,  1}, {0x0008e3, 0x000902,  0}, {0x000903, 0x000939,  1},
    {0x00093a, 0x00093a,  0}, {0x00093b, 0x00093b,  1}, {0x00093c, 0x00093c,  0},
    {0x00093d, 0x000940,  1}, {0x000941, 0x000948,  0}, {0x000949, 0x00094c,  1},
    {0x00094d, 0x00094d,  0}, {0x00094e, 0x000950,  1}, {0x000951, 0x000957,  0},
    {0x000958, 0x000961,  1}, {0x000962, 0x000963,  0}, {0x000964, 0x000980,  1},
    {0x000981, 0x000981,  0}, {0x000982, 0x000983,  1}, {0x000984, 0x000984, -1},
    {0x000985, 0x00098c,  1}, {0x00098d, 0x00098e, -1}, {0x00098f, 0x000990,  1},
    {0x000991, 0x000992, -1}, {0x000993, 0x0009a8,  1}, {0x0009a9, 0x0009a9, -1},
    {0x0009aa, 0x0009b0,  1}, {0x0009b1, 0x0009b1, -1}, {0x0009b2, 0x0009b2,  1},
    {0x0009b3, 0x0009b5, -1}, {0x0009b6, 0x0009b9,  1}, {0x0009ba, 0x0009bb, -1},
    {0x0009bc, 0x0009bc,  0}, {0x0009bd, 0x0009c0,  1}, {0x0009c1, 0x0009c4,  0},
    {0x0009c5, 0x0009c6, -1}, {0x0009c7, 0x0009c8,  1}, {0x0009c9, 0x0009ca, -1},
    {0x0009cb, 0x0009cc,  1}, {0x0009cd, 0x0009cd,  0}, {0x0009ce, 0x0009ce,  1},
    {0x0009cf, 0x0009d6, -1}, {0x0009d7, 0x0009d7,  1}, {0x0009d8, 0x0009db, -1},
    {0x0009dc, 0x0009dd,  1}, {0x0009de, 0x0009de, -1}, {0x0009df, 0x0009e1,  1},
    {0x0009e2, 0x0009e3,  0}, {0x0009e4, 0x0009e5, -1}, {0x0009e6, 0x0009fd,  1},
    {0x0009fe, 0x0009fe,  0}, {0x0009ff, 0x000a00, -1}, {0x000a01, 0x000a02,  0},
    {0x000a03, 0x000a03,  1}, {0x000a04, 0x000a04, -1}, {0x000a05, 0x000a0a,  1},
    {0x000a0b, 0x000a0e, -1}, {0x000a0f, 0x000a10,  1}, {0x000a11, 0x000a12, -1},
    {0x000a13, 0x000a28,  1}, {0x000a29, 0x000a29, -1}, {0x000a2a, 0x000a30,  1},
    {0x000a31, 0x000a31, -1}, {0x000a32, 0x000a33,  1}, {0x000a34, 0x000a34, -1},
    {0x000a35, 0x000a36,  1}, {0x000a37, 0x000a37, -1}, {0x000a38, 0x000a39,  1},
    {0x000a3a, 0x000a3b, -1}, {0x000a3c, 0x000a3c,  0}, {0x000a3d, 0x000a3d, -1},
    {0x000a3e, 0x000a40,  1}, {0x000a41, 0x000a42,  0}, {0x000a43, 0x000a46, -1},
    {0x000a47, 0x000a48,  0}, {0x000a49, 0x000a4a, -1}, {0x000a4b, 0x000a4d,  0},
    {0x000a4e, 0x000a50, -1}, {0x000a51, 0x000a51,  0}, {0x000a52, 0x000a58, -1},
    {0x000a59, 0x000a5c,  1}, {0x000a5d, 0x000a5d, -1}, {0x000a5e, 0x000a5e,  1},
    {0x000a5f, 0x000a65, -1}, {0x000a66, 0x000a6f,  1}, {0x000a70, 0x000a71,  0},
    {0x000a72, 0x000a74,  1}, {0x000a75, 0x000a75,  0}, {0x000a76, 0x000a76,  1},
    {0x000a77, 0x000a80, -1}, {0x000a81, 0x000a82,  0}, {0x000a83, 0x000a83,  1},
    {0x000a84, 0x000a84, -1}, {0x000a85, 0x000a8d,  1}, {0x000a8e, 0x000a8e, -1},
    {0x000a8f, 0x000a91,  1}, {0x000a92, 0x000a92, -1}, {0x000a93, 0x000aa8,  1},
    {0x000aa9, 0x000aa9, -1}, {0x000aaa, 0x000ab0,  1}, {0x000ab1, 0x000ab1, -1},
    {0x000ab2, 0x000ab3,  1}, {0x000ab4, 0x000ab4, -1}, {0x000ab5, 0x000ab9,  1},
    {0x000aba, 0x000abb, -1}, {0x000abc, 0x000abc,  0}, {0x000abd, 0x000ac0,  1},
    {0x000ac1, 0x000ac5,  0}, {0x000ac6, 0x000ac6, -1}, {0x000ac7, 0x000ac8,  0},
    {0x000ac9, 0x000ac9,  1}, {0x000aca, 0x000aca, -1}, {0x000acb, 0x000acc,  1},
    {0x000acd, 0x000acd,  0}, {0x000ace, 0x000acf, -1}, {0x000ad0, 0x000ad0,  1},
    {0x000ad1, 0x000adf, -1}, {0x000ae0, 0x000ae1,  1}, {0x000ae2, 0x000ae3,  0},
    {0x000ae4, 0x000ae5, -1}, {0x000ae6, 0x000af1,  1}, {0x000af2, 0x000af8, -1},
    {0x000af9, 0x000af9,  1}, {0x000afa, 0x000aff,  0}, {0x000b00, 0x000b00, -1},
    {0x000b01, 0x000b01,  0}, {0x000b02, 0x000b03,  1}, {0x000b04, 0x000b04, -1},
    {0x000b05, 0x000b0c,  1}, {0x000b0d, 0x000b0e, -1}, {0x000b0f, 0x000b10,  1},
    {0x000b11, 0x000b12, -1}, {0x000b13, 0x000b28,  1}, {0x000b29, 0x000b29, -1},
    {0x000b2a, 0x000b30,  1}, {0x000b31, 0x000b31, -1}, {0x000b32, 0x000b33,  1},
    {0x000b34, 0x000b34, -1}, {0x000b35, 0x000b39,  1}, {0x000b3a, 0x000b3b, -1},
    {0x000b3c, 0x000b3c,  0}, {0x000b3d, 0x000b3e,  1}, {0x000b3f, 0x000b3f,  0},
    {0x000b40, 0x000b40,  1}, {0x000b41, 0x000b44,  0}, {0x000b45, 0x000b46, -1},
    {0x000b47, 0x000b48,  1}, {0x000b49, 0x000b4a, -1}, {0x000b4b, 0x000b4c,  1},
    {0x000b4d, 0x000b4d,  0}, {0x000b4e, 0x000b54, -1}, {0x000b55, 0x000b56,  0},
    {0x000b57, 0x000b57,  1}, {0x000b58, 0x000b5b, -1}, {0x000b5c, 0x000b5d,  1},
    {0x000b5e, 0x000b5e, -1}, {0x000b5f, 0x000b61,  1}, {0x000b62, 0x000b63,  0},
    {0x000b64, 0x000b65, -1}, {0x000b66, 0x000b77,  1}, {0x000b78, 0x000b81, -1},
    {0x000b82, 0x000b82,  0}, {0x000b83, 0x000b83,  1}, {0x000b84, 0x000b84, -1},
    {0x000b85, 0x000b8a,  1}, {0x000b8b, 0x000b8d, -1}, {0x000b8e, 0x000b90,  1},
    {0x000b91, 0x000b91, -1}, {0x000b92, 0x000b95,  1}, {0x000b96, 0x000b98, -1},
    {0x000b99, 0x000b9a,  1}, {0x000b9b, 0x000b9b, -1}, {0x000b9c, 0x000b9c,  1},
    {0x000b9d, 0x000b9d, -1}, {0x000b9e, 0x000b9f,  1}, {0x000ba0, 0x000ba2, -1},
    {0x000ba3, 0x000ba4,  1}, {0x000ba5, 0x000ba7, -1}, {0x000ba8, 0x000baa,  1},
    {0x000bab, 0x000bad, -1}, {0x000bae, 0x000bb9,  1}, {0x000bba, 0x000bbd, -1},
    {0x000bbe, 0x000bbf,  1}, {0x000bc0, 0x000bc0,  0}, {0x000bc1, 0x000bc2,  1},
    {0x000bc3, 0x000bc5, -1}, {0x000bc6, 0x000bc8,  1}, {0x000bc9, 0x000bc9, -1},
    {0x000bca, 0x000bcc,  1}, {0x000bcd, 0x000bcd,  0}, {0x000bce, 0x000bcf, -1},
    {0x000bd0, 0x000bd0,  1}, {0x000bd1, 0x000bd6, -1}, {0x000bd7, 0x000bd7,  1},
    {0x000bd8, 0x000be5, -1}, {0x000be6, 0x000bfa,  1}, {0x000bfb, 0x000bff, -1},
    {0x000c00, 0x000c00,  0}, {0x000c01, 0x000c03,  1}, {0x000c04, 0x000c04,  0},
    {0x000c05, 0x000c0c,  1}, {0x000c0d, 0x000c0d, -1}, {0x000c0e, 0x000c10,  1},
    {0x000c11, 0x000c11, -1}, {0x000c12, 0x000c28,  1}, {0x000c29, 0x000c29, -1},
    {0x000c2a, 0x000c39,  1}, {0x000c3a, 0x000c3b, -1}, {0x000c3c, 0x000c3c,  0},
    {0x000c3d, 0x000c3d,  1}, {0x000c3e, 0x000c40,  0}, {0x000c41, 0x000c44,  1},
    {0x000c45, 0x000c45, -1}, {0x000c46, 0x000c48,  0}, {0x000c49, 0x000c49, -1},
    {0x000c4a, 0x000c4d,  0}, {0x000c4e, 0x000c54, -1}, {0x000c55, 0x000c56,  0},
    {0x000c57, 0x000c57, -1}, {0x000c58, 0x000c5a,  1}, {0x000c5b, 0x000c5c, -1},
    {0x000c5d, 0x000c5d,  1}, {0x000c5e, 0x000c5f, -1}, {0x000c60, 0x000c61,  1},
    {0x000c62, 0x000c63,  0}, {0x000c64, 0x000c65, -1}, {0x000c66, 0x000c6f,  1},
    {0x000c70, 0x000c76, -1}, {0x000c77, 0x000c80,  1}, {0x000c81, 0x000c81,  0},
    {0x000c82, 0x000c8c,  1}, {0x000c8d, 0x000c8d, -1}, {0x000c8e, 0x000c90,  1},
    {0x000c91, 0x000c91, -1}, {0x000c92, 0x000ca8,  1}, {0x000ca9, 0x000ca9, -1},
    {0x000caa, 0x000cb3,  1}, {0x000cb4, 0x000cb4, -1}, {0x000cb5, 0x000cb9,  1},
    {0x000cba, 0x000cbb, -1}, {0x000cbc, 0x000cbc,  0}, {0x000cbd, 0x000cbe,  1},
    {0x000cbf, 0x000cbf,  0}, {0x000cc0, 0x000cc4,  1}, {0x000cc5, 0x000cc5, -1},
    {0x000cc6, 0x000cc6,  0}, {0x000cc7, 0x000cc8,  1}, {0x000cc9, 0x000cc9, -1},
    {0x000cca, 0x000ccb,  1}, {0x000ccc, 0x000ccd,  0}, {0x000cce, 0x000cd4, -1},
    {0x000cd5, 0x000cd6,  1}, {0x000cd7, 0x000cdc, -1}, {0x000cdd, 0x000cde,  1},
    {0x000cdf, 0x000cdf, -1}, {0x000ce0, 0x000ce1,  1}, {0x000ce2, 0x000ce3,  0},
    {0x000ce4, 0x000ce5, -1}, {0x000ce6, 0x000cef,  1}, {0x000cf0, 0x000cf0, -1},
    {0x000cf1, 0x000cf3,  1}, {0x000cf4, 0x000cff, -1}, {0x000d00, 0x000d01,  0},
    {0x000d02, 0x000d0c,  1}, {0x000d0d, 0x000d0d, -1}, {0x000d0e, 0x000d10,  1},
    {0x000d11, 0x000d11, -1}, {0x000d12, 0x000d3a,  1}, {0x000d3b, 0x000d3c,  0},
    {0x000d3d, 0x000d40,  1}, {0x000d41, 0x000d44,  0}, {0x000d45, 0x000d45, -1},
    {0x000d46, 0x000d48,  1}, {0x000d49, 0x000d49, -1}, {0x000d4a, 0x000d4c,  1},
    {0x000d4d, 0x000d4d,  0}, {0x000d4e, 0x000d4f,  1}, {0x000d50, 0x000d53, -1},
    {0x000d54, 0x000d61,  1}, {0x000d62, 0x000d63,  0}, {0x000d64, 0x000d65, -1},
    {0x000d66, 0x000d7f,  1}, {0x000d80, 0x000d80, -1}, {0x000d81, 0x000d81,  0},
    {0x000d82, 0x000d83,  1}, {0x000d84, 0x000d84, -1}, {0x000d85, 0x000d96,  1},
    {0x000d97, 0x000d99, -1}, {0x000d9a, 0x000db1,  1}, {0x000db2, 0x000db2, -1},
    {0x000db3, 0x000dbb,  1}, {0x000dbc, 0x000dbc, -1}, {0x000dbd, 0x000dbd,  1},
    {0x000dbe, 0x000dbf, -1}, {0x000dc0, 0x000dc6,  1}, {0x000dc7, 0x000dc9, -1},
    {0x000dca, 0x000dca,  0}, {0x000dcb, 0x000dce, -1}, {0x000dcf, 0x000dd1,  1},
    {0x000dd2, 0x000dd4,  0}, {0x000dd5, 0x000dd5, -1}, {0x000dd6, 0x000dd6,  0},
    {0x000dd7, 0x000dd7, -1}, {0x000dd8, 0x000ddf,  1}, {0x000de0, 0x000de5, -1},
    {0x000de6, 0x000def,  1}, {0x000df0, 0x000df1, -1}, {0x000df2, 0x000df4,  1},
    {0x000df5, 0x000e00, -1}, {0x000e01, 0x000e30,  1}, {0x000e31, 0x000e31,  0},
    {0x000e32, 0x000e33,  1}, {0x000e34, 0x000e3a,  0}, {0x000e3b, 0x000e3e, -1},
    {0x000e3f, 0x000e46,  1}, {0x000e47, 0x000e4e,  0}, {0x000e4f, 0x000e5b,  1},
    {0x000e5c, 0x000e80, -1}, {0x000e81, 0x000e82,  1}, {0x000e83, 0x000e83, -1},
    {0x000e84, 0x000e84,  1}, {0x000e85, 0x000e85, -1}, {0x000e86, 0x000e8a,  1},
    {0x000e8b, 0x000e8b, -1}, {0x000e8c, 0x000ea3,  1}, {0x000ea4, 0x000ea4, -1},
    {0x000ea5, 0x000ea5,  1}, {0x000ea6, 0x000ea6, -1}, {0x000ea7, 0x000eb0,  1},
    {0x000eb1, 0x000eb1,  0}, {0x000eb2, 0x000eb3,  1}, {0x000eb4, 0x000ebc,  0},
    {0x000ebd, 0x000ebd,  1}, {0x000ebe, 0x000ebf, -1}, {0x000ec0, 0x000ec4,  1},
    {0x000ec5, 0x000ec5, -1}, {0x000ec6, 0x000ec6,  1}, {0x000ec7, 0x000ec7, -1},
    {0x000ec8, 0x000ece,  0}, {0x000ecf, 0x000ecf, -1}, {0x000ed0, 0x000ed9,  1},
    {0x000eda, 0x000edb, -1}, {0x000edc, 0x000edf,  1}, {0x000ee0, 0x000eff, -1},
    {0x000f00, 0x000f17,  1}, {0x000f18, 0x000f19,  0}, {0x000f1a, 0x000f34,  1},
    {0x000f35, 0x000f35,  0}, {0x000f36, 0x000f36,  1}, {0x000f37, 0x000f37,  0},
    {0x000f38, 0x000f38,  1}, {0x000f39, 0x000f39,  0}, {0x000f3a, 0x000f47,  1},
    {0x000f48, 0x000f48, -1}, {0x000f49, 0x000f6c,  1}, {0x000f6d, 0x000f70, -1},
    {0x000f71, 0x000f7e,  0}, {0x000f7f, 0x000f7f,  1}, {0x000f80, 0x000f84,  0},
    {0x000f85, 0x000f85,  1}, {0x000f86, 0x000f87,  0}, {0x000f88, 0x000f8c,  1},
    {0x000f8d, 0x000f97,  0}, {0x000f98, 0x000f98, -1}, {0x000f99, 0x000fbc,  0},
    {0x000fbd, 0x000fbd, -1}, {0x000fbe, 0x000fc5,  1}, {0x000fc6, 0x000fc6,  0},
    {0x000fc7, 0x000fcc,  1}, {0x000fcd, 0x000fcd, -1}, {0x000fce, 0x000fda,  1},
    {0x000fdb, 0x000fff, -1}, {0x001000, 0x00102c,  1}, {0x00102d, 0x001030,  0},
    {0x001031, 0x001031,  1}, {0x001032, 0x001037,  0}, {0x001038, 0x001038,  1},
    {0x001039, 0x00103a,  0}, {0x00103b, 0x00103c,  1}, {0x00103d, 0x00103e,  0},
    {0x00103f, 0x001057,  1}, {0x001058, 0x001059,  0}, {0x00105a, 0x00105d,  1},
    {0x00105e, 0x001060,  0}, {0x001061, 0x001070,  1}, {0x001071, 0x001074,  0},
    {0x001075, 0x001081,  1}, {0x001082, 0x001082,  0}, {0x001083, 0x001084,  1},
    {0x001085, 0x001086,  0}, {0x001087, 0x00108c,  1}, {0x00108d, 0x00108d,  0},
    {0x00108e, 0x00109c,  1}, {0x00109d, 0x00109d,  0}, {0x00109e, 0x0010c5,  1},
    {0x0010c6, 0x0010c6, -1}, {0x0010c7, 0x0010c7,  1}, {0x0010c8, 0x0010cc, -1},
    {0x0010cd, 0x0010cd,  1}, {0x0010ce, 0x0010cf, -1}, {0x0010d0, 0x0010ff,  1},
    {0x001100, 0x00115f,  2}, {0x001160, 0x0011ff,  0}, {0x001200, 0x001248,  1},
    {0x001249, 0x001249, -1}, {0x00124a, 0x00124d,  1}, {0x00124e, 0x00124f, -1},
    {0x001250, 0x001256,  1}, {0x001257, 0x001257, -1}, {0x001258, 0x001258,  1},
    {0x001259, 0x001259, -1}, {0x00125a, 0x00125d,  1}, {0x00125e, 0x00125f, -1},
    {0x001260, 0x001288,  1}, {0x001289, 0x001289, -1}, {0x00128a, 0x00128d,  1},
    {0x00128e, 0x00128f, -1}, {0x001290, 0x0012b0,  1}, {0x0012b1, 0x0012b1, -1},
    {0x0012b2, 0x0012b5,  1}, {0x0012b6, 0x0012b7, -1}, {0x0012b8, 0x0012be,  1},
    {0x0012bf, 0x0012bf, -1}, {0x0012c0, 0x0012c0,  1}, {0x0012c1, 0x0012c1, -1},
    {0x0012c2, 0x0012c5,  1}, {0x0012c6, 0x0012c7, -1}, {0x0012c8, 0x0012d6,  1},
    {0x0012d7, 0x0012d7, -1}, {0x0012d8, 0x001310,  1}, {0x001311, 0x001311, -1},
    {0x001312, 0x001315,  1}, {0x001316, 0x001317, -1}, {0x001318, 0x00135a,  1},
    {0x00135b, 0x00135c, -1}, {0x00135d, 0x00135f,  0}, {0x001360, 0x00137c,  1},
    {0x00137d, 0x00137f, -1}, {0x001380, 0x001399,  1}, {0x00139a, 0x00139f, -1},
    {0x0013a0, 0x0013f5,  1}, {0x0013f6, 0x0013f7, -1}, {0x0013f8, 0x0013fd,  1},
    {0x0013fe, 0x0013ff, -1}, {0x001400, 0x00169c,  1}, {0x00169d, 0x00169f, -1},
    {0x0016a0, 0x0016f8,  1}, {0x0016f9, 0x0016ff, -1}, {0x001700, 0x001711,  1},
    {0x001712, 0x001714,  0}, {0x001715, 0x001715,  1}, {0x001716, 0x00171e, -1},
    {0x00171f, 0x001731,  1}, {0x001732, 0x001733,  0}, {0x001734, 0x001736,  1},
    {0x001737, 0x00173f, -1}, {0x001740, 0x001751,  1}, {0x001752, 0x001753,  0},
    {0x001754, 0x00175f, -1}, {0x001760, 0x00176c,  1}, {0x00176d, 0x00176d, -1},
    {0x00176e, 0x001770,  1}, {0x001771, 0x001771, -1}, {0x001772, 0x001773,  0},
    {0x001774, 0x00177f, -1}, {0x001780, 0x0017b3,  1}, {0x0017b4, 0x0017b5,  0},
    {0x0017b6, 0x0017b6,  1}, {0x0017b7, 0x0017bd,  0}, {0x0017be, 0x0017c5,  1},
    {0x0017c6, 0x0017c6,  0}, {0x0017c7, 0x0017c8,  1}, {0x0017c9, 0x0017d3,  0},
    {0x0017d4, 0x0017dc,  1}, {0x0017dd, 0x0017dd,  0}, {0x0017de, 0x0017df, -1},
    {0x0017e0, 0x0017e9,  1}, {0x0017ea, 0x0017ef, -1}, {0x0017f0, 0x0017f9,  1},
    {0x0017fa, 0x0017ff, -1}, {0x001800, 0x00180a,  1}, {0x00180b, 0x00180f,  0},
    {0x001810, 0x001819,  1}, {0x00181a, 0x00181f, -1}, {0x001820, 0x001878,  1},
    {0x001879, 0x00187f, -1}, {0x001880, 0x001884,  1}, {0x001885, 0x001886,  0},
    {0x001887, 0x0018a8,  1}, {0x0018a9, 0x0018a9,  0}, {0x0018aa, 0x0018aa,  1},
    {0x0018ab, 0x0018af, -1}, {0x0018b0, 0x0018f5,  1}, {0x0018f6, 0x0018ff, -1},
    {0x001900, 0x00191e,  1}, {0x00191f, 0x00191f, -1}, {0x001920, 0x001922,  0},
    {0x001923, 0x001926,  1}, {0x001927, 0x001928,  0}, {0x001929, 0x00192b,  1},
    {0x00192c, 0x00192f, -1}, {0x001930, 0x001931,  1}, {0x001932, 0x001932,  0},
    {0x001933, 0x001938,  1}, {0x001939, 0x00193b,  0}, {0x00193c, 0x00193f, -1},
    {0x001940, 0x001940,  1}, {0x001941, 0x001943, -1}, {0x001944, 0x00196d,  1},
    {0x00196e, 0x00196f, -1}, {0x001970, 0x001974,  1}, {0x001975, 0x00197f, -1},
    {0x001980, 0x0019ab,  1}, {0x0019ac, 0x0019af, -1}, {0x0019b0, 0x0019c9,  1},
    {0x0019ca, 0x0019cf, -1}, {0x0019d0, 0x0019da,  1}, {0x0019db, 0x0019dd, -1},
    {0x0019de, 0x001a16,  1}, {0x001a17, 0x001a18,  0}, {0x001a19, 0x001a1a,  1},
    {0x001a1b, 0x001a1b,  0}, {0x001a1c, 0x001a1d, -1}, {0x001a1e, 0x001a55,  1},
    {0x001a56, 0x001a56,  0}, {0x001a57, 0x001a57,  1}, {0x001a58, 0x001a5e,  0},
    {0x001a5f, 0x001a5f, -1}, {0x001a60, 0x001a60,  0}, {0x001a61, 0x001a61,  1},
    {0x001a62, 0x001a62,  0}, {0x001a63, 0x001a64,  1}, {0x001a65, 0x001a6c,  0},
    {0x001a6d, 0x001a72,  1}, {0x001a73, 0x001a7c,  0}, {0x001a7d, 0x001a7e, -1},
    {0x001a7f, 0x001a7f,  0}, {0x001a80, 0x001a89,  1}, {0x001a8a, 0x001a8f, -1},
    {0x001a90, 0x001a99,  1}, {0x001a9a, 0x001a9f, -1}, {0x001aa0, 0x001aad,  1},
    {0x001aae, 0x001aaf, -1}, {0x001ab0, 0x001ace,  0}, {0x001acf, 0x001aff, -1},
    {0x001b00, 0x001b03,  0}, {0x001b04, 0x001b33,  1}, {0x001b34, 0x001b34,  0},
    {0x001b35, 0x001b35,  1}, {0x001b36, 0x001b3a,  0}, {0x001b3b, 0x001b3b,  1},
    {0x001b3c, 0x001b3c,  0}, {0x001b3d, 0x001b41,  1}, {0x001b42, 0x001b42,  0},
    {0x001b43, 0x001b4c,  1}, {0x001b4d, 0x001b4d, -1}, {0x001b4e, 0x001b6a,  1},
    {0x001b6b, 0x001b73,  0}, {0x001b74, 0x001b7f,  1}, {0x001b80, 0x001b81,  0},
    {0x001b82, 0x001ba1,  1}, {0x001ba2, 0x001ba5,  0}, {0x001ba6, 0x001ba7,  1},
    {0x001ba8, 0x001ba9,  0}, {0x001baa, 0x001baa,  1}, {0x001bab, 0x001bad,  0},
    {0x001bae, 0x001be5,  1}, {0x001be6, 0x001be6,  0}, {0x001be7, 0x001be7,  1},
    {0x001be8, 0x001be9,  0}, {0x001bea, 0x001bec,  1}, {0x001bed, 0x001bed,  0},
    {0x001bee, 0x001bee,  1}, {0x001bef, 0x001bf1,  0}, {0x001bf2, 0x001bf3,  1},
    {0x001bf4, 0x001bfb, -1}, {0x001bfc, 0x001c2b,  1}, {0x001c2c, 0x001c33,  0},
    {0x001c34, 0x001c35,  1}, {0x001c36, 0x001c37,  0}, {0x001c38, 0x001c3a, -1},
    {0x001c3b, 0x001c49,  1}, {0x001c4a, 0x001c4c, -1}, {0x001c4d, 0x001c8a,  1},
    {0x001c8b, 0x001c8f, -1}, {0x001c90, 0x001cba,  1}, {0x001cbb, 0x001cbc, -1},
    {0x001cbd, 0x001cc7,  1}, {0x001cc8, 0x001ccf, -1}, {0x001cd0, 0x001cd2,  0},
    {0x001cd3, 0x001cd3,  1}, {0x001cd4, 0x001ce0,  0}, {0x001ce1, 0x001ce1,  1},
    {0x001ce2, 0x001ce8,  0}, {0x001ce9, 0x001cec,  1}, {0x001ced, 0x001ced,  0},
    {0x001cee, 0x001cf3,  1}, {0x001cf4, 0x001cf4,  0}, {0x001cf5, 0x001cf7,  1},
    {0x001cf8, 0x001cf9,  0}, {0x001cfa, 0x001cfa,  1}, {0x001cfb, 0x001cff, -1},
    {0x001d00, 0x001dbf,  1}, {0x001dc0, 0x001dff,  0}, {0x001e00, 0x001f15,  1},
    {0x001f16, 0x001f17, -1}, {0x001f18, 0x001f1d,  1}, {0x001f1e, 0x001f1f, -1},
    {0x001f20, 0x001f45,  1}, {0x001f46, 0x001f47, -1}, {0x001f48, 0x001f4d,  1},
    {0x001f4e, 0x001f4f, -1}, {0x001f50, 0x001f57,  1}, {0x001f58, 0x001f58, -1},
    {0x001f59, 0x001f59,  1}, {0x001f5a, 0x001f5a, -1}, {0x001f5b, 0x001f5b,  1},
    {0x001f5c, 0x001f5c, -1}, {0x001f5d, 0x001f5d,  1}, {0x001f5e, 0x001f5e, -1},
    {0x001f5f, 0x001f7d,  1}, {0x001f7e, 0x001f7f, -1}, {0x001f80, 0x001fb4,  1},
    {0x001fb5, 0x001fb5, -1}, {0x001fb6, 0x001fc4,  1}, {0x001fc5, 0x001fc5, -1},
    {0x001fc6, 0x001fd3,  1}, {0x001fd4, 0x001fd5, -1}, {0x001fd6, 0x001fdb,  1},
    {0x001fdc, 0x001fdc, -1}, {0x001fdd, 0x001fef,  1}, {0x001ff0, 0x001ff1, -1},
    {0x001ff2, 0x001ff4,  1}, {0x001ff5, 0x001ff5, -1}, {0x001ff6, 0x001ffe,  1},
    {0x001fff, 0x001fff, -1}, {0x002000, 0x00200a,  1}, {0x00200b, 0x00200f,  0},
    {0x002010, 0x002027,  1}, {0x002028, 0x002029, -1}, {0x00202a, 0x00202e,  0},
    {0x00202f, 0x00205f,  1}, {0x002060, 0x002064,  0}, {0x002065, 0x002065, -1},
    {0x002066, 0x00206f,  0}, {0x002070, 0x002071,  1}, {0x002072, 0x002073, -1},
    {0x002074, 0x00208e,  1}, {0x00208f, 0x00208f, -1}, {0x002090, 0x00209c,  1},
    {0x00209d, 0x00209f, -1}, {0x0020a0, 0x0020c0,  1}, {0x0020c1, 0x0020cf, -1},
    {0x0020d0, 0x0020f0,  0}, {0x0020f1, 0x0020ff, -1}, {0x002100, 0x00218b,  1},
    {0x00218c, 0x00218f, -1}, {0x002190, 0x002319,  1}, {0x00231a, 0x00231b,  2},
    {0x00231c, 0x002328,  1}, {0x002329, 0x00232a,  2}, {0x00232b, 0x0023e8,  1},
    {0x0023e9, 0x0023ec,  2}, {0x0023ed, 0x0023ef,  1}, {0x0023f0, 0x0023f0,  2},
    {0x0023f1, 0x0023f2,  1}, {0x0023f3, 0x0023f3,  2}, {0x0023f4, 0x002429,  1},
    {0x00242a, 0x00243f, -1}, {0x002440, 0x00244a,  1}, {0x00244b, 0x00245f, -1},
    {0x002460, 0x0025fc,  1}, {0x0025fd, 0x0025fe,  2}, {0x0025ff, 0x002613,  1},
    {0x002614, 0x002615,  2}, {0x002616, 0x00262f,  1}, {0x002630, 0x002637,  2},
    {0x002638, 0x002647,  1}, {0x002648, 0x002653,  2}, {0x002654, 0x00267e,  1},
    {0x00267f, 0x00267f,  2}, {0x002680, 0x002689,  1}, {0x00268a, 0x00268f,  2},
    {0x002690, 0x002692,  1}, {0x002693, 0x002693,  2}, {0x002694, 0x0026a0,  1},
    {0x0026a1, 0x0026a1,  2}, {0x0026a2, 0x0026a9,  1}, {0x0026aa, 0x0026ab,  2},
    {0x0026ac, 0x0026bc,  1}, {0x0026bd, 0x0026be,  2}, {0x0026bf, 0x0026c3,  1},
    {0x0026c4, 0x0026c5,  2}, {0x0026c6, 0x0026cd,  1}, {0x0026ce, 0x0026ce,  2},
    {0x0026cf, 0x0026d3,  1}, {0x0026d4, 0x0026d4,  2}, {0x0026d5, 0x0026e9,  1},
    {0x0026ea, 0x0026ea,  2}, {0x0026eb, 0x0026f1,  1}, {0x0026f2, 0x0026f3,  2},
    {0x0026f4, 0x0026f4,  1}, {0x0026f5, 0x0026f5,  2}, {0x0026f6, 0x0026f9,  1},
    {0x0026fa, 0x0026fa,  2}, {0x0026fb, 0x0026fc,  1}, {0x0026fd, 0x0026fd,  2},
    {0x0026fe, 0x002704,  1}, {0x002705, 0x002705,  2}, {0x002706, 0x002709,  1},
    {0x00270a, 0x00270b,  2}, {0x00270c, 0x002727,  1}, {0x002728, 0x002728,  2},
    {0x002729, 0x00274b,  1}, {0x00274c, 0x00274c,  2}, {0x00274d, 0x00274d,  1},
    {0x00274e, 0x00274e,  2}, {0x00274f, 0x002752,  1}, {0x002753, 0x002755,  2},
    {0x002756, 0x002756,  1}, {0x002757, 0x002757,  2}, {0x002758, 0x002794,  1},
    {0x002795, 0x002797,  2}, {0x002798, 0x0027af,  1}, {0x0027b0, 0x0027b0,  2},
    {0x0027b1, 0x0027be,  1}, {0x0027bf, 0x0027bf,  2}, {0x0027c0, 0x002b1a,  1},
    {0x002b1b, 0x002b1c,  2}, {0x002b1d, 0x002b4f,  1}, {0x002b50, 0x002b50,  2},
    {0x002b51, 0x002b54,  1}, {0x002b55, 0x002b55,  2}, {0x002b56, 0x002b73,  1},
    {0x002b74, 0x002b75, -1}, {0x002b76, 0x002b95,  1}, {0x002b96, 0x002b96, -1},
    {0x002b97, 0x002cee,  1}, {0x002cef, 0x002cf1,  0}, {0x002cf2, 0x002cf3,  1},
    {0x002cf4, 0x002cf8, -1}, {0x002cf9, 0x002d25,  1}, {0x002d26, 0x002d26, -1},
    {0x002d27, 0x002d27,  1}, {0x002d28, 0x002d2c, -1}, {0x002d2d, 0x002d2d,  1},
    {0x002d2e, 0x002d2f, -1}, {0x002d30, 0x002d67,  1}, {0x002d68, 0x002d6e, -1},
    {0x002d6f, 0x002d70,  1}, {0x002d71, 0x002d7e, -1}, {0x002d7f, 0x002d7f,  0},
    {0x002d80, 0x002d96,  1}, {0x002d97, 0x002d9f, -1}, {0x002da0, 0x002da6,  1},
    {0x002da7, 0x002da7, -1}, {0x002da8, 0x002dae,  1}, {0x002daf, 0x002daf, -1},
    {0x002db0, 0x002db6,  1}, {0x002db7, 0x002db7, -1}, {0x002db8, 0x002dbe,  1},
    {0x002dbf, 0x002dbf, -1}, {0x002dc0, 0x002dc6,  1}, {0x002dc7, 0x002dc7, -1},
    {0x002dc8, 0x002dce,  1}, {0x002dcf, 0x002dcf, -1}, {0x002dd0, 0x002dd6,  1},
    {0x002dd7, 0x002dd7, -1}, {0x002dd8, 0x002dde,  1}, {0x002ddf, 0x002ddf, -1},
    {0x002de0, 0x002dff,  0}, {0x002e00, 0x002e5d,  1}, {0x002e5e, 0x002e7f, -1},
    {0x002e80, 0x002e99,  2}, {0x002e9a, 0x002e9a, -1}, {0x002e9b, 0x002ef3,  2},
    {0x002ef4, 0x002eff, -1}, {0x002f00, 0x002fd5,  2}, {0x002fd6, 0x002fef, -1},
    {0x002ff0, 0x003029,  2}, {0x00302a, 0x00302d,  0}, {0x00302e, 0x00303e,  2},
    {0x00303f, 0x00303f,  1}, {0x003040, 0x003040, -1}, {0x003041, 0x003096,  2},
    {0x003097, 0x003098, -1}, {0x003099, 0x00309a,  0}, {0x00309b, 0x0030ff,  2},
    {0x003100, 0x003104, -1}, {0x003105, 0x00312f,  2}, {0x003130, 0x003130, -1},
    {0x003131, 0x003163,  2}, {0x003164, 0x003164,  0}, {0x003165, 0x00318e,  2},
    {0x00318f, 0x00318f, -1}, {0x003190, 0x0031e5,  2}, {0x0031e6, 0x0031ee, -1},
    {0x0031ef, 0x00321e,  2}, {0x00321f, 0x00321f, -1}, {0x003220, 0x00a48c,  2},
    {0x00a48d, 0x00a48f, -1}, {0x00a490, 0x00a4c6,  2}, {0x00a4c7, 0x00a4cf, -1},
    {0x00a4d0, 0x00a62b,  1}, {0x00a62c, 0x00a63f, -1}, {0x00a640, 0x00a66e,  1},
    {0x00a66f, 0x00a672,  0}, {0x00a673, 0x00a673,  1}, {0x00a674, 0x00a67d,  0},
    {0x00a67e, 0x00a69d,  1}, {0x00a69e, 0x00a69f,  0}, {0x00a6a0, 0x00a6ef,  1},
    {0x00a6f0, 0x00a6f1,  0}, {0x00a6f2, 0x00a6f7,  1}, {0x00a6f8, 0x00a6ff, -1},
    {0x00a700, 0x00a7cd,  1}, {0x00a7ce, 0x00a7cf, -1}, {0x00a7d0, 0x00a7d1,  1},
    {0x00a7d2, 0x00a7d2, -1}, {0x00a7d3, 0x00a7d3,  1}, {0x00a7d4, 0x00a7d4, -1},
    {0x00a7d5, 0x00a7dc,  1}, {0x00a7dd, 0x00a7f1, -1}, {0x00a7f2, 0x00a801,  1},
    {0x00a802, 0x00a802,  0}, {0x00a803, 0x00a805,  1}, {0x00a806, 0x00a806,  0},
    {0x00a807, 0x00a80a,  1}, {0x00a80b, 0x00a80b,  0}, {0x00a80c, 0x00a824,  1},
    {0x00a825, 0x00a826,  0}, {0x00a827, 0x00a82b,  1}, {0x00a82c, 0x00a82c,  0},
    {0x00a82d, 0x00a82f, -1}, {0x00a830, 0x00a839,  1}, {0x00a83a, 0x00a83f, -1},
    {0x00a840, 0x00a877,  1}, {0x00a878, 0x00a87f, -1}, {0x00a880, 0x00a8c3,  1},
    {0x00a8c4, 0x00a8c5,  0}, {0x00a8c6, 0x00a8cd, -1}, {0x00a8ce, 0x00a8d9,  1},
    {0x00a8da, 0x00a8df, -1}, {0x00a8e0, 0x00a8f1,  0}, {0x00a8f2, 0x00a8fe,  1},
    {0x00a8ff, 0x00a8ff,  0}, {0x00a900, 0x00a925,  1}, {0x00a926, 0x00a92d,  0},
    {0x00a92e, 0x00a946,  1}, {0x00a947, 0x00a951,  0}, {0x00a952, 0x00a953,  1},
    {0x00a954, 0x00a95e, -1}, {0x00a95f, 0x00a95f,  1}, {0x00a960, 0x00a97c,  2},
    {0x00a97d, 0x00a97f, -1}, {0x00a980, 0x00a982,  0}, {0x00a983, 0x00a9b2,  1},
    {0x00a9b3, 0x00a9b3,  0}, {0x00a9b4, 0x00a9b5,  1}, {0x00a9b6, 0x00a9b9,  0},
    {0x00a9ba, 0x00a9bb,  1}, {0x00a9bc, 0x00a9bd,  0}, {0x00a9be, 0x00a9cd,  1},
    {0x00a9ce, 0x00a9ce, -1}, {0x00a9cf, 0x00a9d9,  1}, {0x00a9da, 0x00a9dd, -1},
    {0x00a9de, 0x00a9e4,  1}, {0x00a9e5, 0x00a9e5,  0}, {0x00a9e6, 0x00a9fe,  1},
    {0x00a9ff, 0x00a9ff, -1}, {0x00aa00, 0x00aa28,  1}, {0x00aa29, 0x00aa2e,  0},
    {0x00aa2f, 0x00aa30,  1}, {0x00aa31, 0x00aa32,  0}, {0x00aa33, 0x00aa34,  1},
    {0x00aa35, 0x00aa36,  0}, {0x00aa37, 0x00aa3f, -1}, {0x00aa40, 0x00aa42,  1},
    {0x00aa43, 0x00aa43,  0}, {0x00aa44, 0x00aa4b,  1}, {0x00aa4c, 0x00aa4c,  0},
    {0x00aa4d, 0x00aa4d,  1}, {0x00aa4e, 0x00aa4f, -1}, {0x00aa50, 0x00aa59,  1},
    {0x00aa5a, 0x00aa5b, -1}, {0x00aa5c, 0x00aa7b,  1}, {0x00aa7c, 0x00aa7c,  0},
    {0x00aa7d, 0x00aaaf,  1}, {0x00aab0, 0x00aab0,  0}, {0x00aab1, 0x00aab1,  1},
    {0x00aab2, 0x00aab4,  0}, {0x00aab5, 0x00aab6,  1}, {0x00aab7, 0x00aab8,  0},
    {0x00aab9, 0x00aabd,  1}, {0x00aabe, 0x00aabf,  0}, {0x00aac0, 0x00aac0,  1},
    {0x00aac1, 0x00aac1,  0}, {0x00aac2, 0x00aac2,  1}, {0x00aac3, 0x00aada, -1},
    {0x00aadb, 0x00aaeb,  1}, {0x00aaec, 0x00aaed,  0}, {0x00aaee, 0x00aaf5,  1},
    {0x00aaf6, 0x00aaf6,  0}, {0x00aaf7, 0x00ab00, -1}, {0x00ab01, 0x00ab06,  1},
    {0x00ab07, 0x00ab08, -1}, {0x00ab09, 0x00ab0e,  1}, {0x00ab0f, 0x00ab10, -1},
    {0x00ab11, 0x00ab16,  1}, {0x00ab17, 0x00ab1f, -1}, {0x00ab20, 0x00ab26,  1},
    {0x00ab27, 0x00ab27, -1}, {0x00ab28, 0x00ab2e,  1}, {0x00ab2f, 0x00ab2f, -1},
    {0x00ab30, 0x00ab6b,  1}, {0x00ab6c, 0x00ab6f, -1}, {0x00ab70, 0x00abe4,  1},
    {0x00abe5, 0x00abe5,  0}, {0x00abe6, 0x00abe7,  1}, {0x00abe8, 0x00abe8,  0},
    {0x00abe9, 0x00abec,  1}, {0x00abed, 0x00abed,  0}, {0x00abee, 0x00abef, -1},
    {0x00abf0, 0x00abf9,  1}, {0x00abfa, 0x00abff, -1}, {0x00ac00, 0x00d7a3,  2},
    {0x00d7a4, 0x00d7af, -1}, {0x00d7b0, 0x00d7c6,  0}, {0x00d7c7, 0x00d7ca, -1},
    {0x00d7cb, 0x00d7fb,  0}, {0x00d7fc, 0x00dfff, -1}, {0x00e000, 0x00f8ff,  1},
    {0x00f900, 0x00fa6d,  2}, {0x00fa6e, 0x00fa6f, -1}, {0x00fa70, 0x00fad9,  2},
    {0x00fada, 0x00faff, -1}, {0x00fb00, 0x00fb06,  1}, {0x00fb07, 0x00fb12, -1},
    {0x00fb13, 0x00fb17,  1}, {0x00fb18, 0x00fb1c, -1}, {0x00fb1d, 0x00fb1d,  1},
    {0x00fb1e, 0x00fb1e,  0}, {0x00fb1f, 0x00fb36,  1}, {0x00fb37, 0x00fb37, -1},
    {0x00fb38, 0x00fb3c,  1}, {0x00fb3d, 0x00fb3d, -1}, {0x00fb3e, 0x00fb3e,  1},
    {0x00fb3f, 0x00fb3f, -1}, {0x00fb40, 0x00fb41,  1}, {0x00fb42, 0x00fb42, -1},
    {0x00fb43, 0x00fb44,  1}, {0x00fb45, 0x00fb45, -1}, {0x00fb46, 0x00fbc2,  1},
    {0x00fbc3, 0x00fbd2, -1}, {0x00fbd3, 0x00fd8f,  1}, {0x00fd90, 0x00fd91, -1},
    {0x00fd92, 0x00fdc7,  1}, {0x00fdc8, 0x00fdce, -1}, {0x00fdcf, 0x00fdcf,  1},
    {0x00fdd0, 0x00fdef, -1}, {0x00fdf0, 0x00fdff,  1}, {0x00fe00, 0x00fe0f,  0},
    {0x00fe10, 0x00fe19,  2}, {0x00fe1a, 0x00fe1f, -1}, {0x00fe20, 0x00fe2f,  0},
    {0x00fe30, 0x00fe52,  2}, {0x00fe53, 0x00fe53, -1}, {0x00fe54, 0x00fe66,  2},
    {0x00fe67, 0x00fe67, -1}, {0x00fe68, 0x00fe6b,  2}, {0x00fe6c, 0x00fe6f, -1},
    {0x00fe70, 0x00fe74,  1}, {0x00fe75, 0x00fe75, -1}, {0x00fe76, 0x00fefc,  1},
    {0x00fefd, 0x00fefe, -1}, {0x00feff, 0x00feff,  0}, {0x00ff00, 0x00ff00, -1},
    {0x00ff01, 0x00ff60,  2}, {0x00ff61, 0x00ff9f,  1}, {0x00ffa0, 0x00ffa0,  0},
    {0x00ffa1, 0x00ffbe,  1}, {0x00ffbf, 0x00ffc1, -1}, {0x00ffc2, 0x00ffc7,  1},
    {0x00ffc8, 0x00ffc9, -1}, {0x00ffca, 0x00ffcf,  1}, {0x00ffd0, 0x00ffd1, -1},
    {0x00ffd2, 0x00ffd7,  1}, {0x00ffd8, 0x00ffd9, -1}, {0x00ffda, 0x00ffdc,  1},
    {0x00ffdd, 0x00ffdf, -1}, {0x00ffe0, 0x00ffe6,  2}, {0x00ffe7, 0x00ffe7, -1},
    {0x00ffe8, 0x00ffee,  1}, {0x00ffef, 0x00fff8, -1}, {0x00fff9, 0x00fffd,  1},
    {0x00fffe, 0x00ffff, -1}, {0x010000, 0x01000b,  1}, {0x01000c, 0x01000c, -1},
    {0x01000d, 0x010026,  1}, {0x010027, 0x010027, -1}, {0x010028, 0x01003a,  1},
    {0x01003b, 0x01003b, -1}, {0x01003c, 0x01003d,  1}, {0x01003e, 0x01003e, -1},
    {0x01003f, 0x01004d,  1}, {0x01004e, 0x01004f, -1}, {0x010050, 0x01005d,  1},
    {0x01005e, 0x01007f, -1}, {0x010080, 0x0100fa,  1}, {0x0100fb, 0x0100ff, -1},
    {0x010100, 0x010102,  1}, {0x010103, 0x010106, -1}, {0x010107, 0x010133,  1},
    {0x010134, 0x010136, -1}, {0x010137, 0x01018e,  1}, {0x01018f, 0x01018f, -1},
    {0x010190, 0x01019c,  1}, {0x01019d, 0x01019f, -1}, {0x0101a0, 0x0101a0,  1},
    {0x0101a1, 0x0101cf, -1}, {0x0101d0, 0x0101fc,  1}, {0x0101fd, 0x0101fd,  0},
    {0x0101fe, 0x01027f, -1}, {0x010280, 0x01029c,  1}, {0x01029d, 0x01029f, -1},
    {0x0102a0, 0x0102d0,  1}, {0x0102d1, 0x0102df, -1}, {0x0102e0, 0x0102e0,  0},
    {0x0102e1, 0x0102fb,  1}, {0x0102fc, 0x0102ff, -1}, {0x010300, 0x010323,  1},
    {0x010324, 0x01032c, -1}, {0x01032d, 0x01034a,  1}, {0x01034b, 0x01034f, -1},
    {0x010350, 0x010375,  1}, {0x010376, 0x01037a,  0}, {0x01037b, 0x01037f, -1},
    {0x010380, 0x01039d,  1}, {0x01039e, 0x01039e, -1}, {0x01039f, 0x0103c3,  1},
    {0x0103c4, 0x0103c7, -1}, {0x0103c8, 0x0103d5,  1}, {0x0103d6, 0x0103ff, -1},
    {0x010400, 0x01049d,  1}, {0x01049e, 0x01049f, -1}, {0x0104a0, 0x0104a9,  1},
    {0x0104aa, 0x0104af, -1}, {0x0104b0, 0x0104d3,  1}, {0x0104d4, 0x0104d7, -1},
    {0x0104d8, 0x0104fb,  1}, {0x0104fc, 0x0104ff, -1}, {0x010500, 0x010527,  1},
    {0x010528, 0x01052f, -1}, {0x010530, 0x010563,  1}, {0x010564, 0x01056e, -1},
    {0x01056f, 0x01057a,  1}, {0x01057b, 0x01057b, -1}, {0x01057c, 0x01058a,  1},
    {0x01058b, 0x01058b, -1}, {0x01058c, 0x010592,  1}, {0x010593, 0x010593, -1},
    {0x010594, 0x010595,  1}, {0x010596, 0x010596, -1}, {0x010597, 0x0105a1,  1},
    {0x0105a2, 0x0105a2, -1}, {0x0105a3, 0x0105b1,  1}, {0x0105b2, 0x0105b2, -1},
    {0x0105b3, 0x0105b9,  1}, {0x0105ba, 0x0105ba, -1}, {0x0105bb, 0x0105bc,  1},
    {0x0105bd, 0x0105bf, -1}, {0x0105c0, 0x0105f3,  1}, {0x0105f4, 0x0105ff, -1},
    {0x010600, 0x010736,  1}, {0x010737, 0x01073f, -1}, {0x010740, 0x010755,  1},
    {0x010756, 0x01075f, -1}, {0x010760, 0x010767,  1}, {0x010768, 0x01077f, -1},
    {0x010780, 0x010785,  1}, {0x010786, 0x010786, -1}, {0x010787, 0x0107b0,  1},
    {0x0107b1, 0x0107b1, -1}, {0x0107b2, 0x0107ba,  1}, {0x0107bb, 0x0107ff, -1},
    {0x010800, 0x010805,  1}, {0x010806, 0x010807, -1}, {0x010808, 0x010808,  1},
    {0x010809, 0x010809, -1}, {0x01080a, 0x010835,  1}, {0x010836, 0x010836, -1},
    {0x010837, 0x010838,  1}, {0x010839, 0x01083b, -1}, {0x01083c, 0x01083c,  1},
    {0x01083d, 0x01083e, -1}, {0x01083f, 0x010855,  1}, {0x010856, 0x010856, -1},
    {0x010857, 0x01089e,  1}, {0x01089f, 0x0108a6, -1}, {0x0108a7, 0x0108af,  1},
    {0x0108b0, 0x0108df, -1}, {0x0108e0, 0x0108f2,  1}, {0x0108f3, 0x0108f3, -1},
    {0x0108f4, 0x0108f5,  1}, {0x0108f6, 0x0108fa, -1}, {0x0108fb, 0x01091b,  1},
    {0x01091c, 0x01091e, -1}, {0x01091f, 0x010939,  1}, {0x01093a, 0x01093e, -1},
    {0x01093f, 0x01093f,  1}, {0x010940, 0x01097f, -1}, {0x010980, 0x0109b7,  1},
    {0x0109b8, 0x0109bb, -1}, {0x0109bc, 0x0109cf,  1}, {0x0109d0, 0x0109d1, -1},
    {0x0109d2, 0x010a00,  1}, {0x010a01, 0x010a03,  0}, {0x010a04, 0x010a04, -1},
    {0x010a05, 0x010a06,  0}, {0x010a07, 0x010a0b, -1}, {0x010a0c, 0x010a0f,  0},
    {0x010a10, 0x010a13,  1}, {0x010a14, 0x010a14, -1}, {0x010a15, 0x010a17,  1},
    {0x010a18, 0x010a18, -1}, {0x010a19, 0x010a35,  1}, {0x010a36, 0x010a37, -1},
    {0x010a38, 0x010a3a,  0}, {0x010a3b, 0x010a3e, -1}, {0x010a3f, 0x010a3f,  0},
    {0x010a40, 0x010a48,  1}, {0x010a49, 0x010a4f, -1}, {0x010a50, 0x010a58,  1},
    {0x010a59, 0x010a5f, -1}, {0x010a60, 0x010a9f,  1}, {0x010aa0, 0x010abf, -1},
    {0x010ac0, 0x010ae4,  1}, {0x010ae5, 0x010ae6,  0}, {0x010ae7, 0x010aea, -1},
    {0x010aeb, 0x010af6,  1}, {0x010af7, 0x010aff, -1}, {0x010b00, 0x010b35,  1},
    {0x010b36, 0x010b38, -1}, {0x010b39, 0x010b55,  1}, {0x010b56, 0x010b57, -1},
    {0x010b58, 0x010b72,  1}, {0x010b73, 0x010b77, -1}, {0x010b78, 0x010b91,  1},
    {0x010b92, 0x010b98, -1}, {0x010b99, 0x010b9c,  1}, {0x010b9d, 0x010ba8, -1},
    {0x010ba9, 0x010baf,  1}, {0x010bb0, 0x010bff, -1}, {0x010c00, 0x010c48,  1},
    {0x010c49, 0x010c7f, -1}, {0x010c80, 0x010cb2,  1}, {0x010cb3, 0x010cbf, -1},
    {0x010cc0, 0x010cf2,  1}, {0x010cf3, 0x010cf9, -1}, {0x010cfa, 0x010d23,  1},
    {0x010d24, 0x010d27,  0}, {0x010d28, 0x010d2f, -1}, {0x010d30, 0x010d39,  1},
    {0x010d3a, 0x010d3f, -1}, {0x010d40, 0x010d65,  1}, {0x010d66, 0x010d68, -1},
    {0x010d69, 0x010d6d,  0}, {0x010d6e, 0x010d85,  1}, {0x010d86, 0x010d8d, -1},
    {0x010d8e, 0x010d8f,  1}, {0x010d90, 0x010e5f, -1}, {0x010e60, 0x010e7e,  1},
    {0x010e7f, 0x010e7f, -1}, {0x010e80, 0x010ea9,  1}, {0x010eaa, 0x010eaa, -1},
    {0x010eab, 0x010eac,  0}, {0x010ead, 0x010ead,  1}, {0x010eae, 0x010eaf, -1},
    {0x010eb0, 0x010eb1,  1}, {0x010eb2, 0x010ec1, -1}, {0x010ec2, 0x010ec4,  1},
    {0x010ec5, 0x010efb, -1}, {0x010efc, 0x010eff,  0}, {0x010f00, 0x010f27,  1},
    {0x010f28, 0x010f2f, -1}, {0x010f30, 0x010f45,  1}, {0x010f46, 0x010f50,  0},
    {0x010f51, 0x010f59,  1}, {0x010f5a, 0x010f6f, -1}, {0x010f70, 0x010f81,  1},
    {0x010f82, 0x010f85,  0}, {0x010f86, 0x010f89,  1}, {0x010f8a, 0x010faf, -1},
    {0x010fb0, 0x010fcb,  1}, {0x010fcc, 0x010fdf, -1}, {0x010fe0, 0x010ff6,  1},
    {0x010ff7, 0x010fff, -1}, {0x011000, 0x011000,  1}, {0x011001, 0x011001,  0},
    {0x011002, 0x011037,  1}, {0x011038, 0x011046,  0}, {0x011047, 0x01104d,  1},
    {0x01104e, 0x011051, -1}, {0x011052, 0x01106f,  1}, {0x011070, 0x011070,  0},
    {0x011071, 0x011072,  1}, {0x011073, 0x011074,  0}, {0x011075, 0x011075,  1},
    {0x011076, 0x01107e, -1}, {0x01107f, 0x011081,  0}, {0x011082, 0x0110b2,  1},
    {0x0110b3, 0x0110b6,  0}, {0x0110b7, 0x0110b8,  1}, {0x0110b9, 0x0110ba,  0},
    {0x0110bb, 0x0110c1,  1}, {0x0110c2, 0x0110c2,  0}, {0x0110c3, 0x0110cc, -1},
    {0x0110cd, 0x0110cd,  1}, {0x0110ce, 0x0110cf, -1}, {0x0110d0, 0x0110e8,  1},
    {0x0110e9, 0x0110ef, -1}, {0x0110f0, 0x0110f9,  1}, {0x0110fa, 0x0110ff, -1},
    {0x011100, 0x011102,  0}, {0x011103, 0x011126,  1}, {0x011127, 0x01112b,  0},
    {0x01112c, 0x01112c,  1}, {0x01112d, 0x011134,  0}, {0x011135, 0x011135, -1},
    {0x011136, 0x011147,  1}, {0x011148, 0x01114f, -1}, {0x011150, 0x011172,  1},
    {0x011173, 0x011173,  0}, {0x011174, 0x011176,  1}, {0x011177, 0x01117f, -1},
    {0x011180, 0x011181,  0}, {0x011182, 0x0111b5,  1}, {0x0111b6, 0x0111be,  0},
    {0x0111bf, 0x0111c8,  1}, {0x0111c9, 0x0111cc,  0}, {0x0111cd, 0x0111ce,  1},
    {0x0111cf, 0x0111cf,  0}, {0x0111d0, 0x0111df,  1}, {0x0111e0, 0x0111e0, -1},
    {0x0111e1, 0x0111f4,  1}, {0x0111f5, 0x0111ff, -1}, {0x011200, 0x011211,  1},
    {0x011212, 0x011212, -1}, {0x011213, 0x01122e,  1}, {0x01122f, 0x011231,  0},
    {0x011232, 0x011233,  1}, {0x011234, 0x011234,  0}, {0x011235, 0x011235,  1},
    {0x011236, 0x011237,  0}, {0x011238, 0x01123d,  1}, {0x01123e, 0x01123e,  0},
    {0x01123f, 0x011240,  1}, {0x011241, 0x011241,  0}, {0x011242, 0x01127f, -1},
    {0x011280, 0x011286,  1}, {0x011287, 0x011287, -1}, {0x011288, 0x011288,  1},
    {0x011289, 0x011289, -1}, {0x01128a, 0x01128d,  1}, {0x01128e, 0x01128e, -1},
    {0x01128f, 0x01129d,  1}, {0x01129e, 0x01129e, -1}, {0x01129f, 0x0112a9,  1},
    {0x0112aa, 0x0112af, -1}, {0x0112b0, 0x0112de,  1}, {0x0112df, 0x0112df,  0},
    {0x0112e0, 0x0112e2,  1}, {0x0112e3, 0x0112ea,  0}, {0x0112eb, 0x0112ef, -1},
    {0x0112f0, 0x0112f9,  1}, {0x0112fa, 0x0112ff, -1}, {0x011300, 0x011301,  0},
    {0x011302, 0x011303,  1}, {0x011304, 0x011304, -1}, {0x011305, 0x01130c,  1},
    {0x01130d, 0x01130e, -1}, {0x01130f, 0x011310,  1}, {0x011311, 0x011312, -1},
    {0x011313, 0x011328,  1}, {0x011329, 0x011329, -1}, {0x01132a, 0x011330,  1},
    {0x011331, 0x011331, -1}, {0x011332, 0x011333,  1}, {0x011334, 0x011334, -1},
    {0x011335, 0x011339,  1}, {0x01133a, 0x01133a, -1}, {0x01133b, 0x01133c,  0},
    {0x01133d, 0x01133f,  1}, {0x011340, 0x011340,  0}, {0x011341, 0x011344,  1},
    {0x011345, 0x011346, -1}, {0x011347, 0x011348,  1}, {0x011349, 0x01134a, -1},
    {0x01134b, 0x01134d,  1}, {0x01134e, 0x01134f, -1}, {0x011350, 0x011350,  1},
    {0x011351, 0x011356, -1}, {0x011357, 0x011357,  1}, {0x011358, 0x01135c, -1},
    {0x01135d, 0x011363,  1}, {0x011364, 0x011365, -1}, {0x011366, 0x01136c,  0},
    {0x01136d, 0x01136f, -1}, {0x011370, 0x011374,  0}, {0x011375, 0x01137f, -1},
    {0x011380, 0x011389,  1}, {0x01138a, 0x01138a, -1}, {0x01138b, 0x01138b,  1},
    {0x01138c, 0x01138d, -1}, {0x01138e, 0x01138e,  1}, {0x01138f, 0x01138f, -1},
    {0x011390, 0x0113b5,  1}, {0x0113b6, 0x0113b6, -1}, {0x0113b7, 0x0113ba,  1},
    {0x0113bb, 0x0113c0,  0}, {0x0113c1, 0x0113c1, -1}, {0x0113c2, 0x0113c2,  1},
    {0x0113c3, 0x0113c4, -1}, {0x0113c5, 0x0113c5,  1}, {0x0113c6, 0x0113c6, -1},
    {0x0113c7, 0x0113ca,  1}, {0x0113cb, 0x0113cb, -1}, {0x0113cc, 0x0113cd,  1},
    {0x0113ce, 0x0113ce,  0}, {0x0113cf, 0x0113cf,  1}, {0x0113d0, 0x0113d0,  0},
    {0x0113d1, 0x0113d1,  1}, {0x0113d2, 0x0113d2,  0}, {0x0113d3, 0x0113d5,  1},
    {0x0113d6, 0x0113d6, -1}, {0x0113d7, 0x0113d8,  1}, {0x0113d9, 0x0113e0, -1},
    {0x0113e1, 0x0113e2,  0}, {0x0113e3, 0x0113ff, -1}, {0x011400, 0x011437,  1},
    {0x011438, 0x01143f,  0}, {0x011440, 0x011441,  1}, {0x011442, 0x011444,  0},
    {0x011445, 0x011445,  1}, {0x011446, 0x011446,  0}, {0x011447, 0x01145b,  1},
    {0x01145c, 0x01145c, -1}, {0x01145d, 0x01145d,  1}, {0x01145e, 0x01145e,  0},
    {0x01145f, 0x011461,  1}, {0x011462, 0x01147f, -1}, {0x011480, 0x0114b2,  1},
    {0x0114b3, 0x0114b8,  0}, {0x0114b9, 0x0114b9,  1}, {0x0114ba, 0x0114ba,  0},
    {0x0114bb, 0x0114be,  1}, {0x0114bf, 0x0114c0,  0}, {0x0114c1, 0x0114c1,  1},
    {0x0114c2, 0x0114c3,  0}, {0x0114c4, 0x0114c7,  1}, {0x0114c8, 0x0114cf, -1},
    {0x0114d0, 0x0114d9,  1}, {0x0114da, 0x01157f, -1}, {0x011580, 0x0115b1,  1},
    {0x0115b2, 0x0115b5,  0}, {0x0115b6, 0x0115b7, -1}, {0x0115b8, 0x0115bb,  1},
    {0x0115bc, 0x0115bd,  0}, {0x0115be, 0x0115be,  1}, {0x0115bf, 0x0115c0,  0},
    {0x0115c1, 0x0115db,  1}, {0x0115dc, 0x0115dd,  0}, {0x0115de, 0x0115ff, -1},
    {0x011600, 0x011632,  1}, {0x011633, 0x01163a,  0}, {0x01163b, 0x01163c,  1},
    {0x01163d, 0x01163d,  0}, {0x01163e, 0x01163e,  1}, {0x01163f, 0x011640,  0},
    {0x011641, 0x011644,  1}, {0x011645, 0x01164f, -1}, {0x011650, 0x011659,  1},
    {0x01165a, 0x01165f, -1}, {0x011660, 0x01166c,  1}, {0x01166d, 0x01167f, -1},
    {0x011680, 0x0116aa,  1}, {0x0116ab, 0x0116ab,  0}, {0x0116ac, 0x0116ac,  1},
    {0x0116ad, 0x0116ad,  0}, {0x0116ae, 0x0116af,  1}, {0x0116b0, 0x0116b5,  0},
    {0x0116b6, 0x0116b6,  1}, {0x0116b7, 0x0116b7,  0}, {0x0116b8, 0x0116b9,  1},
    {0x0116ba, 0x0116bf, -1}, {0x0116c0, 0x0116c9,  1}, {0x0116ca, 0x0116cf, -1},
    {0x0116d0, 0x0116e3,  1}, {0x0116e4, 0x0116ff, -1}, {0x011700, 0x01171a,  1},
    {0x01171b, 0x01171c, -1}, {0x01171d, 0x01171d,  0}, {0x01171e, 0x01171e,  1},
    {0x01171f, 0x01171f,  0}, {0x011720, 0x011721,  1}, {0x011722, 0x011725,  0},
    {0x011726, 0x011726,  1}, {0x011727, 0x01172b,  0}, {0x01172c, 0x01172f, -1},
    {0x011730, 0x011746,  1}, {0x011747, 0x0117ff, -1}, {0x011800, 0x01182e,  1},
    {0x01182f, 0x011837,  0}, {0x011838, 0x011838,  1}, {0x011839, 0x01183a,  0},
    {0x01183b, 0x01183b,  1}, {0x01183c, 0x01189f, -1}, {0x0118a0, 0x0118f2,  1},
    {0x0118f3, 0x0118fe, -1}, {0x0118ff, 0x011906,  1}, {0x011907, 0x011908, -1},
    {0x011909, 0x011909,  1}, {0x01190a, 0x01190b, -1}, {0x01190c, 0x011913,  1},
    {0x011914, 0x011914, -1}, {0x011915, 0x011916,  1}, {0x011917, 0x011917, -1},
    {0x011918, 0x011935,  1}, {0x011936, 0x011936, -1}, {0x011937, 0x011938,  1},
    {0x011939, 0x01193a, -1}, {0x01193b, 0x01193c,  0}, {0x01193d, 0x01193d,  1},
    {0x01193e, 0x01193e,  0}, {0x01193f, 0x011942,  1}, {0x011943, 0x011943,  0},
    {0x011944, 0x011946,  1}, {0x011947, 0x01194f, -1}, {0x011950, 0x011959,  1},
    {0x01195a, 0x01199f, -1}, {0x0119a0, 0x0119a7,  1}, {0x0119a8, 0x0119a9, -1},
    {0x0119aa, 0x0119d3,  1}, {0x0119d4, 0x0119d7,  0}, {0x0119d8, 0x0119d9, -1},
    {0x0119da, 0x0119db,  0}, {0x0119dc, 0x0119df,  1}, {0x0119e0, 0x0119e0,  0},
    {0x0119e1, 0x0119e4,  1}, {0x0119e5, 0x0119ff, -1}, {0x011a00, 0x011a00,  1},
    {0x011a01, 0x011a0a,  0}, {0x011a0b, 0x011a32,  1}, {0x011a33, 0x011a38,  0},
    {0x011a39, 0x011a3a,  1}, {0x011a3b, 0x011a3e,  0}, {0x011a3f, 0x011a46,  1},
    {0x011a47, 0x011a47,  0}, {0x011a48, 0x011a4f, -1}, {0x011a50, 0x011a50,  1},
    {0x011a51, 0x011a56,  0}, {0x011a57, 0x011a58,  1}, {0x011a59, 0x011a5b,  0},
    {0x011a5c, 0x011a89,  1}, {0x011a8a, 0x011a96,  0}, {0x011a97, 0x011a97,  1},
    {0x011a98, 0x011a99,  0}, {0x011a9a, 0x011aa2,  1}, {0x011aa3, 0x011aaf, -1},
    {0x011ab0, 0x011af8,  1}, {0x011af9, 0x011aff, -1}, {0x011b00, 0x011b09,  1},
    {0x011b0a, 0x011bbf, -1}, {0x011bc0, 0x011be1,  1}, {0x011be2, 0x011bef, -1},
    {0x011bf0, 0x011bf9,  1}, {0x011bfa, 0x011bff, -1}, {0x011c00, 0x011c08,  1},
    {0x011c09, 0x011c09, -1}, {0x011c0a, 0x011c2f,  1}, {0x011c30, 0x011c36,  0},
    {0x011c37, 0x011c37, -1}, {0x011c38, 0x011c3d,  0}, {0x011c3e, 0x011c3e,  1},
    {0x011c3f, 0x011c3f,  0}, {0x011c40, 0x011c45,  1}, {0x011c46, 0x011c4f, -1},
    {0x011c50, 0x011c6c,  1}, {0x011c6d, 0x011c6f, -1}, {0x011c70, 0x011c8f,  1},
    {0x011c90, 0x011c91, -1}, {0x011c92, 0x011ca7,  0}, {0x011ca8, 0x011ca8, -1},
    {0x011ca9, 0x011ca9,  1}, {0x011caa, 0x011cb0,  0}, {0x011cb1, 0x011cb1,  1},
    {0x011cb2, 0x011cb3,  0}, {0x011cb4, 0x011cb4,  1}, {0x011cb5, 0x011cb6,  0},
    {0x011cb7, 0x011cff, -1}, {0x011d00, 0x011d06,  1}, {0x011d07, 0x011d07, -1},
    {0x011d08, 0x011d09,  1}, {0x011d0a, 0x011d0a, -1}, {0x011d0b, 0x011d30,  1},
    {0x011d31, 0x011d36,  0}, {0x011d37, 0x011d39, -1}, {0x011d3a, 0x011d3a,  0},
    {0x011d3b, 0x011d3b, -1}, {0x011d3c, 0x011d3d,  0}, {0x011d3e, 0x011d3e, -1},
    {0x011d3f, 0x011d45,  0}, {0x011d46, 0x011d46,  1}, {0x011d47, 0x011d47,  0},
    {0x011d48, 0x011d4f, -1}, {0x011d50, 0x011d59,  1}, {0x011d5a, 0x011d5f, -1},
    {0x011d60, 0x011d65,  1}, {0x011d66, 0x011d66, -1}, {0x011d67, 0x011d68,  1},
    {0x011d69, 0x011d69, -1}, {0x011d6a, 0x011d8e,  1}, {0x011d8f, 0x011d8f, -1},
    {0x011d90, 0x011d91,  0}, {0x011d92, 0x011d92, -1}, {0x011d93, 0x011d94,  1},
    {0x011d95, 0x011d95,  0}, {0x011d96, 0x011d96,  1}, {0x011d97, 0x011d97,  0},
    {0x011d98, 0x011d98,  1}, {0x011d99, 0x011d9f, -1}, {0x011da0, 0x011da9,  1},
    {0x011daa, 0x011edf, -1}, {0x011ee0, 0x011ef2,  1}, {0x011ef3, 0x011ef4,  0},
    {0x011ef5, 0x011ef8,  1}, {0x011ef9, 0x011eff, -1}, {0x011f00, 0x011f01,  0},
    {0x011f02, 0x011f10,  1}, {0x011f11, 0x011f11, -1}, {0x011f12, 0x011f35,  1},
    {0x011f36, 0x011f3a,  0}, {0x011f3b, 0x011f3d, -1}, {0x011f3e, 0x011f3f,  1},
    {0x011f40, 0x011f40,  0}, {0x011f41, 0x011f41,  1}, {0x011f42, 0x011f42,  0},
    {0x011f43, 0x011f59,  1}, {0x011f5a, 0x011f5a,  0}, {0x011f5b, 0x011faf, -1},
    {0x011fb0, 0x011fb0,  1}, {0x011fb1, 0x011fbf, -1}, {0x011fc0, 0x011ff1,  1},
    {0x011ff2, 0x011ffe, -1}, {0x011fff, 0x012399,  1}, {0x01239a, 0x0123ff, -1},
    {0x012400, 0x01246e,  1}, {0x01246f, 0x01246f, -1}, {0x012470, 0x012474,  1},
    {0x012475, 0x01247f, -1}, {0x012480, 0x012543,  1}, {0x012544, 0x012f8f, -1},
    {0x012f90, 0x012ff2,  1}, {0x012ff3, 0x012fff, -1}, {0x013000, 0x01343f,  1},
    {0x013440, 0x013440,  0}, {0x013441, 0x013446,  1}, {0x013447, 0x013455,  0},
    {0x013456, 0x01345f, -1}, {0x013460, 0x0143fa,  1}, {0x0143fb, 0x0143ff, -1},
    {0x014400, 0x014646,  1}, {0x014647, 0x0160ff, -1}, {0x016100, 0x01611d,  1},
    {0x01611e, 0x016129,  0}, {0x01612a, 0x01612c,  1}, {0x01612d, 0x01612f,  0},
    {0x016130, 0x016139,  1}, {0x01613a, 0x0167ff, -1}, {0x016800, 0x016a38,  1},
    {0x016a39, 0x016a3f, -1}, {0x016a40, 0x016a5e,  1}, {0x016a5f, 0x016a5f, -1},
    {0x016a60, 0x016a69,  1}, {0x016a6a, 0x016a6d, -1}, {0x016a6e, 0x016abe,  1},
    {0x016abf, 0x016abf, -1}, {0x016ac0, 0x016ac9,  1}, {0x016aca, 0x016acf, -1},
    {0x016ad0, 0x016aed,  1}, {0x016aee, 0x016aef, -1}, {0x016af0, 0x016af4,  0},
    {0x016af5, 0x016af5,  1}, {0x016af6, 0x016aff, -1}, {0x016b00, 0x016b2f,  1},
    {0x016b30, 0x016b36,  0}, {0x016b37, 0x016b45,  1}, {0x016b46, 0x016b4f, -1},
    {0x016b50, 0x016b59,  1}, {0x016b5a, 0x016b5a, -1}, {0x016b5b, 0x016b61,  1},
    {0x016b62, 0x016b62, -1}, {0x016b63, 0x016b77,  1}, {0x016b78, 0x016b7c, -1},
    {0x016b7d, 0x016b8f,  1}, {0x016b90, 0x016d3f, -1}, {0x016d40, 0x016d79,  1},
    {0x016d7a, 0x016e3f, -1}, {0x016e40, 0x016e9a,  1}, {0x016e9b, 0x016eff, -1},
    {0x016f00, 0x016f4a,  1}, {0x016f4b, 0x016f4e, -1}, {0x016f4f, 0x016f4f,  0},
    {0x016f50, 0x016f87,  1}, {0x016f88, 0x016f8e, -1}, {0x016f8f, 0x016f92,  0},
    {0x016f93, 0x016f9f,  1}, {0x016fa0, 0x016fdf, -1}, {0x016fe0, 0x016fe3,  2},
    {0x016fe4, 0x016fe4,  0}, {0x016fe5, 0x016fef, -1}, {0x016ff0, 0x016ff1,  2},
    {0x016ff2, 0x016fff, -1}, {0x017000, 0x0187f7,  2}, {0x0187f8, 0x0187ff, -1},
    {0x018800, 0x018cd5,  2}, {0x018cd6, 0x018cfe, -1}, {0x018cff, 0x018d08,  2},
    {0x018d09, 0x01afef, -1}, {0x01aff0, 0x01aff3,  2}, {0x01aff4, 0x01aff4, -1},
    {0x01aff5, 0x01affb,  2}, {0x01affc, 0x01affc, -1}, {0x01affd, 0x01affe,  2},
    {0x01afff, 0x01afff, -1}, {0x01b000, 0x01b122,  2}, {0x01b123, 0x01b131, -1},
    {0x01b132, 0x01b132,  2}, {0x01b133, 0x01b14f, -1}, {0x01b150, 0x01b152,  2},
    {0x01b153, 0x01b154, -1}, {0x01b155, 0x01b155,  2}, {0x01b156, 0x01b163, -1},
    {0x01b164, 0x01b167,  2}, {0x01b168, 0x01b16f, -1}, {0x01b170, 0x01b2fb,  2},
    {0x01b2fc, 0x01bbff, -1}, {0x01bc00, 0x01bc6a,  1}, {0x01bc6b, 0x01bc6f, -1},
    {0x01bc70, 0x01bc7c,  1}, {0x01bc7d, 0x01bc7f, -1}, {0x01bc80, 0x01bc88,  1},
    {0x01bc89, 0x01bc8f, -1}, {0x01bc90, 0x01bc99,  1}, {0x01bc9a, 0x01bc9b, -1},
    {0x01bc9c, 0x01bc9c,  1}, {0x01bc9d, 0x01bc9e,  0}, {0x01bc9f, 0x01bc9f,  1},
    {0x01bca0, 0x01bca3,  0}, {0x01bca4, 0x01cbff, -1}, {0x01cc00, 0x01ccf9,  1},
    {0x01ccfa, 0x01ccff, -1}, {0x01cd00, 0x01ceb3,  1}, {0x01ceb4, 0x01ceff, -1},
    {0x01cf00, 0x01cf2d,  0}, {0x01cf2e, 0x01cf2f, -1}, {0x01cf30, 0x01cf46,  0},
    {0x01cf47, 0x01cf4f, -1}, {0x01cf50, 0x01cfc3,  1}, {0x01cfc4, 0x01cfff, -1},
    {0x01d000, 0x01d0f5,  1}, {0x01d0f6, 0x01d0ff, -1}, {0x01d100, 0x01d126,  1},
    {0x01d127, 0x01d128, -1}, {0x01d129, 0x01d166,  1}, {0x01d167, 0x01d169,  0},
    {0x01d16a, 0x01d172,  1}, {0x01d173, 0x01d182,  0}, {0x01d183, 0x01d184,  1},
    {0x01d185, 0x01d18b,  0}, {0x01d18c, 0x01d1a9,  1}, {0x01d1aa, 0x01d1ad,  0},
    {0x01d1ae, 0x01d1ea,  1}, {0x01d1eb, 0x01d1ff, -1}, {0x01d200, 0x01d241,  1},
    {0x01d242, 0x01d244,  0}, {0x01d245, 0x01d245,  1}, {0x01d246, 0x01d2bf, -1},
    {0x01d2c0, 0x01d2d3,  1}, {0x01d2d4, 0x01d2df, -1}, {0x01d2e0, 0x01d2f3,  1},
    {0x01d2f4, 0x01d2ff, -1}, {0x01d300, 0x01d356,  2}, {0x01d357, 0x01d35f, -1},
    {0x01d360, 0x01d376,  2}, {0x01d377, 0x01d378,  1}, {0x01d379, 0x01d3ff, -1},
    {0x01d400, 0x01d454,  1}, {0x01d455, 0x01d455, -1}, {0x01d456, 0x01d49c,  1},
    {0x01d49d, 0x01d49d, -1}, {0x01d49e, 0x01d49f,  1}, {0x01d4a0, 0x01d4a1, -1},
    {0x01d4a2, 0x01d4a2,  1}, {0x01d4a3, 0x01d4a4, -1}, {0x01d4a5, 0x01d4a6,  1},
    {0x01d4a7, 0x01d4a8, -1}, {0x01d4a9, 0x01d4ac,  1}, {0x01d4ad, 0x01d4ad, -1},
    {0x01d4ae, 0x01d4b9,  1}, {0x01d4ba, 0x01d4ba, -1}, {0x01d4bb, 0x01d4bb,  1},
    {0x01d4bc, 0x01d4bc, -1}, {0x01d4bd, 0x01d4c3,  1}, {0x01d4c4, 0x01d4c4, -1},
    {0x01d4c5, 0x01d505,  1}, {0x01d506, 0x01d506, -1}, {0x01d507, 0x01d50a,  1},
    {0x01d50b, 0x01d50c, -1}, {0x01d50d, 0x01d514,  1}, {0x01d515, 0x01d515, -1},
    {0x01d516, 0x01d51c,  1}, {0x01d51d, 0x01d51d, -1}, {0x01d51e, 0x01d539,  1},
    {0x01d53a, 0x01d53a, -1}, {0x01d53b, 0x01d53e,  1}, {0x01d53f, 0x01d53f, -1},
    {0x01d540, 0x01d544,  1}, {0x01d545, 0x01d545, -1}, {0x01d546, 0x01d546,  1},
    {0x01d547, 0x01d549, -1}, {0x01d54a, 0x01d550,  1}, {0x01d551, 0x01d551, -1},
    {0x01d552, 0x01d6a5,  1}, {0x01d6a6, 0x01d6a7, -1}, {0x01d6a8, 0x01d7cb,  1},
    {0x01d7cc, 0x01d7cd, -1}, {0x01d7ce, 0x01d9ff,  1}, {0x01da00, 0x01da36,  0},
    {0x01da37, 0x01da3a,  1}, {0x01da3b, 0x01da6c,  0}, {0x01da6d, 0x01da74,  1},
    {0x01da75, 0x01da75,  0}, {0x01da76, 0x01da83,  1}, {0x01da84, 0x01da84,  0},
    {0x01da85, 0x01da8b,  1}, {0x01da8c, 0x01da9a, -1}, {0x01da9b, 0x01da9f,  0},
    {0x01daa0, 0x01daa0, -1}, {0x01daa1, 0x01daaf,  0}, {0x01dab0, 0x01deff, -1},
    {0x01df00, 0x01df1e,  1}, {0x01df1f, 0x01df24, -1}, {0x01df25, 0x01df2a,  1},
    {0x01df2b, 0x01dfff, -1}, {0x01e000, 0x01e006,  0}, {0x01e007, 0x01e007, -1},
    {0x01e008, 0x01e018,  0}, {0x01e019, 0x01e01a, -1}, {0x01e01b, 0x01e021,  0},
    {0x01e022, 0x01e022, -1}, {0x01e023, 0x01e024,  0}, {0x01e025, 0x01e025, -1},
    {0x01e026, 0x01e02a,  0}, {0x01e02b, 0x01e02f, -1}, {0x01e030, 0x01e06d,  1},
    {0x01e06e, 0x01e08e, -1}, {0x01e08f, 0x01e08f,  0}, {0x01e090, 0x01e0ff, -1},
    {0x01e100, 0x01e12c,  1}, {0x01e12d, 0x01e12f, -1}, {0x01e130, 0x01e136,  0},
    {0x01e137, 0x01e13d,  1}, {0x01e13e, 0x01e13f, -1}, {0x01e140, 0x01e149,  1},
    {0x01e14a, 0x01e14d, -1}, {0x01e14e, 0x01e14f,  1}, {0x01e150, 0x01e28f, -1},
    {0x01e290, 0x01e2ad,  1}, {0x01e2ae, 0x01e2ae,  0}, {0x01e2af, 0x01e2bf, -1},
    {0x01e2c0, 0x01e2eb,  1}, {0x01e2ec, 0x01e2ef,  0}, {0x01e2f0, 0x01e2f9,  1},
    {0x01e2fa, 0x01e2fe, -1}, {0x01e2ff, 0x01e2ff,  1}, {0x01e300, 0x01e4cf, -1},
    {0x01e4d0, 0x01e4eb,  1}, {0x01e4ec, 0x01e4ef,  0}, {0x01e4f0, 0x01e4f9,  1},
    {0x01e4fa, 0x01e5cf, -1}, {0x01e5d0, 0x01e5ed,  1}, {0x01e5ee, 0x01e5ef,  0},
    {0x01e5f0, 0x01e5fa,  1}, {0x01e5fb, 0x01e5fe, -1}, {0x01e5ff, 0x01e5ff,  1},
    {0x01e600, 0x01e7df, -1}, {0x01e7e0, 0x01e7e6,  1}, {0x01e7e7, 0x01e7e7, -1},
    {0x01e7e8, 0x01e7eb,  1}, {0x01e7ec, 0x01e7ec, -1}, {0x01e7ed, 0x01e7ee,  1},
    {0x01e7ef, 0x01e7ef, -1}, {0x01e7f0, 0x01e7fe,  1}, {0x01e7ff, 0x01e7ff, -1},
    {0x01e800, 0x01e8c4,  1}, {0x01e8c5, 0x01e8c6, -1}, {0x01e8c7, 0x01e8cf,  1},
    {0x01e8d0, 0x01e8d6,  0}, {0x01e8d7, 0x01e8ff, -1}, {0x01e900, 0x01e943,  1},
    {0x01e944, 0x01e94a,  0}, {0x01e94b, 0x01e94b,  1}, {0x01e94c, 0x01e94f, -1},
    {0x01e950, 0x01e959,  1}, {0x01e95a, 0x01e95d, -1}, {0x01e95e, 0x01e95f,  1},
    {0x01e960, 0x01ec70, -1}, {0x01ec71, 0x01ecb4,  1}, {0x01ecb5, 0x01ed00, -1},
    {0x01ed01, 0x01ed3d,  1}, {0x01ed3e, 0x01edff, -1}, {0x01ee00, 0x01ee03,  1},
    {0x01ee04, 0x01ee04, -1}, {0x01ee05, 0x01ee1f,  1}, {0x01ee20, 0x01ee20, -1},
    {0x01ee21, 0x01ee22,  1}, {0x01ee23, 0x01ee23, -1}, {0x01ee24, 0x01ee24,  1},
    {0x01ee25, 0x01ee26, -1}, {0x01ee27, 0x01ee27,  1}, {0x01ee28, 0x01ee28, -1},
    {0x01ee29, 0x01ee32,  1}, {0x01ee33, 0x01ee33, -1}, {0x01ee34, 0x01ee37,  1},
    {0x01ee38, 0x01ee38, -1}, {0x01ee39, 0x01ee39,  1}, {0x01ee3a, 0x01ee3a, -1},
    {0x01ee3b, 0x01ee3b,  1}, {0x01ee3c, 0x01ee41, -1}, {0x01ee42, 0x01ee42,  1},
    {0x01ee43, 0x01ee46, -1}, {0x01ee47, 0x01ee47,  1}, {0x01ee48, 0x01ee48, -1},
    {0x01ee49, 0x01ee49,  1}, {0x01ee4a, 0x01ee4a, -1}, {0x01ee4b, 0x01ee4b,  1},
    {0x01ee4c, 0x01ee4c, -1}, {0x01ee4d, 0x01ee4f,  1}, {0x01ee50, 0x01ee50, -1},
    {0x01ee51, 0x01ee52,  1}, {0x01ee53, 0x01ee53, -1}, {0x01ee54, 0x01ee54,  1},
    {0x01ee55, 0x01ee56, -1}, {0x01ee57, 0x01ee57,  1}, {0x01ee58, 0x01ee58, -1},
    {0x01ee59, 0x01ee59,  1}, {0x01ee5a, 0x01ee5a, -1}, {0x01ee5b, 0x01ee5b,  1},
    {0x01ee5c, 0x01ee5c, -1}, {0x01ee5d, 0x01ee5d,  1}, {0x01ee5e, 0x01ee5e, -1},
    {0x01ee5f, 0x01ee5f,  1}, {0x01ee60, 0x01ee60, -1}, {0x01ee61, 0x01ee62,  1},
    {0x01ee63, 0x01ee63, -1}, {0x01ee64, 0x01ee64,  1}, {0x01ee65, 0x01ee66, -1},
    {0x01ee67, 0x01ee6a,  1}, {0x01ee6b, 0x01ee6b, -1}, {0x01ee6c, 0x01ee72,  1},
    {0x01ee73, 0x01ee73, -1}, {0x01ee74, 0x01ee77,  1}, {0x01ee78, 0x01ee78, -1},
    {0x01ee79, 0x01ee7c,  1}, {0x01ee7d, 0x01ee7d, -1}, {0x01ee7e, 0x01ee7e,  1},
    {0x01ee7f, 0x01ee7f, -1}, {0x01ee80, 0x01ee89,  1}, {0x01ee8a, 0x01ee8a, -1},
    {0x01ee8b, 0x01ee9b,  1}, {0x01ee9c, 0x01eea0, -1}, {0x01eea1, 0x01eea3,  1},
    {0x01eea4, 0x01eea4, -1}, {0x01eea5, 0x01eea9,  1}, {0x01eeaa, 0x01eeaa, -1},
    {0x01eeab, 0x01eebb,  1}, {0x01eebc, 0x01eeef, -1}, {0x01eef0, 0x01eef1,  1},
    {0x01eef2, 0x01efff, -1}, {0x01f000, 0x01f003,  1}, {0x01f004, 0x01f004,  2},
    {0x01f005, 0x01f02b,  1}, {0x01f02c, 0x01f02f, -1}, {0x01f030, 0x01f093,  1},
    {0x01f094, 0x01f09f, -1}, {0x01f0a0, 0x01f0ae,  1}, {0x01f0af, 0x01f0b0, -1},
    {0x01f0b1, 0x01f0bf,  1}, {0x01f0c0, 0x01f0c0, -1}, {0x01f0c1, 0x01f0ce,  1},
    {0x01f0cf, 0x01f0cf,  2}, {0x01f0d0, 0x01f0d0, -1}, {0x01f0d1, 0x01f0f5,  1},
    {0x01f0f6, 0x01f0ff, -1}, {0x01f100, 0x01f18d,  1}, {0x01f18e, 0x01f18e,  2},
    {0x01f18f, 0x01f190,  1}, {0x01f191, 0x01f19a,  2}, {0x01f19b, 0x01f1ad,  1},
    {0x01f1ae, 0x01f1e5, -1}, {0x01f1e6, 0x01f1ff,  1}, {0x01f200, 0x01f202,  2},
    {0x01f203, 0x01f20f, -1}, {0x01f210, 0x01f23b,  2}, {0x01f23c, 0x01f23f, -1},
    {0x01f240, 0x01f248,  2}, {0x01f249, 0x01f24f, -1}, {0x01f250, 0x01f251,  2},
    {0x01f252, 0x01f25f, -1}, {0x01f260, 0x01f265,  2}, {0x01f266, 0x01f2ff, -1},
    {0x01f300, 0x01f320,  2}, {0x01f321, 0x01f32c,  1}, {0x01f32d, 0x01f335,  2},
    {0x01f336, 0x01f336,  1}, {0x01f337, 0x01f37c,  2}, {0x01f37d, 0x01f37d,  1},
    {0x01f37e, 0x01f393,  2}, {0x01f394, 0x01f39f,  1}, {0x01f3a0, 0x01f3ca,  2},
    {0x01f3cb, 0x01f3ce,  1}, {0x01f3cf, 0x01f3d3,  2}, {0x01f3d4, 0x01f3df,  1},
    {0x01f3e0, 0x01f3f0,  2}, {0x01f3f1, 0x01f3f3,  1}, {0x01f3f4, 0x01f3f4,  2},
    {0x01f3f5, 0x01f3f7,  1}, {0x01f3f8, 0x01f43e,  2}, {0x01f43f, 0x01f43f,  1},
    {0x01f440, 0x01f440,  2}, {0x01f441, 0x01f441,  1}, {0x01f442, 0x01f4fc,  2},
    {0x01f4fd, 0x01f4fe,  1}, {0x01f4ff, 0x01f53d,  2}, {0x01f53e, 0x01f54a,  1},
    {0x01f54b, 0x01f54e,  2}, {0x01f54f, 0x01f54f,  1}, {0x01f550, 0x01f567,  2},
    {0x01f568, 0x01f579,  1}, {0x01f57a, 0x01f57a,  2}, {0x01f57b, 0x01f594,  1},
    {0x01f595, 0x01f596,  2}, {0x01f597, 0x01f5a3,  1}, {0x01f5a4, 0x01f5a4,  2},
    {0x01f5a5, 0x01f5fa,  1}, {0x01f5fb, 0x01f64f,  2}, {0x01f650, 0x01f67f,  1},
    {0x01f680, 0x01f6c5,  2}, {0x01f6c6, 0x01f6cb,  1}, {0x01f6cc, 0x01f6cc,  2},
    {0x01f6cd, 0x01f6cf,  1}, {0x01f6d0, 0x01f6d2,  2}, {0x01f6d3, 0x01f6d4,  1},
    {0x01f6d5, 0x01f6d7,  2}, {0x01f6d8, 0x01f6db, -1}, {0x01f6dc, 0x01f6df,  2},
    {0x01f6e0, 0x01f6ea,  1}, {0x01f6eb, 0x01f6ec,  2}, {0x01f6ed, 0x01f6ef, -1},
    {0x01f6f0, 0x01f6f3,  1}, {0x01f6f4, 0x01f6fc,  2}, {0x01f6fd, 0x01f6ff, -1},
    {0x01f700, 0x01f776,  1}, {0x01f777, 0x01f77a, -1}, {0x01f77b, 0x01f7d9,  1},
    {0x01f7da, 0x01f7df, -1}, {0x01f7e0, 0x01f7eb,  2}, {0x01f7ec, 0x01f7ef, -1},
    {0x01f7f0, 0x01f7f0,  2}, {0x01f7f1, 0x01f7ff, -1}, {0x01f800, 0x01f80b,  1},
    {0x01f80c, 0x01f80f, -1}, {0x01f810, 0x01f847,  1}, {0x01f848, 0x01f84f, -1},
    {0x01f850, 0x01f859,  1}, {0x01f85a, 0x01f85f, -1}, {0x01f860, 0x01f887,  1},
    {0x01f888, 0x01f88f, -1}, {0x01f890, 0x01f8ad,  1}, {0x01f8ae, 0x01f8af, -1},
    {0x01f8b0, 0x01f8bb,  1}, {0x01f8bc, 0x01f8bf, -1}, {0x01f8c0, 0x01f8c1,  1},
    {0x01f8c2, 0x01f8ff, -1}, {0x01f900, 0x01f90b,  1}, {0x01f90c, 0x01f93a,  2},
    {0x01f93b, 0x01f93b,  1}, {0x01f93c, 0x01f945,  2}, {0x01f946, 0x01f946,  1},
    {0x01f947, 0x01f9ff,  2}, {0x01fa00, 0x01fa53,  1}, {0x01fa54, 0x01fa5f, -1},
    {0x01fa60, 0x01fa6d,  1}, {0x01fa6e, 0x01fa6f, -1}, {0x01fa70, 0x01fa7c,  2},
    {0x01fa7d, 0x01fa7f, -1}, {0x01fa80, 0x01fa89,  2}, {0x01fa8a, 0x01fa8e, -1},
    {0x01fa8f, 0x01fac6,  2}, {0x01fac7, 0x01facd, -1}, {0x01face, 0x01fadc,  2},
    {0x01fadd, 0x01fade, -1}, {0x01fadf, 0x01fae9,  2}, {0x01faea, 0x01faef, -1},
    {0x01faf0, 0x01faf8,  2}, {0x01faf9, 0x01faff, -1}, {0x01fb00, 0x01fb92,  1},
    {0x01fb93, 0x01fb93, -1}, {0x01fb94, 0x01fbf9,  1}, {0x01fbfa, 0x01ffff, -1},
    {0x020000, 0x02a6df,  2}, {0x02a6e0, 0x02a6ff, -1}, {0x02a700, 0x02b739,  2},
    {0x02b73a, 0x02b73f, -1}, {0x02b740, 0x02b81d,  2}, {0x02b81e, 0x02b81f, -1},
    {0x02b820, 0x02cea1,  2}, {0x02cea2, 0x02ceaf, -1}, {0x02ceb0, 0x02ebe0,  2},
    {0x02ebe1, 0x02ebef, -1}, {0x02ebf0, 0x02ee5d,  2}, {0x02ee5e, 0x02f7ff, -1},
    {0x02f800, 0x02fa1d,  2}, {0x02fa1e, 0x02ffff, -1}, {0x030000, 0x03134a,  2},
    {0x03134b, 0x03134f, -1}, {0x031350, 0x0323af,  2}, {0x0323b0, 0x0e0000, -1},
    {0x0e0001, 0x0e0001,  0}, {0x0e0002, 0x0e001f, -1}, {0x0e0020, 0x0e007f,  0},
    {0x0e0080, 0x0e00ff, -1}, {0x0e0100, 0x0e01ef,  0}, {0x0e01f0, 0x0effff, -1},
    {0x0f0000, 0x0ffffd,  1}, {0x0ffffe, 0x0fffff, -1}, {0x100000, 0x10fffd,  1},
    {0x10fffe, 0x10ffff, -1},
    // clang-format on
};
#define WCWIDTH_TABLE_LENGTH 2143
#endif // ifndef TB_OPT_LIBC_WCHAR

static int tb_reset(void);
static int tb_printf_inner(int x, int y, uintattr_t fg, uintattr_t bg,
    size_t *out_w, const char *fmt, va_list vl);
static int init_term_attrs(void);
static int init_term_caps(void);
static int init_cap_trie(void);
static int cap_trie_add(const char *cap, uint16_t key, uint8_t mod);
static int cap_trie_find(const char *buf, size_t nbuf, struct cap_trie_t **last,
    size_t *depth);
static int cap_trie_deinit(struct cap_trie_t *node);
static int init_resize_handler(void);
static int send_init_escape_codes(void);
static int send_clear(void);
static int update_term_size(void);
static int update_term_size_via_esc(void);
static int init_cellbuf(void);
static int tb_deinit(void);
static int load_terminfo(void);
static int load_terminfo_from_path(const char *path, const char *term);
static int read_terminfo_path(const char *path);
static int parse_terminfo_caps(void);
static int load_builtin_caps(void);
static const char *get_terminfo_string(int16_t offsets_pos, int16_t offsets_len,
    int16_t table_pos, int16_t table_size, int16_t index);
static int get_terminfo_int16(int offset, int16_t *val);
static int wait_event(struct tb_event *event, int timeout);
static int extract_event(struct tb_event *event);
static int extract_esc(struct tb_event *event);
static int extract_esc_user(struct tb_event *event, int is_post);
static int extract_esc_cap(struct tb_event *event);
static int extract_esc_mouse(struct tb_event *event);
static int resize_cellbufs(void);
static void handle_resize(int sig);
static int send_attr(uintattr_t fg, uintattr_t bg);
static int send_sgr(uint32_t fg, uint32_t bg, int fg_is_default,
    int bg_is_default);
static int send_cursor_if(int x, int y);
static int send_char(int x, int y, uint32_t ch);
static int send_cluster(int x, int y, uint32_t *ch, size_t nch);
static int convert_num(uint32_t num, char *buf);
static int cell_cmp(struct tb_cell *a, struct tb_cell *b);
static int cell_copy(struct tb_cell *dst, struct tb_cell *src);
static int cell_set(struct tb_cell *cell, uint32_t *ch, size_t nch,
    uintattr_t fg, uintattr_t bg);
static int cell_reserve_ech(struct tb_cell *cell, size_t n);
static int cell_free(struct tb_cell *cell);
static int cellbuf_init(struct cellbuf_t *c, int w, int h);
static int cellbuf_free(struct cellbuf_t *c);
static int cellbuf_clear(struct cellbuf_t *c);
static int cellbuf_get(struct cellbuf_t *c, int x, int y, struct tb_cell **out);
static int cellbuf_in_bounds(struct cellbuf_t *c, int x, int y);
static int cellbuf_resize(struct cellbuf_t *c, int w, int h);
static int bytebuf_puts(struct bytebuf_t *b, const char *str);
static int bytebuf_nputs(struct bytebuf_t *b, const char *str, size_t nstr);
static int bytebuf_shift(struct bytebuf_t *b, size_t n);
static int bytebuf_flush(struct bytebuf_t *b, int fd);
static int bytebuf_reserve(struct bytebuf_t *b, size_t sz);
static int bytebuf_free(struct bytebuf_t *b);
static int tb_iswprint_ex(uint32_t ch, int *width);
static int tb_wcswidth(uint32_t *ch, size_t nch);

int tb_init(void) {
    return tb_init_file("/dev/tty");
}

int tb_init_file(const char *path) {
    if (global.initialized) return TB_ERR_INIT_ALREADY;
    int ttyfd = open(path, O_RDWR);
    if (ttyfd < 0) {
        global.last_errno = errno;
        return TB_ERR_INIT_OPEN;
    }
    global.ttyfd_open = 1;
    return tb_init_fd(ttyfd);
}

int tb_init_fd(int ttyfd) {
    return tb_init_rwfd(ttyfd, ttyfd);
}

int tb_init_rwfd(int rfd, int wfd) {
    int rv;

    tb_reset();
    global.ttyfd = rfd == wfd && isatty(rfd) ? rfd : -1;
    global.rfd = rfd;
    global.wfd = wfd;

    do {
        if_err_break(rv, init_term_attrs());
        if_err_break(rv, init_term_caps());
        if_err_break(rv, init_cap_trie());
        if_err_break(rv, init_resize_handler());
        if_err_break(rv, send_init_escape_codes());
        if_err_break(rv, send_clear());
        if_err_break(rv, update_term_size());
        if_err_break(rv, init_cellbuf());
        global.initialized = 1;
    } while (0);

    if (rv != TB_OK) tb_deinit();

    return rv;
}

int tb_shutdown(void) {
    if_not_init_return();
    tb_deinit();
    return TB_OK;
}

int tb_width(void) {
    if_not_init_return();
    return global.width;
}

int tb_height(void) {
    if_not_init_return();
    return global.height;
}

int tb_clear(void) {
    if_not_init_return();
    return cellbuf_clear(&global.back);
}

int tb_set_clear_attrs(uintattr_t fg, uintattr_t bg) {
    if_not_init_return();
    global.fg = fg;
    global.bg = bg;
    return TB_OK;
}

int tb_present(void) {
    if_not_init_return();

    int rv;

    // TODO: Assert global.back.(width,height) == global.front.(width,height)

    global.last_x = -1;
    global.last_y = -1;

    int x, y, i;
    for (y = 0; y < global.front.height; y++) {
        for (x = 0; x < global.front.width;) {
            struct tb_cell *back, *front;
            if_err_return(rv, cellbuf_get(&global.back, x, y, &back));
            if_err_return(rv, cellbuf_get(&global.front, x, y, &front));

            int w;
            {
#ifdef TB_OPT_EGC
                if (back->nech > 0)
                    w = tb_wcswidth(back->ech, back->nech);
                else
#endif
                    w = tb_wcwidth((wchar_t)back->ch);
            }
            if (w < 1) w = 1; // wcwidth qreturns -1 for invalid codepoints

            if (cell_cmp(back, front) != 0) {
                cell_copy(front, back);

                send_attr(back->fg, back->bg);
                if (w > 1 && x >= global.front.width - (w - 1)) {
                    // Not enough room for wide char, send spaces
                    for (i = x; i < global.front.width; i++) {
                        send_char(i, y, ' ');
                    }
                } else {
                    {
#ifdef TB_OPT_EGC
                        if (back->nech > 0)
                            send_cluster(x, y, back->ech, back->nech);
                        else
#endif
                            send_char(x, y, back->ch);
                    }

                    // When wcwidth>1, we need to advance the cursor by more
                    // than 1, thereby skipping some cells. Set these skipped
                    // cells to an invalid codepoint in the front buffer, so
                    // that if this cell is later replaced by a wcwidth==1 char,
                    // we'll get a cell_cmp diff for the skipped cells and
                    // properly re-render.
                    for (i = 1; i < w; i++) {
                        struct tb_cell *front_wide;
                        uint32_t invalid = -1;
                        if_err_return(rv,
                            cellbuf_get(&global.front, x + i, y, &front_wide));
                        if_err_return(rv,
                            cell_set(front_wide, &invalid, 1, -1, -1));
                    }
                }
            }
            x += w;
        }
    }

    if_err_return(rv, send_cursor_if(global.cursor_x, global.cursor_y));
    if_err_return(rv, bytebuf_flush(&global.out, global.wfd));

    return TB_OK;
}

int tb_invalidate(void) {
    int rv;
    if_not_init_return();
    if_err_return(rv, resize_cellbufs());
    return TB_OK;
}

int tb_set_cursor(int cx, int cy) {
    if_not_init_return();
    int rv;
    if (cx < 0) cx = 0;
    if (cy < 0) cy = 0;
    if (global.cursor_x == -1) {
        if_err_return(rv,
            bytebuf_puts(&global.out, global.caps[TB_CAP_SHOW_CURSOR]));
    }
    if_err_return(rv, send_cursor_if(cx, cy));
    global.cursor_x = cx;
    global.cursor_y = cy;
    return TB_OK;
}

int tb_hide_cursor(void) {
    if_not_init_return();
    int rv;
    if (global.cursor_x >= 0) {
        if_err_return(rv,
            bytebuf_puts(&global.out, global.caps[TB_CAP_HIDE_CURSOR]));
    }
    global.cursor_x = -1;
    global.cursor_y = -1;
    return TB_OK;
}

int tb_set_cell(int x, int y, uint32_t ch, uintattr_t fg, uintattr_t bg) {
    return tb_set_cell_ex(x, y, &ch, 1, fg, bg);
}

int tb_set_cell_ex(int x, int y, uint32_t *ch, size_t nch, uintattr_t fg,
    uintattr_t bg) {
    if_not_init_return();
    int rv;
    struct tb_cell *cell;
    if_err_return(rv, cellbuf_get(&global.back, x, y, &cell));
    if_err_return(rv, cell_set(cell, ch, nch, fg, bg));
    return TB_OK;
}

int tb_get_cell(int x, int y, int back, struct tb_cell *cell) {
    if_not_init_return();
    int rv;
    struct tb_cell *cellp = NULL;
    rv = cellbuf_get(back ? &global.back : &global.front, x, y, &cellp);
    if (cellp) memcpy(cell, cellp, sizeof(*cell));
    return rv;
}

int tb_extend_cell(int x, int y, uint32_t ch) {
    if_not_init_return();
#ifdef TB_OPT_EGC
    // TODO: iswprint ch?
    int rv;
    struct tb_cell *cell;
    size_t nech;
    if_err_return(rv, cellbuf_get(&global.back, x, y, &cell));
    if (cell->nech > 0) { // append to ech
        nech = cell->nech + 1;
        if_err_return(rv, cell_reserve_ech(cell, nech + 1));
        cell->ech[nech - 1] = ch;
    } else { // make new ech
        nech = 2;
        if_err_return(rv, cell_reserve_ech(cell, nech + 1));
        cell->ech[0] = cell->ch;
        cell->ech[1] = ch;
    }
    cell->ech[nech] = '\0';
    cell->nech = nech;
    return TB_OK;
#else
    (void)x;
    (void)y;
    (void)ch;
    return TB_ERR;
#endif
}

int tb_set_input_mode(int mode) {
    if_not_init_return();

    if (mode == TB_INPUT_CURRENT) return global.input_mode;

    int esc_or_alt = TB_INPUT_ESC | TB_INPUT_ALT;
    if ((mode & esc_or_alt) == 0) {
        // neither specified; flip on ESC
        mode |= TB_INPUT_ESC;
    } else if ((mode & esc_or_alt) == esc_or_alt) {
        // both specified; flip off ALT
        mode &= ~TB_INPUT_ALT;
    }

    if (mode & TB_INPUT_MOUSE) {
        bytebuf_puts(&global.out, TB_HARDCAP_ENTER_MOUSE);
        bytebuf_flush(&global.out, global.wfd);
    } else {
        bytebuf_puts(&global.out, TB_HARDCAP_EXIT_MOUSE);
        bytebuf_flush(&global.out, global.wfd);
    }

    global.input_mode = mode;
    return TB_OK;
}

int tb_set_output_mode(int mode) {
    if_not_init_return();
    switch (mode) {
        case TB_OUTPUT_CURRENT:
            return global.output_mode;
        case TB_OUTPUT_NORMAL:
        case TB_OUTPUT_256:
        case TB_OUTPUT_216:
        case TB_OUTPUT_GRAYSCALE:
#if TB_OPT_ATTR_W >= 32
        case TB_OUTPUT_TRUECOLOR:
#endif
            global.last_fg = ~global.fg;
            global.last_bg = ~global.bg;
            global.output_mode = mode;
            return TB_OK;
    }
    return TB_ERR;
}

int tb_peek_event(struct tb_event *event, int timeout_ms) {
    if_not_init_return();
    return wait_event(event, timeout_ms);
}

int tb_poll_event(struct tb_event *event) {
    if_not_init_return();
    return wait_event(event, -1);
}

int tb_get_fds(int *ttyfd, int *resizefd) {
    if_not_init_return();

    *ttyfd = global.rfd;
    *resizefd = global.resize_pipefd[0];

    return TB_OK;
}

int tb_print(int x, int y, uintattr_t fg, uintattr_t bg, const char *str) {
    return tb_print_ex(x, y, fg, bg, NULL, str);
}

int tb_print_ex(int x, int y, uintattr_t fg, uintattr_t bg, size_t *out_w,
    const char *str) {
    int rv, w, ix, x_prev;
    uint32_t uni;

    if_not_init_return();

    if (!cellbuf_in_bounds(&global.back, x, y)) {
        return TB_ERR_OUT_OF_BOUNDS;
    }

    ix = x;
    x_prev = x;
    if (out_w) *out_w = 0;

    while (*str) {
        rv = tb_utf8_char_to_unicode(&uni, str);

        if (rv < 0) {
            uni = 0xfffd; // replace invalid UTF-8 char with U+FFFD
            str += rv * -1;
        } else if (rv > 0) {
            str += rv;
        } else {
            break; // shouldn't get here
        }

        if (uni == '\n') { // TODO: \r, \t, \v, \f, etc?
            x = ix;
            x_prev = x;
            y += 1;
            continue;
        } else if (!tb_iswprint_ex(uni, &w)) {
            uni = 0xfffd; // replace non-printable with U+FFFD
            w = 1;
        }

        if (w < 0) {
            return TB_ERR;   // shouldn't happen if iswprint
        } else if (w == 0) { // combining character
            if (cellbuf_in_bounds(&global.back, x_prev, y)) {
                if_err_return(rv, tb_extend_cell(x_prev, y, uni));
            }
        } else {
            if (cellbuf_in_bounds(&global.back, x, y)) {
                if_err_return(rv, tb_set_cell(x, y, uni, fg, bg));
            }
            x_prev = x;
            x += w;
            if (out_w) *out_w += w;
        }
    }

    return TB_OK;
}

int tb_printf(int x, int y, uintattr_t fg, uintattr_t bg, const char *fmt,
    ...) {
    int rv;
    va_list vl;
    va_start(vl, fmt);
    rv = tb_printf_inner(x, y, fg, bg, NULL, fmt, vl);
    va_end(vl);
    return rv;
}

int tb_printf_ex(int x, int y, uintattr_t fg, uintattr_t bg, size_t *out_w,
    const char *fmt, ...) {
    int rv;
    va_list vl;
    va_start(vl, fmt);
    rv = tb_printf_inner(x, y, fg, bg, out_w, fmt, vl);
    va_end(vl);
    return rv;
}

int tb_send(const char *buf, size_t nbuf) {
    return bytebuf_nputs(&global.out, buf, nbuf);
}

int tb_sendf(const char *fmt, ...) {
    int rv;
    char buf[TB_OPT_PRINTF_BUF];
    va_list vl;
    va_start(vl, fmt);
    rv = vsnprintf(buf, sizeof(buf), fmt, vl);
    va_end(vl);
    if (rv < 0 || rv >= (int)sizeof(buf)) {
        return TB_ERR;
    }
    return tb_send(buf, (size_t)rv);
}

int tb_set_func(int fn_type, int (*fn)(struct tb_event *, size_t *)) {
    switch (fn_type) {
        case TB_FUNC_EXTRACT_PRE:
            global.fn_extract_esc_pre = fn;
            return TB_OK;
        case TB_FUNC_EXTRACT_POST:
            global.fn_extract_esc_post = fn;
            return TB_OK;
    }
    return TB_ERR;
}

struct tb_cell *tb_cell_buffer(void) {
    if (!global.initialized) return NULL;
    return global.back.cells;
}

int tb_utf8_char_length(char c) {
    return utf8_length[(unsigned char)c];
}

int tb_utf8_char_to_unicode(uint32_t *out, const char *c) {
    if (*c == '\0') return 0;

    int i;
    unsigned char len = tb_utf8_char_length(*c);
    unsigned char mask = utf8_mask[len - 1];
    uint32_t result = c[0] & mask;
    for (i = 1; i < len && c[i] != '\0'; ++i) {
        result <<= 6;
        result |= c[i] & 0x3f;
    }

    if (i != len) return i * -1;

    *out = result;
    return (int)len;
}

int tb_utf8_unicode_to_char(char *out, uint32_t c) {
    int len = 0;
    int first;
    int i;

    if (c < 0x80) {
        first = 0;
        len = 1;
    } else if (c < 0x800) {
        first = 0xc0;
        len = 2;
    } else if (c < 0x10000) {
        first = 0xe0;
        len = 3;
    } else if (c < 0x200000) {
        first = 0xf0;
        len = 4;
    } else if (c < 0x4000000) {
        first = 0xf8;
        len = 5;
    } else {
        first = 0xfc;
        len = 6;
    }

    for (i = len - 1; i > 0; --i) {
        out[i] = (c & 0x3f) | 0x80;
        c >>= 6;
    }
    out[0] = c | first;
    out[len] = '\0';

    return len;
}

int tb_last_errno(void) {
    return global.last_errno;
}

const char *tb_strerror(int err) {
    switch (err) {
        case TB_OK:
            return "Success";
        case TB_ERR_NEED_MORE:
            return "Not enough input";
        case TB_ERR_INIT_ALREADY:
            return "Termbox initialized already";
        case TB_ERR_MEM:
            return "Out of memory";
        case TB_ERR_NO_EVENT:
            return "No event";
        case TB_ERR_NO_TERM:
            return "No TERM in environment";
        case TB_ERR_NOT_INIT:
            return "Termbox not initialized";
        case TB_ERR_OUT_OF_BOUNDS:
            return "Out of bounds";
        case TB_ERR_UNSUPPORTED_TERM:
            return "Unsupported terminal";
        case TB_ERR_CAP_COLLISION:
            return "Termcaps collision";
        case TB_ERR_RESIZE_SSCANF:
            return "Terminal width/height not received by sscanf() after "
                   "resize";
        case TB_ERR:
        case TB_ERR_INIT_OPEN:
        case TB_ERR_READ:
        case TB_ERR_RESIZE_IOCTL:
        case TB_ERR_RESIZE_PIPE:
        case TB_ERR_RESIZE_SIGACTION:
        case TB_ERR_POLL:
        case TB_ERR_TCGETATTR:
        case TB_ERR_TCSETATTR:
        case TB_ERR_RESIZE_WRITE:
        case TB_ERR_RESIZE_POLL:
        case TB_ERR_RESIZE_READ:
        default:
            strerror_r(global.last_errno, global.errbuf, sizeof(global.errbuf));
            return (const char *)global.errbuf;
    }
}

int tb_has_truecolor(void) {
#if TB_OPT_ATTR_W >= 32
    return 1;
#else
    return 0;
#endif
}

int tb_has_egc(void) {
#ifdef TB_OPT_EGC
    return 1;
#else
    return 0;
#endif
}

int tb_attr_width(void) {
    return TB_OPT_ATTR_W;
}

const char *tb_version(void) {
    return TB_VERSION_STR;
}

static int tb_reset(void) {
    int ttyfd_open = global.ttyfd_open;
    memset(&global, 0, sizeof(global));
    global.ttyfd = -1;
    global.rfd = -1;
    global.wfd = -1;
    global.ttyfd_open = ttyfd_open;
    global.resize_pipefd[0] = -1;
    global.resize_pipefd[1] = -1;
    global.width = -1;
    global.height = -1;
    global.cursor_x = -1;
    global.cursor_y = -1;
    global.last_x = -1;
    global.last_y = -1;
    global.fg = TB_DEFAULT;
    global.bg = TB_DEFAULT;
    global.last_fg = ~global.fg;
    global.last_bg = ~global.bg;
    global.input_mode = TB_INPUT_ESC;
    global.output_mode = TB_OUTPUT_NORMAL;
    return TB_OK;
}

static int init_term_attrs(void) {
    if (global.ttyfd < 0) return TB_OK;

    if (tcgetattr(global.ttyfd, &global.orig_tios) != 0) {
        global.last_errno = errno;
        return TB_ERR_TCGETATTR;
    }

    struct termios tios;
    memcpy(&tios, &global.orig_tios, sizeof(tios));
    global.has_orig_tios = 1;

    cfmakeraw(&tios);
    tios.c_cc[VMIN] = 1;
    tios.c_cc[VTIME] = 0;

    if (tcsetattr(global.ttyfd, TCSAFLUSH, &tios) != 0) {
        global.last_errno = errno;
        return TB_ERR_TCSETATTR;
    }

    return TB_OK;
}

int tb_printf_inner(int x, int y, uintattr_t fg, uintattr_t bg, size_t *out_w,
    const char *fmt, va_list vl) {
    int rv;
    char buf[TB_OPT_PRINTF_BUF];
    rv = vsnprintf(buf, sizeof(buf), fmt, vl);
    if (rv < 0 || rv >= (int)sizeof(buf)) {
        return TB_ERR;
    }
    return tb_print_ex(x, y, fg, bg, out_w, buf);
}

static int init_term_caps(void) {
    if (load_terminfo() == TB_OK) {
        return parse_terminfo_caps();
    }
    return load_builtin_caps();
}

static int init_cap_trie(void) {
    int rv, i;

    // Add caps from terminfo or built-in
    //
    // Collisions are expected as some terminfo entries have dupes. (For
    // example, att605-pc collides on TB_CAP_F4 and TB_CAP_DELETE.) First cap
    // in TB_CAP_* index order will win.
    //
    // TODO: Reorder TB_CAP_* so more critical caps come first.
    for (i = 0; i < TB_CAP__COUNT_KEYS; i++) {
        rv = cap_trie_add(global.caps[i], tb_key_i(i), 0);
        if (rv != TB_OK && rv != TB_ERR_CAP_COLLISION) return rv;
    }

    // Add built-in mod caps
    //
    // Collisions are OK here as well. This can happen if global.caps collides
    // with builtin_mod_caps. It is desirable to give precedence to global.caps
    // here.
    for (i = 0; builtin_mod_caps[i].cap != NULL; i++) {
        rv = cap_trie_add(builtin_mod_caps[i].cap, builtin_mod_caps[i].key,
            builtin_mod_caps[i].mod);
        if (rv != TB_OK && rv != TB_ERR_CAP_COLLISION) return rv;
    }

    return TB_OK;
}

static int cap_trie_add(const char *cap, uint16_t key, uint8_t mod) {
    struct cap_trie_t *next, *node = &global.cap_trie;
    size_t i, j;

    if (!cap || strlen(cap) <= 0) return TB_OK; // Nothing to do for empty caps

    for (i = 0; cap[i] != '\0'; i++) {
        char c = cap[i];
        next = NULL;

        // Check if c is already a child of node
        for (j = 0; j < node->nchildren; j++) {
            if (node->children[j].c == c) {
                next = &node->children[j];
                break;
            }
        }
        if (!next) {
            // We need to add a new child to node
            node->nchildren += 1;
            node->children = (struct cap_trie_t *)tb_realloc(node->children,
                sizeof(*node) * node->nchildren);
            if (!node->children) {
                return TB_ERR_MEM;
            }
            next = &node->children[node->nchildren - 1];
            memset(next, 0, sizeof(*next));
            next->c = c;
        }

        // Continue
        node = next;
    }

    if (node->is_leaf) {
        // Already a leaf here
        return TB_ERR_CAP_COLLISION;
    }

    node->is_leaf = 1;
    node->key = key;
    node->mod = mod;
    return TB_OK;
}

static int cap_trie_find(const char *buf, size_t nbuf, struct cap_trie_t **last,
    size_t *depth) {
    struct cap_trie_t *next, *node = &global.cap_trie;
    size_t i, j;
    *last = node;
    *depth = 0;
    for (i = 0; i < nbuf; i++) {
        char c = buf[i];
        next = NULL;

        // Find c in node.children
        for (j = 0; j < node->nchildren; j++) {
            if (node->children[j].c == c) {
                next = &node->children[j];
                break;
            }
        }
        if (!next) {
            // Not found
            return TB_OK;
        }
        node = next;
        *last = node;
        *depth += 1;
        if (node->is_leaf && node->nchildren < 1) {
            break;
        }
    }
    return TB_OK;
}

static int cap_trie_deinit(struct cap_trie_t *node) {
    size_t j;
    for (j = 0; j < node->nchildren; j++) {
        cap_trie_deinit(&node->children[j]);
    }
    if (node->children) tb_free(node->children);
    memset(node, 0, sizeof(*node));
    return TB_OK;
}

static int init_resize_handler(void) {
    if (pipe(global.resize_pipefd) != 0) {
        global.last_errno = errno;
        return TB_ERR_RESIZE_PIPE;
    }

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = handle_resize;
    if (sigaction(SIGWINCH, &sa, NULL) != 0) {
        global.last_errno = errno;
        return TB_ERR_RESIZE_SIGACTION;
    }

    return TB_OK;
}

static int send_init_escape_codes(void) {
    int rv;
    if_err_return(rv, bytebuf_puts(&global.out, global.caps[TB_CAP_ENTER_CA]));
    if_err_return(rv,
        bytebuf_puts(&global.out, global.caps[TB_CAP_ENTER_KEYPAD]));
    if_err_return(rv,
        bytebuf_puts(&global.out, global.caps[TB_CAP_HIDE_CURSOR]));
    return TB_OK;
}

static int send_clear(void) {
    int rv;

    if_err_return(rv, send_attr(global.fg, global.bg));
    if_err_return(rv,
        bytebuf_puts(&global.out, global.caps[TB_CAP_CLEAR_SCREEN]));

    if_err_return(rv, send_cursor_if(global.cursor_x, global.cursor_y));
    if_err_return(rv, bytebuf_flush(&global.out, global.wfd));

    global.last_x = -1;
    global.last_y = -1;

    return TB_OK;
}

static int update_term_size(void) {
    int rv, ioctl_errno;

    if (global.ttyfd < 0) return TB_OK;

    struct winsize sz;
    memset(&sz, 0, sizeof(sz));

    // Try ioctl TIOCGWINSZ
    if (ioctl(global.ttyfd, TIOCGWINSZ, &sz) == 0) {
        global.width = sz.ws_col;
        global.height = sz.ws_row;
        return TB_OK;
    }
    ioctl_errno = errno;

    // Try >cursor(9999,9999), >u7, <u6
    if_ok_return(rv, update_term_size_via_esc());

    global.last_errno = ioctl_errno;
    return TB_ERR_RESIZE_IOCTL;
}

static int update_term_size_via_esc(void) {
#ifndef TB_RESIZE_FALLBACK_MS
#define TB_RESIZE_FALLBACK_MS 1000
#endif

    char move_and_report[] = "\x1b[9999;9999H\x1b[6n";
    ssize_t write_rv =
        write(global.wfd, move_and_report, strlen(move_and_report));
    if (write_rv != (ssize_t)strlen(move_and_report)) {
        return TB_ERR_RESIZE_WRITE;
    }

    fd_set fds;
    FD_ZERO(&fds);
    FD_SET(global.rfd, &fds);

    struct timeval timeout;
    timeout.tv_sec = 0;
    timeout.tv_usec = TB_RESIZE_FALLBACK_MS * 1000;

    int select_rv = select(global.rfd + 1, &fds, NULL, NULL, &timeout);

    if (select_rv != 1) {
        global.last_errno = errno;
        return TB_ERR_RESIZE_POLL;
    }

    char buf[TB_OPT_READ_BUF];
    ssize_t read_rv = read(global.rfd, buf, sizeof(buf) - 1);
    if (read_rv < 1) {
        global.last_errno = errno;
        return TB_ERR_RESIZE_READ;
    }
    buf[read_rv] = '\0';

    int rw, rh;
    if (sscanf(buf, "\x1b[%d;%dR", &rh, &rw) != 2) {
        return TB_ERR_RESIZE_SSCANF;
    }

    global.width = rw;
    global.height = rh;
    return TB_OK;
}

static int init_cellbuf(void) {
    int rv;
    if_err_return(rv, cellbuf_init(&global.back, global.width, global.height));
    if_err_return(rv, cellbuf_init(&global.front, global.width, global.height));
    if_err_return(rv, cellbuf_clear(&global.back));
    if_err_return(rv, cellbuf_clear(&global.front));
    return TB_OK;
}

static int tb_deinit(void) {
    if (global.caps[0] != NULL && global.wfd >= 0) {
        bytebuf_puts(&global.out, global.caps[TB_CAP_SHOW_CURSOR]);
        bytebuf_puts(&global.out, global.caps[TB_CAP_SGR0]);
        bytebuf_puts(&global.out, global.caps[TB_CAP_CLEAR_SCREEN]);
        bytebuf_puts(&global.out, global.caps[TB_CAP_EXIT_CA]);
        bytebuf_puts(&global.out, global.caps[TB_CAP_EXIT_KEYPAD]);
        bytebuf_puts(&global.out, TB_HARDCAP_EXIT_MOUSE);
        bytebuf_flush(&global.out, global.wfd);
    }
    if (global.ttyfd >= 0) {
        if (global.has_orig_tios) {
            tcsetattr(global.ttyfd, TCSAFLUSH, &global.orig_tios);
        }
        if (global.ttyfd_open) {
            close(global.ttyfd);
            global.ttyfd_open = 0;
        }
    }

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = SIG_DFL;
    sigaction(SIGWINCH, &sa, NULL);
    if (global.resize_pipefd[0] >= 0) close(global.resize_pipefd[0]);
    if (global.resize_pipefd[1] >= 0) close(global.resize_pipefd[1]);

    cellbuf_free(&global.back);
    cellbuf_free(&global.front);
    bytebuf_free(&global.in);
    bytebuf_free(&global.out);

    if (global.terminfo) tb_free(global.terminfo);

    cap_trie_deinit(&global.cap_trie);

    tb_reset();
    return TB_OK;
}

static int load_terminfo(void) {
    int rv;
    char tmp[TB_PATH_MAX];

    // See terminfo(5) "Fetching Compiled Descriptions" for a description of
    // this behavior. Some of these paths are compile-time ncurses options, so
    // best guesses are used here.
    const char *term = getenv("TERM");
    if (!term) return TB_ERR;

    // If TERMINFO is set, try that directory and stop
    const char *terminfo = getenv("TERMINFO");
    if (terminfo) return load_terminfo_from_path(terminfo, term);

    // Next try ~/.terminfo
    const char *home = getenv("HOME");
    if (home) {
        snprintf_or_return(rv, tmp, sizeof(tmp), "%s/.terminfo", home);
        if_ok_return(rv, load_terminfo_from_path(tmp, term));
    }

    // Next try TERMINFO_DIRS
    //
    // Note, empty entries are supposed to be interpretted as the "compiled-in
    // default", which is of course system-dependent. Previously /etc/terminfo
    // was used here. Let's skip empty entries altogether rather than give
    // precedence to a guess, and check common paths after this loop.
    const char *dirs = getenv("TERMINFO_DIRS");
    if (dirs) {
        snprintf_or_return(rv, tmp, sizeof(tmp), "%s", dirs);
        char *dir = strtok(tmp, ":");
        while (dir) {
            const char *cdir = dir;
            if (*cdir != '\0') {
                if_ok_return(rv, load_terminfo_from_path(cdir, term));
            }
            dir = strtok(NULL, ":");
        }
    }

#ifdef TB_TERMINFO_DIR
    if_ok_return(rv, load_terminfo_from_path(TB_TERMINFO_DIR, term));
#endif
    if_ok_return(rv, load_terminfo_from_path("/usr/local/etc/terminfo", term));
    if_ok_return(rv,
        load_terminfo_from_path("/usr/local/share/terminfo", term));
    if_ok_return(rv, load_terminfo_from_path("/usr/local/lib/terminfo", term));
    if_ok_return(rv, load_terminfo_from_path("/etc/terminfo", term));
    if_ok_return(rv, load_terminfo_from_path("/usr/share/terminfo", term));
    if_ok_return(rv, load_terminfo_from_path("/usr/lib/terminfo", term));
    if_ok_return(rv, load_terminfo_from_path("/usr/share/lib/terminfo", term));
    if_ok_return(rv, load_terminfo_from_path("/lib/terminfo", term));

    return TB_ERR;
}

static int load_terminfo_from_path(const char *path, const char *term) {
    int rv;
    char tmp[TB_PATH_MAX];

    // Look for term at this terminfo location, e.g., <terminfo>/x/xterm
    snprintf_or_return(rv, tmp, sizeof(tmp), "%s/%c/%s", path, term[0], term);
    if_ok_return(rv, read_terminfo_path(tmp));

#ifdef __APPLE__
    // Try the Darwin equivalent path, e.g., <terminfo>/78/xterm
    snprintf_or_return(rv, tmp, sizeof(tmp), "%s/%x/%s", path, term[0], term);
    return read_terminfo_path(tmp);
#endif

    return TB_ERR;
}

static int read_terminfo_path(const char *path) {
    FILE *fp = fopen(path, "rb");
    if (!fp) return TB_ERR;

    struct stat st;
    if (fstat(fileno(fp), &st) != 0) {
        fclose(fp);
        return TB_ERR;
    }

    size_t fsize = st.st_size;
    char *data = (char *)tb_malloc(fsize);
    if (!data) {
        fclose(fp);
        return TB_ERR;
    }

    if (fread(data, 1, fsize, fp) != fsize) {
        fclose(fp);
        tb_free(data);
        return TB_ERR;
    }

    global.terminfo = data;
    global.nterminfo = fsize;

    fclose(fp);
    return TB_OK;
}

static int parse_terminfo_caps(void) {
    // See term(5) "LEGACY STORAGE FORMAT" and "EXTENDED STORAGE FORMAT" for a
    // description of this behavior.

    // Ensure there's at least a header's worth of data
    if (global.nterminfo < 6 * (int)sizeof(int16_t)) return TB_ERR;

    int16_t magic_number, nbytes_names, nbytes_bools, num_ints, num_offsets,
        nbytes_strings;
    size_t nbytes_header = 6 * sizeof(int16_t);
    // header[0] the magic number (octal 0432 or 01036)
    // header[1] the size, in bytes, of the names section
    // header[2] the number of bytes in the boolean section
    // header[3] the number of short integers in the numbers section
    // header[4] the number of offsets (short integers) in the strings section
    // header[5] the size, in bytes, of the string table
    get_terminfo_int16(0 * sizeof(int16_t), &magic_number);
    get_terminfo_int16(1 * sizeof(int16_t), &nbytes_names);
    get_terminfo_int16(2 * sizeof(int16_t), &nbytes_bools);
    get_terminfo_int16(3 * sizeof(int16_t), &num_ints);
    get_terminfo_int16(4 * sizeof(int16_t), &num_offsets);
    get_terminfo_int16(5 * sizeof(int16_t), &nbytes_strings);

    // Legacy ints are 16-bit, extended ints are 32-bit
    const int bytes_per_int = magic_number == 01036 ? 4  // 32-bit
                                                    : 2; // 16-bit

    // > Between the boolean section and the number section, a null byte will be
    // > inserted, if necessary, to ensure that the number section begins on an
    // > even byte
    const int align_offset = (nbytes_names + nbytes_bools) % 2 != 0 ? 1 : 0;

    const int pos_str_offsets =
        nbytes_header  // header (12 bytes)
        + nbytes_names // length of names section
        + nbytes_bools // length of boolean section
        + align_offset +
        (num_ints * bytes_per_int); // length of numbers section

    const int pos_str_table =
        pos_str_offsets +
        (num_offsets * sizeof(int16_t)); // length of string offsets table

    // Load caps
    int i;
    for (i = 0; i < TB_CAP__COUNT; i++) {
        const char *cap = get_terminfo_string(pos_str_offsets, num_offsets,
            pos_str_table, nbytes_strings, terminfo_cap_indexes[i]);
        if (!cap) {
            // Something is not right
            return TB_ERR;
        }
        global.caps[i] = cap;
    }

    return TB_OK;
}

static int load_builtin_caps(void) {
    int i, j;
    const char *term = getenv("TERM");

    if (!term) return TB_ERR_NO_TERM;

    // Check for exact TERM match
    for (i = 0; builtin_terms[i].name != NULL; i++) {
        if (strcmp(term, builtin_terms[i].name) == 0) {
            for (j = 0; j < TB_CAP__COUNT; j++) {
                global.caps[j] = builtin_terms[i].caps[j];
            }
            return TB_OK;
        }
    }

    // Check for partial TERM or alias match
    for (i = 0; builtin_terms[i].name != NULL; i++) {
        if (strstr(term, builtin_terms[i].name) != NULL ||
            (*(builtin_terms[i].alias) != '\0' &&
                strstr(term, builtin_terms[i].alias) != NULL))
        {
            for (j = 0; j < TB_CAP__COUNT; j++) {
                global.caps[j] = builtin_terms[i].caps[j];
            }
            return TB_OK;
        }
    }

    return TB_ERR_UNSUPPORTED_TERM;
}

static const char *get_terminfo_string(int16_t offsets_pos, int16_t offsets_len,
    int16_t table_pos, int16_t table_size, int16_t index) {
    if (index >= offsets_len) {
        // An index beyond the offset table indicates absent
        // See `convert_strings` in tinfo `read_entry.c`
        return "";
    }

    int16_t table_offset;
    int table_offset_offset = (int)offsets_pos + (index * (int)sizeof(int16_t));
    if (get_terminfo_int16(table_offset_offset, &table_offset) != TB_OK) {
        // offset beyond end of terminfo entry
        // Truncated/corrupt terminfo entry?
        return NULL;
    }

    if (table_offset < 0 || table_offset >= table_size) {
        // A negative offset indicates absent
        // An offset beyond the string table indicates absent
        // See `convert_strings` in tinfo `read_entry.c`
        return "";
    }

    int str_offset = (int)table_pos + (int)table_offset;
    if (str_offset >= (int)global.nterminfo) {
        // string beyond end of terminfo entry
        // Truncated/corrupt terminfo entry?
        return NULL;
    }

    return (const char *)(global.terminfo + str_offset);
}

static int get_terminfo_int16(int offset, int16_t *val) {
    if (offset < 0 || offset >= (int)global.nterminfo) {
        *val = -1;
        return TB_ERR;
    }
    memcpy(val, global.terminfo + offset, sizeof(int16_t));
    return TB_OK;
}

static int wait_event(struct tb_event *event, int timeout) {
    int rv;
    char buf[TB_OPT_READ_BUF];

    memset(event, 0, sizeof(*event));
    if_ok_return(rv, extract_event(event));

    fd_set fds;
    struct timeval tv;
    tv.tv_sec = timeout / 1000;
    tv.tv_usec = (timeout - (tv.tv_sec * 1000)) * 1000;

    do {
        FD_ZERO(&fds);
        FD_SET(global.rfd, &fds);
        FD_SET(global.resize_pipefd[0], &fds);

        int maxfd = global.resize_pipefd[0] > global.rfd
                        ? global.resize_pipefd[0]
                        : global.rfd;

        int select_rv =
            select(maxfd + 1, &fds, NULL, NULL, (timeout < 0) ? NULL : &tv);

        if (select_rv < 0) {
            // Let EINTR/EAGAIN bubble up
            global.last_errno = errno;
            return TB_ERR_POLL;
        } else if (select_rv == 0) {
            return TB_ERR_NO_EVENT;
        }

        int tty_has_events = (FD_ISSET(global.rfd, &fds));
        int resize_has_events = (FD_ISSET(global.resize_pipefd[0], &fds));

        if (tty_has_events) {
            ssize_t read_rv = read(global.rfd, buf, sizeof(buf));
            if (read_rv < 0) {
                global.last_errno = errno;
                return TB_ERR_READ;
            } else if (read_rv > 0) {
                bytebuf_nputs(&global.in, buf, read_rv);
            }
        }

        if (resize_has_events) {
            int ignore = 0;
            read(global.resize_pipefd[0], &ignore, sizeof(ignore));
            // TODO: Harden against errors encountered mid-resize
            if_err_return(rv, update_term_size());
            if_err_return(rv, resize_cellbufs());
            event->type = TB_EVENT_RESIZE;
            event->w = global.width;
            event->h = global.height;
            return TB_OK;
        }

        memset(event, 0, sizeof(*event));
        if_ok_return(rv, extract_event(event));
    } while (timeout == -1);

    return rv;
}

static int extract_event(struct tb_event *event) {
    int rv;
    struct bytebuf_t *in = &global.in;

    if (in->len == 0) return TB_ERR;

    if (in->buf[0] == '\x1b') {
        // Escape sequence?
        // In TB_INPUT_ESC, skip if the buffer is a single escape char
        if (!((global.input_mode & TB_INPUT_ESC) && in->len == 1)) {
            if_ok_or_need_more_return(rv, extract_esc(event));
        }

        // Escape key?
        if (global.input_mode & TB_INPUT_ESC) {
            event->type = TB_EVENT_KEY;
            event->ch = 0;
            event->key = TB_KEY_ESC;
            event->mod = 0;
            bytebuf_shift(in, 1);
            return TB_OK;
        }

        // Recurse for alt key
        event->mod |= TB_MOD_ALT;
        bytebuf_shift(in, 1);
        return extract_event(event);
    }

    // ASCII control key?
    int is_ctrl =
        (uint16_t)in->buf[0] < TB_KEY_SPACE || in->buf[0] == TB_KEY_BACKSPACE2;
    if (is_ctrl) {
        event->type = TB_EVENT_KEY;
        event->ch = 0;
        event->key = (uint16_t)in->buf[0];
        event->mod |= TB_MOD_CTRL;
        bytebuf_shift(in, 1);
        return TB_OK;
    }

    // UTF-8?
    if (in->len >= (size_t)tb_utf8_char_length(in->buf[0])) {
        event->type = TB_EVENT_KEY;
        tb_utf8_char_to_unicode(&event->ch, in->buf);
        event->key = 0;
        bytebuf_shift(in, tb_utf8_char_length(in->buf[0]));
        return TB_OK;
    }

    // Need more input
    return TB_ERR;
}

static int extract_esc(struct tb_event *event) {
    int rv;
    if_ok_or_need_more_return(rv, extract_esc_user(event, 0));
    if_ok_or_need_more_return(rv, extract_esc_cap(event));
    if_ok_or_need_more_return(rv, extract_esc_mouse(event));
    if_ok_or_need_more_return(rv, extract_esc_user(event, 1));
    return TB_ERR;
}

static int extract_esc_user(struct tb_event *event, int is_post) {
    int rv;
    size_t consumed = 0;
    struct bytebuf_t *in = &global.in;
    int (*fn)(struct tb_event *, size_t *);

    fn = is_post ? global.fn_extract_esc_post : global.fn_extract_esc_pre;

    if (!fn) return TB_ERR;

    rv = fn(event, &consumed);
    if (rv == TB_OK) bytebuf_shift(in, consumed);

    if_ok_or_need_more_return(rv, rv);
    return TB_ERR;
}

static int extract_esc_cap(struct tb_event *event) {
    int rv;
    struct bytebuf_t *in = &global.in;
    struct cap_trie_t *node;
    size_t depth;

    if_err_return(rv, cap_trie_find(in->buf, in->len, &node, &depth));
    if (node->is_leaf) {
        // Found a leaf node
        event->type = TB_EVENT_KEY;
        event->ch = 0;
        event->key = node->key;
        event->mod = node->mod;
        bytebuf_shift(in, depth);
        return TB_OK;
    } else if (node->nchildren > 0 && in->len <= depth) {
        // Found a branch node (not enough input)
        return TB_ERR_NEED_MORE;
    }

    return TB_ERR;
}

static int extract_esc_mouse(struct tb_event *event) {
    struct bytebuf_t *in = &global.in;

    enum { TYPE_VT200 = 0, TYPE_1006, TYPE_1015, TYPE_MAX };

    const char *cmp[TYPE_MAX] = {//
        // X10 mouse encoding, the simplest one
        // \x1b [ M Cb Cx Cy
        [TYPE_VT200] = "\x1b[M",
        // xterm 1006 extended mode or urxvt 1015 extended mode
        // xterm: \x1b [ < Cb ; Cx ; Cy (M or m)
        [TYPE_1006] = "\x1b[<",
        // urxvt: \x1b [ Cb ; Cx ; Cy M
        [TYPE_1015] = "\x1b["};

    int type = 0;
    int ret = TB_ERR;

    // Unrolled at compile-time (probably)
    for (; type < TYPE_MAX; type++) {
        size_t size = strlen(cmp[type]);

        if (in->len >= size && (strncmp(cmp[type], in->buf, size)) == 0) {
            break;
        }
    }

    if (type == TYPE_MAX) {
        ret = TB_ERR; // No match
        return ret;
    }

    size_t buf_shift = 0;

    switch (type) {
        case TYPE_VT200:
            if (in->len >= 6) {
                int b = in->buf[3] - 0x20;
                int fail = 0;

                switch (b & 3) {
                    case 0:
                        event->key = ((b & 64) != 0) ? TB_KEY_MOUSE_WHEEL_UP
                                                     : TB_KEY_MOUSE_LEFT;
                        break;
                    case 1:
                        event->key = ((b & 64) != 0) ? TB_KEY_MOUSE_WHEEL_DOWN
                                                     : TB_KEY_MOUSE_MIDDLE;
                        break;
                    case 2:
                        event->key = TB_KEY_MOUSE_RIGHT;
                        break;
                    case 3:
                        event->key = TB_KEY_MOUSE_RELEASE;
                        break;
                    default:
                        ret = TB_ERR;
                        fail = 1;
                        break;
                }

                if (!fail) {
                    if ((b & 32) != 0) {
                        event->mod |= TB_MOD_MOTION;
                    }

                    // the coord is 1,1 for upper left
                    event->x = ((uint8_t)in->buf[4]) - 0x21;
                    event->y = ((uint8_t)in->buf[5]) - 0x21;

                    ret = TB_OK;
                }

                buf_shift = 6;
            }
            break;
        case TYPE_1006:
            // fallthrough
        case TYPE_1015: {
            size_t index_fail = (size_t)-1;

            enum {
                FIRST_M = 0,
                FIRST_SEMICOLON,
                LAST_SEMICOLON,
                FIRST_LAST_MAX
            };

            size_t indices[FIRST_LAST_MAX] = {index_fail, index_fail,
                index_fail};
            int m_is_capital = 0;

            for (size_t i = 0; i < in->len; i++) {
                if (in->buf[i] == ';') {
                    if (indices[FIRST_SEMICOLON] == index_fail) {
                        indices[FIRST_SEMICOLON] = i;
                    } else {
                        indices[LAST_SEMICOLON] = i;
                    }
                } else if (indices[FIRST_M] == index_fail) {
                    if (in->buf[i] == 'm' || in->buf[i] == 'M') {
                        m_is_capital = (in->buf[i] == 'M');
                        indices[FIRST_M] = i;
                    }
                }
            }

            if (indices[FIRST_M] == index_fail ||
                indices[FIRST_SEMICOLON] == index_fail ||
                indices[LAST_SEMICOLON] == index_fail)
            {
                ret = TB_ERR;
            } else {
                int start = (type == TYPE_1015 ? 2 : 3);

                unsigned n1 = strtoul(&in->buf[start], NULL, 10);
                unsigned n2 =
                    strtoul(&in->buf[indices[FIRST_SEMICOLON] + 1], NULL, 10);
                unsigned n3 =
                    strtoul(&in->buf[indices[LAST_SEMICOLON] + 1], NULL, 10);

                if (type == TYPE_1015) {
                    n1 -= 0x20;
                }

                int fail = 0;

                switch (n1 & 3) {
                    case 0:
                        event->key = ((n1 & 64) != 0) ? TB_KEY_MOUSE_WHEEL_UP
                                                      : TB_KEY_MOUSE_LEFT;
                        break;
                    case 1:
                        event->key = ((n1 & 64) != 0) ? TB_KEY_MOUSE_WHEEL_DOWN
                                                      : TB_KEY_MOUSE_MIDDLE;
                        break;
                    case 2:
                        event->key = TB_KEY_MOUSE_RIGHT;
                        break;
                    case 3:
                        event->key = TB_KEY_MOUSE_RELEASE;
                        break;
                    default:
                        ret = TB_ERR;
                        fail = 1;
                        break;
                }

                buf_shift = in->len;

                if (!fail) {
                    if (!m_is_capital) {
                        // on xterm mouse release is signaled by lowercase m
                        event->key = TB_KEY_MOUSE_RELEASE;
                    }

                    if ((n1 & 32) != 0) {
                        event->mod |= TB_MOD_MOTION;
                    }

                    event->x = ((uint8_t)n2) - 1;
                    event->y = ((uint8_t)n3) - 1;

                    ret = TB_OK;
                }
            }
        } break;
        case TYPE_MAX:
            ret = TB_ERR;
    }

    if (buf_shift > 0) bytebuf_shift(in, buf_shift);

    if (ret == TB_OK) event->type = TB_EVENT_MOUSE;

    return ret;
}

static int resize_cellbufs(void) {
    int rv;
    if_err_return(rv,
        cellbuf_resize(&global.back, global.width, global.height));
    if_err_return(rv,
        cellbuf_resize(&global.front, global.width, global.height));
    if_err_return(rv, cellbuf_clear(&global.front));
    if_err_return(rv, send_clear());
    return TB_OK;
}

static void handle_resize(int sig) {
    int errno_copy = errno;
    write(global.resize_pipefd[1], &sig, sizeof(sig));
    errno = errno_copy;
}

static int send_attr(uintattr_t fg, uintattr_t bg) {
    int rv;

    if (fg == global.last_fg && bg == global.last_bg) {
        return TB_OK;
    }

    if_err_return(rv, bytebuf_puts(&global.out, global.caps[TB_CAP_SGR0]));

    uint32_t cfg, cbg;
    switch (global.output_mode) {
        default:
        case TB_OUTPUT_NORMAL:
            // The minus 1 below is because our colors are 1-indexed starting
            // from black. Black is represented by a 30, 40, 90, or 100 for fg,
            // bg, bright fg, or bright bg respectively. Red is 31, 41, 91,
            // 101, etc.
            cfg = (fg & TB_BRIGHT ? 90 : 30) + (fg & 0x0f) - 1;
            cbg = (bg & TB_BRIGHT ? 100 : 40) + (bg & 0x0f) - 1;
            break;

        case TB_OUTPUT_256:
            cfg = fg & 0xff;
            cbg = bg & 0xff;
            if (fg & TB_HI_BLACK) cfg = 0;
            if (bg & TB_HI_BLACK) cbg = 0;
            break;

        case TB_OUTPUT_216:
            cfg = fg & 0xff;
            cbg = bg & 0xff;
            if (cfg > 216) cfg = 216;
            if (cbg > 216) cbg = 216;
            cfg += 0x0f;
            cbg += 0x0f;
            break;

        case TB_OUTPUT_GRAYSCALE:
            cfg = fg & 0xff;
            cbg = bg & 0xff;
            if (cfg > 24) cfg = 24;
            if (cbg > 24) cbg = 24;
            cfg += 0xe7;
            cbg += 0xe7;
            break;

#if TB_OPT_ATTR_W >= 32
        case TB_OUTPUT_TRUECOLOR:
            cfg = fg & 0xffffff;
            cbg = bg & 0xffffff;
            if (fg & TB_HI_BLACK) cfg = 0;
            if (bg & TB_HI_BLACK) cbg = 0;
            break;
#endif
    }

    if (fg & TB_BOLD)
        if_err_return(rv, bytebuf_puts(&global.out, global.caps[TB_CAP_BOLD]));

    if (fg & TB_BLINK)
        if_err_return(rv, bytebuf_puts(&global.out, global.caps[TB_CAP_BLINK]));

    if (fg & TB_UNDERLINE)
        if_err_return(rv,
            bytebuf_puts(&global.out, global.caps[TB_CAP_UNDERLINE]));

    if (fg & TB_ITALIC)
        if_err_return(rv,
            bytebuf_puts(&global.out, global.caps[TB_CAP_ITALIC]));

    if (fg & TB_DIM)
        if_err_return(rv, bytebuf_puts(&global.out, global.caps[TB_CAP_DIM]));

#if TB_OPT_ATTR_W == 64
    if (fg & TB_STRIKEOUT)
        if_err_return(rv, bytebuf_puts(&global.out, TB_HARDCAP_STRIKEOUT));

    if (fg & TB_UNDERLINE_2)
        if_err_return(rv, bytebuf_puts(&global.out, TB_HARDCAP_UNDERLINE_2));

    if (fg & TB_OVERLINE)
        if_err_return(rv, bytebuf_puts(&global.out, TB_HARDCAP_OVERLINE));

    if (fg & TB_INVISIBLE)
        if_err_return(rv,
            bytebuf_puts(&global.out, global.caps[TB_CAP_INVISIBLE]));
#endif

    if ((fg & TB_REVERSE) || (bg & TB_REVERSE))
        if_err_return(rv,
            bytebuf_puts(&global.out, global.caps[TB_CAP_REVERSE]));

    int fg_is_default = (fg & 0xff) == 0;
    int bg_is_default = (bg & 0xff) == 0;
    if (global.output_mode == TB_OUTPUT_256) {
        if (fg & TB_HI_BLACK) fg_is_default = 0;
        if (bg & TB_HI_BLACK) bg_is_default = 0;
    }
#if TB_OPT_ATTR_W >= 32
    if (global.output_mode == TB_OUTPUT_TRUECOLOR) {
        fg_is_default = ((fg & 0xffffff) == 0) && ((fg & TB_HI_BLACK) == 0);
        bg_is_default = ((bg & 0xffffff) == 0) && ((bg & TB_HI_BLACK) == 0);
    }
#endif

    if_err_return(rv, send_sgr(cfg, cbg, fg_is_default, bg_is_default));

    global.last_fg = fg;
    global.last_bg = bg;

    return TB_OK;
}

static int send_sgr(uint32_t cfg, uint32_t cbg, int fg_is_default,
    int bg_is_default) {
    int rv;
    char nbuf[32];

    if (fg_is_default && bg_is_default) {
        return TB_OK;
    }

    switch (global.output_mode) {
        default:
        case TB_OUTPUT_NORMAL:
            send_literal(rv, "\x1b[");
            if (!fg_is_default) {
                send_num(rv, nbuf, cfg);
                if (!bg_is_default) {
                    send_literal(rv, ";");
                }
            }
            if (!bg_is_default) {
                send_num(rv, nbuf, cbg);
            }
            send_literal(rv, "m");
            break;

        case TB_OUTPUT_256:
        case TB_OUTPUT_216:
        case TB_OUTPUT_GRAYSCALE:
            send_literal(rv, "\x1b[");
            if (!fg_is_default) {
                send_literal(rv, "38;5;");
                send_num(rv, nbuf, cfg);
                if (!bg_is_default) {
                    send_literal(rv, ";");
                }
            }
            if (!bg_is_default) {
                send_literal(rv, "48;5;");
                send_num(rv, nbuf, cbg);
            }
            send_literal(rv, "m");
            break;

#if TB_OPT_ATTR_W >= 32
        case TB_OUTPUT_TRUECOLOR:
            send_literal(rv, "\x1b[");
            if (!fg_is_default) {
                send_literal(rv, "38;2;");
                send_num(rv, nbuf, (cfg >> 16) & 0xff);
                send_literal(rv, ";");
                send_num(rv, nbuf, (cfg >> 8) & 0xff);
                send_literal(rv, ";");
                send_num(rv, nbuf, cfg & 0xff);
                if (!bg_is_default) {
                    send_literal(rv, ";");
                }
            }
            if (!bg_is_default) {
                send_literal(rv, "48;2;");
                send_num(rv, nbuf, (cbg >> 16) & 0xff);
                send_literal(rv, ";");
                send_num(rv, nbuf, (cbg >> 8) & 0xff);
                send_literal(rv, ";");
                send_num(rv, nbuf, cbg & 0xff);
            }
            send_literal(rv, "m");
            break;
#endif
    }
    return TB_OK;
}

static int send_cursor_if(int x, int y) {
    int rv;
    char nbuf[32];
    if (x < 0 || y < 0) {
        return TB_OK;
    }
    send_literal(rv, "\x1b[");
    send_num(rv, nbuf, y + 1);
    send_literal(rv, ";");
    send_num(rv, nbuf, x + 1);
    send_literal(rv, "H");
    return TB_OK;
}

static int send_char(int x, int y, uint32_t ch) {
    return send_cluster(x, y, &ch, 1);
}

static int send_cluster(int x, int y, uint32_t *ch, size_t nch) {
    int rv;
    char chu8[8];

    if (global.last_x != x - 1 || global.last_y != y) {
        if_err_return(rv, send_cursor_if(x, y));
    }
    global.last_x = x;
    global.last_y = y;

    int i;
    for (i = 0; i < (int)nch; i++) {
        uint32_t ch32 = *(ch + i);
        if (!tb_iswprint(ch32)) {
            ch32 = 0xfffd; // replace non-printable codepoints with U+FFFD
        }
        int chu8_len = tb_utf8_unicode_to_char(chu8, ch32);
        if_err_return(rv, bytebuf_nputs(&global.out, chu8, (size_t)chu8_len));
    }

    return TB_OK;
}

static int convert_num(uint32_t num, char *buf) {
    int i, l = 0;
    char ch;
    do {
        buf[l++] = (char)('0' + (num % 10));
        num /= 10;
    } while (num);
    for (i = 0; i < l / 2; i++) {
        ch = buf[i];
        buf[i] = buf[l - 1 - i];
        buf[l - 1 - i] = ch;
    }
    return l;
}

static int cell_cmp(struct tb_cell *a, struct tb_cell *b) {
    if (a->ch != b->ch || a->fg != b->fg || a->bg != b->bg) {
        return 1;
    }
#ifdef TB_OPT_EGC
    if (a->nech != b->nech) {
        return 1;
    } else if (a->nech > 0) { // a->nech == b->nech
        return memcmp(a->ech, b->ech, a->nech);
    }
#endif
    return 0;
}

static int cell_copy(struct tb_cell *dst, struct tb_cell *src) {
#ifdef TB_OPT_EGC
    if (src->nech > 0) {
        return cell_set(dst, src->ech, src->nech, src->fg, src->bg);
    }
#endif
    return cell_set(dst, &src->ch, 1, src->fg, src->bg);
}

static int cell_set(struct tb_cell *cell, uint32_t *ch, size_t nch,
    uintattr_t fg, uintattr_t bg) {
    // TODO: iswprint ch?
    cell->ch = ch ? *ch : 0;
    cell->fg = fg;
    cell->bg = bg;
#ifdef TB_OPT_EGC
    if (nch <= 1) {
        cell->nech = 0;
    } else {
        int rv;
        if_err_return(rv, cell_reserve_ech(cell, nch + 1));
        memcpy(cell->ech, ch, sizeof(*ch) * nch);
        cell->ech[nch] = '\0';
        cell->nech = nch;
    }
#else
    (void)nch;
    (void)cell_reserve_ech;
#endif
    return TB_OK;
}

static int cell_reserve_ech(struct tb_cell *cell, size_t n) {
#ifdef TB_OPT_EGC
    if (cell->cech >= n) return TB_OK;
    cell->ech = (uint32_t *)tb_realloc(cell->ech, n * sizeof(cell->ch));
    if (!cell->ech) return TB_ERR_MEM;
    cell->cech = n;
    return TB_OK;
#else
    (void)cell;
    (void)n;
    return TB_ERR;
#endif
}

static int cell_free(struct tb_cell *cell) {
#ifdef TB_OPT_EGC
    if (cell->ech) tb_free(cell->ech);
#endif
    memset(cell, 0, sizeof(*cell));
    return TB_OK;
}

static int cellbuf_init(struct cellbuf_t *c, int w, int h) {
    c->cells = (struct tb_cell *)tb_malloc(sizeof(struct tb_cell) * w * h);
    if (!c->cells) return TB_ERR_MEM;
    memset(c->cells, 0, sizeof(struct tb_cell) * w * h);
    c->width = w;
    c->height = h;
    return TB_OK;
}

static int cellbuf_free(struct cellbuf_t *c) {
    if (c->cells) {
        int i;
        for (i = 0; i < c->width * c->height; i++) {
            cell_free(&c->cells[i]);
        }
        tb_free(c->cells);
    }
    memset(c, 0, sizeof(*c));
    return TB_OK;
}

static int cellbuf_clear(struct cellbuf_t *c) {
    int rv, i;
    uint32_t space = (uint32_t)' ';
    for (i = 0; i < c->width * c->height; i++) {
        if_err_return(rv,
            cell_set(&c->cells[i], &space, 1, global.fg, global.bg));
    }
    return TB_OK;
}

static int cellbuf_get(struct cellbuf_t *c, int x, int y,
    struct tb_cell **out) {
    if (!cellbuf_in_bounds(c, x, y)) {
        *out = NULL;
        return TB_ERR_OUT_OF_BOUNDS;
    }
    *out = &c->cells[(y * c->width) + x];
    return TB_OK;
}

static int cellbuf_in_bounds(struct cellbuf_t *c, int x, int y) {
    if (x < 0 || x >= c->width || y < 0 || y >= c->height) {
        return 0;
    }
    return 1;
}

static int cellbuf_resize(struct cellbuf_t *c, int w, int h) {
    int rv;

    int ow = c->width;
    int oh = c->height;

    if (ow == w && oh == h) {
        return TB_OK;
    }

    w = w < 1 ? 1 : w;
    h = h < 1 ? 1 : h;

    int minw = (w < ow) ? w : ow;
    int minh = (h < oh) ? h : oh;

    struct tb_cell *prev = c->cells;

    if_err_return(rv, cellbuf_init(c, w, h));
    if_err_return(rv, cellbuf_clear(c));

    int x, y;
    for (x = 0; x < minw; x++) {
        for (y = 0; y < minh; y++) {
            struct tb_cell *src, *dst;
            src = &prev[(y * ow) + x];
            if_err_return(rv, cellbuf_get(c, x, y, &dst));
            if_err_return(rv, cell_copy(dst, src));
        }
    }

    tb_free(prev);

    return TB_OK;
}

static int bytebuf_puts(struct bytebuf_t *b, const char *str) {
    if (!str || strlen(str) <= 0) return TB_OK; // Nothing to do for empty caps
    return bytebuf_nputs(b, str, (size_t)strlen(str));
}

static int bytebuf_nputs(struct bytebuf_t *b, const char *str, size_t nstr) {
    int rv;
    if_err_return(rv, bytebuf_reserve(b, b->len + nstr + 1));
    memcpy(b->buf + b->len, str, nstr);
    b->len += nstr;
    b->buf[b->len] = '\0';
    return TB_OK;
}

static int bytebuf_shift(struct bytebuf_t *b, size_t n) {
    if (n > b->len) n = b->len;
    size_t nmove = b->len - n;
    memmove(b->buf, b->buf + n, nmove);
    b->len -= n;
    return TB_OK;
}

static int bytebuf_flush(struct bytebuf_t *b, int fd) {
    if (b->len <= 0) return TB_OK;
    ssize_t write_rv = write(fd, b->buf, b->len);
    if (write_rv < 0 || (size_t)write_rv != b->len) {
        // Note, errno will be 0 on partial write
        global.last_errno = errno;
        return TB_ERR;
    }
    b->len = 0;
    return TB_OK;
}

static int bytebuf_reserve(struct bytebuf_t *b, size_t sz) {
    if (b->cap >= sz) return TB_OK;

    size_t newcap = b->cap > 0 ? b->cap : 1;
    while (newcap < sz) {
        newcap *= 2;
    }

    char *newbuf;
    if (b->buf) {
        newbuf = (char *)tb_realloc(b->buf, newcap);
    } else {
        newbuf = (char *)tb_malloc(newcap);
    }
    if (!newbuf) return TB_ERR_MEM;

    b->buf = newbuf;
    b->cap = newcap;
    return TB_OK;
}

static int bytebuf_free(struct bytebuf_t *b) {
    if (b->buf) tb_free(b->buf);
    memset(b, 0, sizeof(*b));
    return TB_OK;
}

int tb_iswprint(uint32_t ch) {
#ifdef TB_OPT_LIBC_WCHAR
    return iswprint((wint_t)ch);
#else
    return tb_iswprint_ex(ch, NULL);
#endif
}

int tb_wcwidth(uint32_t ch) {
#ifdef TB_OPT_LIBC_WCHAR
    return wcwidth((wchar_t)ch);
#else
    return tb_wcswidth(&ch, 1);
#endif
}

static int tb_wcswidth(uint32_t *ch, size_t nch) {
#ifdef TB_OPT_LIBC_WCHAR
    return wcswidth((wchar_t *)ch, nch);
#else
    int sw = 0;
    size_t i = 0;
    for (i = 0; i < nch; i++) {
        int w;
        tb_iswprint_ex(ch[i], &w);
        if (w < 0) return -1;
        sw += w;
    }
    return sw;
#endif
}

static int tb_iswprint_ex(uint32_t ch, int *w) {
#ifdef TB_OPT_LIBC_WCHAR
    if (w) *w = wcwidth((wint_t)ch);
    return iswprint(ch);
#else
    int lo = 0, hi = WCWIDTH_TABLE_LENGTH - 1;
    if (ch >= 0x20 && ch <= 0x7e) { // fast path for ASCII
        if (w) *w = 1;
        return 1;
    } else if (ch == 0) { // Special case for null, which is not represented in
        if (w) *w = 0;    // wcwidth_table since it's the only codepoint that is
        return 0;         // iswprint==0 but not wcwidth==-1. (It's wcwidth==0.)
    }
    while (lo <= hi) {
        int i = (lo + hi) / 2;
        if (ch < wcwidth_table[i].range_start) {
            hi = i - 1;
        } else if (ch > wcwidth_table[i].range_end) {
            lo = i + 1;
        } else {
            if (w) *w = wcwidth_table[i].width;
            return wcwidth_table[i].width >= 0 ? 1 : 0;
        }
    }
    if (w) *w = -1; // invalid codepoint
    return 0;
#endif
}

#endif // TB_IMPL
