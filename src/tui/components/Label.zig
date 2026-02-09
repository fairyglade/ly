const Label = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const Cell = @import("../Cell.zig");
const Position = @import("../Position.zig");
const TerminalBuffer = @import("../TerminalBuffer.zig");
const Widget = @import("../Widget.zig");

allocator: ?Allocator,
text: []const u8,
max_width: ?usize,
fg: u32,
bg: u32,
update_fn: ?*const fn (*Label, *anyopaque) anyerror!void,
component_pos: Position,
children_pos: Position,

pub fn init(
    text: []const u8,
    max_width: ?usize,
    fg: u32,
    bg: u32,
    update_fn: ?*const fn (*Label, *anyopaque) anyerror!void,
) Label {
    return .{
        .allocator = null,
        .text = text,
        .max_width = max_width,
        .fg = fg,
        .bg = bg,
        .update_fn = update_fn,
        .component_pos = TerminalBuffer.START_POSITION,
        .children_pos = TerminalBuffer.START_POSITION,
    };
}

pub fn deinit(self: *Label) void {
    if (self.allocator) |allocator| allocator.free(self.text);
}

pub fn widget(self: *Label) Widget {
    return Widget.init(
        self,
        deinit,
        null,
        draw,
        update,
        null,
    );
}

pub fn setTextAlloc(
    self: *Label,
    allocator: Allocator,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    self.text = try std.fmt.allocPrint(allocator, fmt, args);
    self.allocator = allocator;
}

pub fn setTextBuf(
    self: *Label,
    buffer: []u8,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    self.text = try std.fmt.bufPrint(buffer, fmt, args);
    self.allocator = null;
}

pub fn setText(self: *Label, text: []const u8) void {
    self.text = text;
    self.allocator = null;
}

pub fn positionX(self: *Label, original_pos: Position) void {
    self.component_pos = original_pos;
    self.children_pos = original_pos.addX(TerminalBuffer.strWidth(self.text));
}

pub fn positionY(self: *Label, original_pos: Position) void {
    self.component_pos = original_pos;
    self.children_pos = original_pos.addY(1);
}

pub fn positionXY(self: *Label, original_pos: Position) void {
    self.component_pos = original_pos;
    self.children_pos = Position.init(
        TerminalBuffer.strWidth(self.text),
        1,
    ).add(original_pos);
}

pub fn childrenPosition(self: Label) Position {
    return self.children_pos;
}

pub fn draw(self: *Label) void {
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

pub fn update(self: *Label, ctx: *anyopaque) !void {
    if (self.update_fn) |update_fn| {
        return @call(
            .auto,
            update_fn,
            .{ self, ctx },
        );
    }
}
