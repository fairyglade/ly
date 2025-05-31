const std = @import("std");
const interop = @import("interop.zig");
const enums = @import("enums.zig");
const Lang = @import("bigclock/Lang.zig");
const en = @import("bigclock/en.zig");
const fa = @import("bigclock/fa.zig");
const Cell = @import("tui/Cell.zig");

const Bigclock = enums.Bigclock;
pub const WIDTH = Lang.WIDTH;
pub const HEIGHT = Lang.HEIGHT;
pub const SIZE = Lang.SIZE;

pub fn clockCell(animate: bool, char: u8, fg: u32, bg: u32, bigclock: Bigclock) [SIZE]Cell {
    var cells: [SIZE]Cell = undefined;

    var tv: interop.system_time.timeval = undefined;
    _ = interop.system_time.gettimeofday(&tv, null);

    const clock_chars = toBigNumber(if (animate and char == ':' and @divTrunc(tv.tv_usec, 500000) != 0) ' ' else char, bigclock);
    for (0..cells.len) |i| cells[i] = Cell.init(clock_chars[i], fg, bg);

    return cells;
}

pub fn alphaBlit(x: usize, y: usize, tb_width: usize, tb_height: usize, cells: [SIZE]Cell) void {
    if (x + WIDTH >= tb_width or y + HEIGHT >= tb_height) return;

    for (0..HEIGHT) |yy| {
        for (0..WIDTH) |xx| {
            const cell = cells[yy * WIDTH + xx];
            cell.put(x + xx, y + yy);
        }
    }
}

fn toBigNumber(char: u8, bigclock: Bigclock) [SIZE]u21 {
    const locale_chars = switch (bigclock) {
        .fa => fa.locale_chars,
        .en => en.locale_chars,
        .none => unreachable,
    };
    return switch (char) {
        '0' => locale_chars.ZERO,
        '1' => locale_chars.ONE,
        '2' => locale_chars.TWO,
        '3' => locale_chars.THREE,
        '4' => locale_chars.FOUR,
        '5' => locale_chars.FIVE,
        '6' => locale_chars.SIX,
        '7' => locale_chars.SEVEN,
        '8' => locale_chars.EIGHT,
        '9' => locale_chars.NINE,
        ':' => locale_chars.S,
        else => locale_chars.E,
    };
}
