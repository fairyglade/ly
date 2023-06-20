# Termbox
[Termbox](https://github.com/nsf/termbox)
was a promising Text User Interface (TUI) library.
Unfortunately, its original author
[changed his mind](https://github.com/nsf/termbox/issues/37#issuecomment-261075481)
about consoles and despite the
[community's efforts](https://github.com/nsf/termbox/pull/104#issuecomment-300308156)
to keep the library's development going, preferred to let it die. Before it happened,
[some people](https://wiki.musl-libc.org/alternatives.html)
already noticed the robustness of the initial architecture
[became compromised](https://github.com/nsf/termbox/commit/66c3f91b14e24510319bce6b5cc2fecf8cf5abff#commitcomment-3790714)
in a nonsensical refactoring frenzy. Now, the author refuses to merge features
like true-color support, invoking some
[spurious correlations](https://github.com/nsf/termbox/pull/104#issuecomment-300292223)
we will discuss no further.

## The new Termbox-next
This fork was made to restore the codebase to its original quality (before
[66c3f91](https://github.com/nsf/termbox/commit/66c3f91b14e24510319bce6b5cc2fecf8cf5abff))
while providing all the functionnalities of the current implementation.
This was achieved by branching at
[a2e217f](https://github.com/nsf/termbox/commit/a2e217f0fb97e6bbd589136ea3945f9d5a123d81)
and cherry-picking all the commits up to
[d63b83a](https://github.com/nsf/termbox/commit/d63b83af04e0fd6da836bb8f37e5cec72a1dc95a)
if they weren't harmful.

## Changes
A lot of things changed during the process:
 - *waf*, the original build system, was completely removed from the
   project and replaced by make.
 - anything related to python was removed as well

## Getting started
Termbox's interface only consists of 12 functions:
```
tb_init() // initialization
tb_shutdown() // shutdown

tb_width() // width of the terminal screen
tb_height() // height of the terminal screen

tb_clear() // clear buffer
tb_present() // sync internal buffer with terminal

tb_put_cell()
tb_change_cell()
tb_blit() // drawing functions

tb_select_input_mode() // change input mode
tb_peek_event() // peek a keyboard event
tb_poll_event() // wait for a keyboard event
```
See src/termbox.h header file for full detail.

## TL;DR
`make` to build a static version of the lib under bin/termbox.a
`cd src/demo && make` to build the example programs in src/demo/
