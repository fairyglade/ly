const std = @import("std");
const interop = @import("../interop.zig");

const termbox = interop.termbox;

pub const Cell = struct {
    ch: u32,
    fg: u16,
    bg: u16,
};

pub fn initCell(ch: u32, fg: u16, bg: u16) Cell {
    return .{
        .ch = ch,
        .fg = fg,
        .bg = bg,
    };
}

pub fn putCell(x: usize, y: usize, cell: Cell) void {
    _ = termbox.tb_set_cell(@intCast(x), @intCast(y), cell.ch, cell.fg, cell.bg);
}

// Every codepoint is assumed to have a width of 1.
// Since ly should be running in a tty, this should be fine.
pub fn strWidth(str: []const u8) !u8 {
    const utf8view = try std.unicode.Utf8View.init(str);
    var utf8 = utf8view.iterator();
    var i: u8 = 0;
    while (utf8.nextCodepoint()) |_| i += 1;
    return i;
}
