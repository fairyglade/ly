const std = @import("std");
const Allocator = std.mem.Allocator;

const Cell = @import("../Cell.zig");
const Position = @import("../Position.zig");
const TerminalBuffer = @import("../TerminalBuffer.zig");
const termbox = TerminalBuffer.termbox;

const Label = @This();

text: []const u8,
max_width: ?usize,
fg: u32,
bg: u32,
is_text_allocated: bool,
component_pos: Position,
children_pos: Position,

pub fn init(
    text: []const u8,
    max_width: ?usize,
    fg: u32,
    bg: u32,
) Label {
    return .{
        .text = text,
        .max_width = max_width,
        .fg = fg,
        .bg = bg,
        .is_text_allocated = false,
        .component_pos = TerminalBuffer.START_POSITION,
        .children_pos = TerminalBuffer.START_POSITION,
    };
}

pub fn setTextAlloc(
    self: *Label,
    allocator: Allocator,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    self.text = try std.fmt.allocPrint(allocator, fmt, args);
    self.is_text_allocated = true;
}

pub fn setTextBuf(
    self: *Label,
    buffer: []u8,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    self.text = try std.fmt.bufPrint(buffer, fmt, args);
    self.is_text_allocated = false;
}

pub fn setText(self: *Label, text: []const u8) void {
    self.text = text;
    self.is_text_allocated = false;
}

pub fn deinit(self: Label, allocator: ?Allocator) void {
    if (self.is_text_allocated) {
        if (allocator) |alloc| alloc.free(self.text);
    }
}

pub fn positionX(self: *Label, original_pos: Position) void {
    self.component_pos = original_pos;
    self.children_pos = original_pos.addX(self.text.len);
}

pub fn positionY(self: *Label, original_pos: Position) void {
    self.component_pos = original_pos;
    self.children_pos = original_pos.addY(1);
}

pub fn positionXY(self: *Label, original_pos: Position) void {
    self.component_pos = original_pos;
    self.children_pos = Position.init(
        self.text.len,
        1,
    ).add(original_pos);
}

pub fn childrenPosition(self: Label) Position {
    return self.children_pos;
}

pub fn draw(self: Label) void {
    if (self.max_width) |width| {
        TerminalBuffer.drawConfinedText(
            self.text,
            self.component_pos.x,
            self.component_pos.y,
            width,
            self.fg,
            self.bg,
        );
        return;
    }

    TerminalBuffer.drawText(
        self.text,
        self.component_pos.x,
        self.component_pos.y,
        self.fg,
        self.bg,
    );
}
