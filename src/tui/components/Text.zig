const std = @import("std");
const Allocator = std.mem.Allocator;

const keyboard = @import("../keyboard.zig");
const TerminalBuffer = @import("../TerminalBuffer.zig");
const Position = @import("../Position.zig");
const Widget = @import("../Widget.zig");

const DynamicString = std.ArrayListUnmanaged(u8);

const Text = @This();

allocator: Allocator,
buffer: *TerminalBuffer,
text: DynamicString,
end: usize,
cursor: usize,
visible_start: usize,
width: usize,
component_pos: Position,
children_pos: Position,
masked: bool,
maybe_mask: ?u32,
fg: u32,
bg: u32,

pub fn init(
    allocator: Allocator,
    buffer: *TerminalBuffer,
    masked: bool,
    maybe_mask: ?u32,
    width: usize,
    fg: u32,
    bg: u32,
) Text {
    return .{
        .allocator = allocator,
        .buffer = buffer,
        .text = .empty,
        .end = 0,
        .cursor = 0,
        .visible_start = 0,
        .width = width,
        .component_pos = TerminalBuffer.START_POSITION,
        .children_pos = TerminalBuffer.START_POSITION,
        .masked = masked,
        .maybe_mask = maybe_mask,
        .fg = fg,
        .bg = bg,
    };
}

pub fn deinit(self: *Text) void {
    self.text.deinit(self.allocator);
}

pub fn widget(self: *Text) Widget {
    return Widget.init(
        "Text",
        self,
        deinit,
        null,
        draw,
        null,
        handle,
        null,
    );
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

pub fn handle(self: *Text, maybe_key: ?keyboard.Key, insert_mode: bool) !void {
    if (maybe_key) |key| {
        if (key.left or (!insert_mode and (key.h or key.backspace))) {
            self.goLeft();
        } else if (key.right or (!insert_mode and key.l)) {
            self.goRight();
        } else if (key.delete) {
            self.delete();
        } else if (key.backspace) {
            self.backspace();
        } else if (insert_mode) {
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

fn goLeft(self: *Text) void {
    if (self.cursor == 0) return;
    if (self.visible_start > 0) self.visible_start -= 1;

    self.cursor -= 1;
}

fn goRight(self: *Text) void {
    if (self.cursor >= self.end) return;
    if (self.cursor - self.visible_start == self.width - 1) self.visible_start += 1;

    self.cursor += 1;
}

fn delete(self: *Text) void {
    if (self.cursor >= self.end) return;

    _ = self.text.orderedRemove(self.cursor);

    self.end -= 1;
}

fn backspace(self: *Text) void {
    if (self.cursor == 0) return;

    self.goLeft();
    self.delete();
}

fn write(self: *Text, char: u8) !void {
    if (char == 0) return;

    try self.text.insert(self.allocator, self.cursor, char);

    self.end += 1;
    self.goRight();
}
