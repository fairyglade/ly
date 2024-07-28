const std = @import("std");
const utils = @import("../utils.zig");
const TerminalBuffer = @import("../TerminalBuffer.zig");

const ArrayList = std.ArrayList;
const ErrorMessage = struct { width: u8, text: []const u8 };

const InfoLine = @This();

error_list: ArrayList(ErrorMessage),
error_bg: u16,
error_fg: u16,
text: []const u8,
width: u8,

pub fn init(allocator: std.mem.Allocator) InfoLine {
    return .{
        .error_list = ArrayList(ErrorMessage).init(allocator),
        .error_bg = 0,
        .error_fg = 258,
        .text = "",
        .width = 0,
    };
}

pub fn deinit(self: InfoLine) void {
    self.error_list.deinit();
}

pub fn setText(self: *InfoLine, text: []const u8) !void {
    self.width = if (text.len > 0) try utils.strWidth(text) else 0;
    self.text = text;
}

pub fn addError(self: *InfoLine, error_message: []const u8) !void {
    if (error_message.len > 0) {
        const entry = .{
            .width = try utils.strWidth(error_message),
            .text = error_message,
        };
        try self.error_list.append(entry);
    }
}

pub fn draw(self: InfoLine, buffer: TerminalBuffer) !void {
    var text: []const u8 = self.text;
    var bg: u16 = buffer.bg;
    var fg: u16 = buffer.fg;
    var width: u8 = self.width;

    if (self.error_list.items.len > 0) {
        const entry = self.error_list.getLast();
        text = entry.text; 
        bg = self.error_bg;
        fg = self.error_fg;
        width = entry.width;
    }

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
