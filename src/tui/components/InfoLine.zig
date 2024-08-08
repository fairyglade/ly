const std = @import("std");
const TerminalBuffer = @import("../TerminalBuffer.zig");
const generic = @import("generic.zig");
const utils = @import("../utils.zig");

const Allocator = std.mem.Allocator;

const MessageLabel = generic.CyclableLabel(Message);

const InfoLine = @This();

const Message = struct {
    width: u8,
    text: []const u8,
    bg: u16,
    fg: u16,
};

label: MessageLabel,

pub fn init(allocator: Allocator, buffer: *TerminalBuffer) InfoLine {
    return .{
        .label = MessageLabel.init(allocator, buffer, drawItem),
    };
}

pub fn deinit(self: InfoLine) void {
    self.label.deinit();
}

pub fn addMessage(self: *InfoLine, text: []const u8, bg: u16, fg: u16) !void {
    if (text.len == 0) return;

    try self.label.addItem(.{
        .width = try utils.strWidth(text),
        .text = text,
        .bg = bg,
        .fg = fg,
    });
}

pub fn clearRendered(allocator: Allocator, buffer: TerminalBuffer) !void {
    // Draw over the area
    const y = buffer.box_y + buffer.margin_box_v;
    const spaces = try allocator.alloc(u8, buffer.box_width);
    defer allocator.free(spaces);

    @memset(spaces, ' ');

    buffer.drawLabel(spaces, buffer.box_x, y);
}

fn drawItem(label: *MessageLabel, message: Message, _: usize, _: usize) bool {
    if (message.width == 0 or label.buffer.box_width <= message.width) return false;

    const x = label.buffer.box_x + ((label.buffer.box_width - message.width) / 2);
    label.first_char_x = x + message.width;

    TerminalBuffer.drawColorLabel(message.text, x, label.y, message.fg, message.bg);
    return true;
}
