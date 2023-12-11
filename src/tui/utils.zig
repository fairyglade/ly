const std = @import("std");
const interop = @import("../interop.zig");

const termbox = interop.termbox;

pub fn initCell(ch: u32, fg: u32, bg: u32) termbox.tb_cell {
    var cell = std.mem.zeroes(termbox.tb_cell);
    cell.ch = ch;
    cell.fg = fg;
    cell.bg = bg;
    return cell;
}
