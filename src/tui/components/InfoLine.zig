const std = @import("std");
const utils = @import("../utils.zig");
const TerminalBuffer = @import("../TerminalBuffer.zig");

const ArrayList = std.ArrayList;

const InfoLine = @This();

error_list: ArrayList([]const u8),
error_bg: u16,
error_fg: u16,
text: []const u8,

pub fn init(allocator: std.mem.Allocator) InfoLine {
    return .{
        .error_list = ArrayList([]const u8).init(allocator),
        .error_bg = 0,
        .error_fg = 258,
        .text = "",
    };
}

pub fn deinit(self: InfoLine) void {
    self.error_list.deinit();
}

pub fn setText(self: *InfoLine, text: []const u8) void {
    self.text = text;
}

pub fn addError(self: *InfoLine, error_message: []const u8) !void {
    try self.error_list.append(error_message);
}

pub fn draw(self: InfoLine, buffer: TerminalBuffer) !void {
    var text: []const u8 = self.text;
    var bg: u16 = buffer.bg;
    var fg: u16 = buffer.fg;

    if (self.error_list.items.len > 0) {
        text = self.error_list.getLast();
        bg = self.error_bg;
        fg = self.error_fg;
    }

    const width: u8 = if (text.len > 0) try utils.strWidth(text) else 0;

    if (width > 0 and buffer.box_width > width) {
        const label_y = buffer.box_y + buffer.margin_box_v;
        const x = buffer.box_x + ((buffer.box_width - width) / 2);
        TerminalBuffer.drawColorLabel(text, x, label_y, fg, bg);
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
