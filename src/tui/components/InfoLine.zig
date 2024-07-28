const std = @import("std");
const utils = @import("../utils.zig");
const TerminalBuffer = @import("../TerminalBuffer.zig");

const InfoLine = @This();

const Message = struct {
    width: u8,
    text: []const u8,
    bg: u16,
    fg: u16,
};
const MessageList = std.ArrayList(Message);

messages: MessageList,

pub fn init(allocator: std.mem.Allocator) InfoLine {
    return .{
        .messages = MessageList.init(allocator),
    };
}

pub fn deinit(self: InfoLine) void {
    self.messages.deinit();
}

pub fn addMessage(self: *InfoLine, text: []const u8, bg: u16, fg: u16) !void {
    if (text.len == 0) return;

    try self.messages.append(.{
        .width = try utils.strWidth(text),
        .text = text,
        .bg = bg,
        .fg = fg,
    });
}

pub fn draw(self: InfoLine, buffer: TerminalBuffer) !void {
    if (self.messages.items.len == 0) return;

    const entry = self.messages.getLast();
    if (entry.width == 0 or buffer.box_width <= entry.width) return;

    const label_y = buffer.box_y + buffer.margin_box_v;
    const x = buffer.box_x + ((buffer.box_width - entry.width) / 2);
    TerminalBuffer.drawColorLabel(entry.text, x, label_y, entry.fg, entry.bg);
}

pub fn clearRendered(allocator: std.mem.Allocator, buffer: TerminalBuffer) !void {
    // Draw over the area
    const y = buffer.box_y + buffer.margin_box_v;
    const spaces = try allocator.alloc(u8, buffer.box_width);
    defer allocator.free(spaces);

    @memset(spaces, ' ');

    buffer.drawLabel(spaces, buffer.box_x, y);
}
