const std = @import("std");
const utils = @import("../utils.zig");
const TerminalBuffer = @import("../TerminalBuffer.zig");

const InfoLine = @This();

text: []const u8 = "",
width: u8 = 0,

pub fn setText(self: *InfoLine, text: []const u8) !void {
    self.width = if (text.len > 0) try utils.strWidth(text) else 0;
    self.text = text;
}

pub fn draw(self: InfoLine, buffer: TerminalBuffer) void {
    if (self.width > 0 and buffer.box_width > self.width) {
        const label_y = buffer.box_y + buffer.margin_box_v;
        const x = buffer.box_x + ((buffer.box_width - self.width) / 2);

        buffer.drawLabel(self.text, x, label_y);
    }
}

pub fn clearRendered(allocator: std.mem.Allocator, buffer: TerminalBuffer) !void {
    // draw over the area
    const y = buffer.box_y + buffer.margin_box_v;
    const spaces = try allocator.alloc(u8, buffer.box_width);
    defer allocator.free(spaces);

    @memset(spaces, ' ');

    buffer.drawLabel(spaces, buffer.box_x, y);
}
