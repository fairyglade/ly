const std = @import("std");
const interop = @import("interop.zig");
const utils = @import("tui/utils.zig");
const enums = @import("enums.zig");
const Lang  = @import("bigclock/Lang.zig");
const en    = @import("bigclock/en.zig");
const fa    = @import("bigclock/fa.zig");

const termbox    = interop.termbox;
const Bigclock   = enums.Bigclock;
pub const WIDTH  = Lang.WIDTH;
pub const HEIGHT = Lang.HEIGHT;
pub const SIZE   = Lang.SIZE;

pub fn clockCell(animate: bool, char: u8, fg: u16, bg: u16, bigclock: Bigclock) [SIZE]utils.Cell {
    var cells: [SIZE]utils.Cell = undefined;

    var tv: interop.system_time.timeval = undefined;
    _ = interop.system_time.gettimeofday(&tv, null);

    const clock_chars = toBigNumber(if (animate and char == ':' and @divTrunc(tv.tv_usec, 500000) != 0) ' ' else char, bigclock);
    for (0..cells.len) |i| cells[i] = utils.initCell(clock_chars[i], fg, bg);

    return cells;
}

pub fn alphaBlit(x: usize, y: usize, tb_width: usize, tb_height: usize, cells: [SIZE]utils.Cell) void {
    if (x + WIDTH >= tb_width or y + HEIGHT >= tb_height) return;

    for (0..HEIGHT) |yy| {
        for (0..WIDTH) |xx| {
            const cell = cells[yy * WIDTH + xx];
            if (cell.ch != 0) utils.putCell(x + xx, y + yy, cell);
        }
    }
}

fn toBigNumber(char: u8, bigclock: Bigclock) []const u21 {
    const locale_chars = switch (bigclock) {
        .fa     => fa.locale_chars,
        .en     => en.locale_chars,
        .none   => unreachable,
    };
    return switch (char) {
        '0' => &locale_chars.ZERO,
        '1' => &locale_chars.ONE,
        '2' => &locale_chars.TWO,
        '3' => &locale_chars.THREE,
        '4' => &locale_chars.FOUR,
        '5' => &locale_chars.FIVE,
        '6' => &locale_chars.SIX,
        '7' => &locale_chars.SEVEN,
        '8' => &locale_chars.EIGHT,
        '9' => &locale_chars.NINE,
        ':' => &locale_chars.S,
        else => &locale_chars.E,
    };
}
