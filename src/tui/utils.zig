const std = @import("std");
const interop = @import("../interop.zig");

const termbox = interop.termbox;

pub inline fn initCell(ch: u32, fg: u32, bg: u32) termbox.tb_cell {
    return .{
        .ch = ch,
        .fg = fg,
        .bg = bg,
    };
}
