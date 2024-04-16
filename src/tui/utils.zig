const std = @import("std");
const interop = @import("../interop.zig");

const termbox = interop.termbox;

pub fn initCell(ch: u32, fg: u32, bg: u32) termbox.tb_cell {
    return .{
        .ch = ch,
        .fg = fg,
        .bg = bg,
    };
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
