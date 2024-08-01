const std = @import("std");
const builtin = @import("builtin");
const interop = @import("interop.zig");
const utils = @import("tui/utils.zig");

const termbox = interop.termbox;

const X: u32 = if (builtin.os.tag == .linux or builtin.os.tag.isBSD()) 0x2593 else '#';
const O: u32 = 0;

pub const WIDTH = 5;
pub const HEIGHT = 5;
pub const SIZE = WIDTH * HEIGHT;

// zig fmt: off
const ZERO = [_]u21{
    X,X,X,X,X,
    X,X,O,X,X,
    X,X,O,X,X,
    X,X,O,X,X,
    X,X,X,X,X,
};
const ONE = [_]u21{
    O,O,O,X,X,
    O,O,O,X,X,
    O,O,O,X,X,
    O,O,O,X,X,
    O,O,O,X,X,
};
const TWO = [_]u21{
    X,X,X,X,X,
    O,O,O,X,X,
    X,X,X,X,X,
    X,X,O,O,O,
    X,X,X,X,X,
};
const THREE = [_]u21{
    X,X,X,X,X,
    O,O,O,X,X,
    X,X,X,X,X,
    O,O,O,X,X,
    X,X,X,X,X,
};
const FOUR = [_]u21{
    X,X,O,X,X,
    X,X,O,X,X,
    X,X,X,X,X,
    O,O,O,X,X,
    O,O,O,X,X,
};
const FIVE = [_]u21{
    X,X,X,X,X,
    X,X,O,O,O,
    X,X,X,X,X,
    O,O,O,X,X,
    X,X,X,X,X,
};
const SIX = [_]u21{
    X,X,X,X,X,
    X,X,O,O,O,
    X,X,X,X,X,
    X,X,O,X,X,
    X,X,X,X,X,
};
const SEVEN = [_]u21{
    X,X,X,X,X,
    O,O,O,X,X,
    O,O,O,X,X,
    O,O,O,X,X,
    O,O,O,X,X,
};
const EIGHT = [_]u21{
    X,X,X,X,X,
    X,X,O,X,X,
    X,X,X,X,X,
    X,X,O,X,X,
    X,X,X,X,X,
};
const NINE = [_]u21{
    X,X,X,X,X,
    X,X,O,X,X,
    X,X,X,X,X,
    O,O,O,X,X,
    X,X,X,X,X,
};
const S = [_]u21{
    O,O,O,O,O,
    O,O,X,O,O,
    O,O,O,O,O,
    O,O,X,O,O,
    O,O,O,O,O,
};
const E = [_]u21{
    O,O,O,O,O,
    O,O,O,O,O,
    O,O,O,O,O,
    O,O,O,O,O,
    O,O,O,O,O,
};
// zig fmt: on

pub fn clockCell(animate: bool, char: u8, fg: u16, bg: u16) [SIZE]termbox.tb_cell {
    var cells: [SIZE]termbox.tb_cell = undefined;

    var tv: interop.system_time.timeval = undefined;
    _ = interop.system_time.gettimeofday(&tv, null);

    const clock_chars = toBigNumber(if (animate and char == ':' and @divTrunc(tv.tv_usec, 500000) != 0) ' ' else char);
    for (0..cells.len) |i| cells[i] = utils.initCell(clock_chars[i], fg, bg);

    return cells;
}

pub fn alphaBlit(buffer: [*]termbox.tb_cell, x: usize, y: usize, tb_width: usize, tb_height: usize, cells: [SIZE]termbox.tb_cell) void {
    if (x + WIDTH >= tb_width or y + HEIGHT >= tb_height) return;

    for (0..HEIGHT) |yy| {
        for (0..WIDTH) |xx| {
            const cell = cells[yy * WIDTH + xx];
            if (cell.ch != 0) buffer[(y + yy) * tb_width + (x + xx)] = cell;
        }
    }
}

fn toBigNumber(char: u8) []const u21 {
    return switch (char) {
        '0' => &ZERO,
        '1' => &ONE,
        '2' => &TWO,
        '3' => &THREE,
        '4' => &FOUR,
        '5' => &FIVE,
        '6' => &SIX,
        '7' => &SEVEN,
        '8' => &EIGHT,
        '9' => &NINE,
        ':' => &S,
        else => &E,
    };
}
