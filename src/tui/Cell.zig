const interop = @import("../interop.zig");

const termbox = interop.termbox;

const Cell = @This();

ch: u32,
fg: u32,
bg: u32,

pub fn init(ch: u32, fg: u32, bg: u32) Cell {
    return .{
        .ch = ch,
        .fg = fg,
        .bg = bg,
    };
}

pub fn put(self: Cell, x: usize, y: usize) void {
    if (self.ch == 0) return;

    _ = termbox.tb_set_cell(@intCast(x), @intCast(y), self.ch, self.fg, self.bg);
}
