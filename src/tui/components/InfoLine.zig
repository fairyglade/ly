const std = @import("std");
const Allocator = std.mem.Allocator;

const keyboard = @import("../keyboard.zig");
const TerminalBuffer = @import("../TerminalBuffer.zig");
const Widget = @import("../Widget.zig");
const generic = @import("generic.zig");

const MessageLabel = generic.CyclableLabel(Message, Message);

const InfoLine = @This();

const Message = struct {
    width: usize,
    text: []const u8,
    bg: u32,
    fg: u32,
};

label: MessageLabel,

pub fn init(
    allocator: Allocator,
    buffer: *TerminalBuffer,
    width: usize,
    arrow_fg: u32,
    arrow_bg: u32,
) InfoLine {
    return .{
        .label = MessageLabel.init(
            allocator,
            buffer,
            drawItem,
            null,
            null,
            width,
            true,
            arrow_fg,
            arrow_bg,
        ),
    };
}

pub fn deinit(self: *InfoLine) void {
    self.label.deinit();
}

pub fn widget(self: *InfoLine) Widget {
    return Widget.init(
        "InfoLine",
        self,
        deinit,
        null,
        draw,
        null,
        handle,
    );
}

pub fn addMessage(self: *InfoLine, text: []const u8, bg: u32, fg: u32) !void {
    if (text.len == 0) return;

    try self.label.addItem(.{
        .width = TerminalBuffer.strWidth(text),
        .text = text,
        .bg = bg,
        .fg = fg,
    });
}

pub fn clearRendered(self: InfoLine, allocator: Allocator) !void {
    // Draw over the area
    const spaces = try allocator.alloc(u8, self.label.width - 2);
    defer allocator.free(spaces);

    @memset(spaces, ' ');

    TerminalBuffer.drawText(
        spaces,
        self.label.component_pos.x + 2,
        self.label.component_pos.y,
        TerminalBuffer.Color.DEFAULT,
        TerminalBuffer.Color.DEFAULT,
    );
}

fn draw(self: *InfoLine) void {
    self.label.draw();
}

fn handle(self: *InfoLine, maybe_key: ?keyboard.Key, insert_mode: bool) !void {
    self.label.handle(maybe_key, insert_mode);
}

fn drawItem(label: *MessageLabel, message: Message, x: usize, y: usize, width: usize) void {
    if (message.width == 0) return;

    const x_offset = if (label.text_in_center and width >= message.width) (width - message.width) / 2 else 0;

    label.cursor = message.width + x_offset;
    TerminalBuffer.drawConfinedText(
        message.text,
        x + x_offset,
        y,
        width,
        message.fg,
        message.bg,
    );
}
