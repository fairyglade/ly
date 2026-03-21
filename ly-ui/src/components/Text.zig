const std = @import("std");
const Allocator = std.mem.Allocator;

const keyboard = @import("../keyboard.zig");
const TerminalBuffer = @import("../TerminalBuffer.zig");
const Position = @import("../Position.zig");
const Widget = @import("../Widget.zig");

const DynamicString = std.ArrayListUnmanaged(u8);

const Text = @This();

instance: ?Widget,
allocator: Allocator,
buffer: *TerminalBuffer,
text: DynamicString,
end: usize,
cursor: usize,
visible_start: usize,
width: usize,
component_pos: Position,
children_pos: Position,
should_insert: bool,
masked: bool,
maybe_mask: ?u32,
fg: u32,
bg: u32,
keybinds: TerminalBuffer.KeybindMap,

pub fn init(
    allocator: Allocator,
    buffer: *TerminalBuffer,
    should_insert: bool,
    masked: bool,
    maybe_mask: ?u32,
    width: usize,
    fg: u32,
    bg: u32,
) !*Text {
    var self = try allocator.create(Text);
    self.* = Text{
        .instance = null,
        .allocator = allocator,
        .buffer = buffer,
        .text = .empty,
        .end = 0,
        .cursor = 0,
        .visible_start = 0,
        .width = width,
        .component_pos = TerminalBuffer.START_POSITION,
        .children_pos = TerminalBuffer.START_POSITION,
        .should_insert = should_insert,
        .masked = masked,
        .maybe_mask = maybe_mask,
        .fg = fg,
        .bg = bg,
        .keybinds = .init(allocator),
    };

    try buffer.registerKeybind(&self.keybinds, "Left", &goLeft, self);
    try buffer.registerKeybind(&self.keybinds, "Right", &goRight, self);
    try buffer.registerKeybind(&self.keybinds, "Delete", &delete, self);
    try buffer.registerKeybind(&self.keybinds, "Backspace", &backspace, self);
    try buffer.registerKeybind(&self.keybinds, "Ctrl+U", &clearTextEntry, self);

    return self;
}

pub fn deinit(self: *Text) void {
    self.text.deinit(self.allocator);
    self.keybinds.deinit();
    self.allocator.destroy(self);
}

pub fn widget(self: *Text) *Widget {
    if (self.instance) |*instance| return instance;
    self.instance = Widget.init(
        "Text",
        self.keybinds,
        self,
        deinit,
        null,
        draw,
        null,
        handle,
        null,
    );
    return &self.instance.?;
}

pub fn positionX(self: *Text, original_pos: Position) void {
    self.component_pos = original_pos;
    self.children_pos = original_pos.addX(self.width);
}

pub fn positionY(self: *Text, original_pos: Position) void {
    self.component_pos = original_pos;
    self.children_pos = original_pos.addY(1);
}

pub fn positionXY(self: *Text, original_pos: Position) void {
    self.component_pos = original_pos;
    self.children_pos = Position.init(
        self.width,
        1,
    ).add(original_pos);
}

pub fn childrenPosition(self: Text) Position {
    return self.children_pos;
}

pub fn clear(self: *Text) void {
    self.text.clearRetainingCapacity();
    self.end = 0;
    self.cursor = 0;
    self.visible_start = 0;
}

pub fn toggleMask(self: *Text) void {
    self.masked = !self.masked;
}

pub fn handle(self: *Text, maybe_key: ?keyboard.Key) !void {
    if (maybe_key) |key| {
        if (self.should_insert) {
            const maybe_character = key.getEnabledPrintableAscii();
            if (maybe_character) |character| try self.write(character);
        }
    }

    if (self.masked and self.maybe_mask == null) {
        TerminalBuffer.setCursor(
            self.component_pos.x,
            self.component_pos.y,
        );
        return;
    }

    TerminalBuffer.setCursor(
        self.component_pos.x + (self.cursor - self.visible_start),
        self.component_pos.y,
    );
}

fn draw(self: *Text) void {
    if (self.masked) {
        if (self.maybe_mask) |mask| {
            if (self.width < 1) return;

            const length = @min(TerminalBuffer.strWidth(self.text.items), self.width - 1);
            if (length == 0) return;

            TerminalBuffer.drawCharMultiple(
                mask,
                self.component_pos.x,
                self.component_pos.y,
                length,
                self.fg,
                self.bg,
            );
        }
        return;
    }

    const str_length = TerminalBuffer.strWidth(self.text.items);
    const length = @min(str_length, self.width);
    if (length == 0) return;

    const visible_slice = vs: {
        if (str_length > self.width and self.cursor < str_length) {
            break :vs self.text.items[self.visible_start..(self.width + self.visible_start)];
        } else {
            break :vs self.text.items[self.visible_start..];
        }
    };

    TerminalBuffer.drawText(
        visible_slice,
        self.component_pos.x,
        self.component_pos.y,
        self.fg,
        self.bg,
    );
}

fn goLeft(ptr: *anyopaque) !bool {
    var self: *Text = @ptrCast(@alignCast(ptr));

    if (self.cursor == 0) return false;
    if (self.visible_start > 0) self.visible_start -= 1;

    self.cursor -= 1;
    return false;
}

fn goRight(ptr: *anyopaque) !bool {
    var self: *Text = @ptrCast(@alignCast(ptr));

    if (self.cursor >= self.end) return false;
    if (self.cursor - self.visible_start == self.width - 1) self.visible_start += 1;

    self.cursor += 1;
    return false;
}

fn delete(ptr: *anyopaque) !bool {
    var self: *Text = @ptrCast(@alignCast(ptr));

    if (self.cursor >= self.end or !self.should_insert) return false;

    _ = self.text.orderedRemove(self.cursor);

    self.end -= 1;
    return false;
}

fn backspace(ptr: *anyopaque) !bool {
    const self: *Text = @ptrCast(@alignCast(ptr));

    if (self.cursor == 0 or !self.should_insert) return false;

    _ = try goLeft(ptr);
    _ = try delete(ptr);
    return false;
}

fn write(self: *Text, char: u8) !void {
    if (char == 0) return;

    try self.text.insert(self.allocator, self.cursor, char);

    self.end += 1;
    _ = try goRight(self);
}

fn clearTextEntry(ptr: *anyopaque) !bool {
    var self: *Text = @ptrCast(@alignCast(ptr));

    if (!self.should_insert) return false;

    self.clear();
    self.buffer.drawNextFrame(true);
    return false;
}
