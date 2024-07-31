const std = @import("std");
const interop = @import("../../interop.zig");
const TerminalBuffer = @import("../TerminalBuffer.zig");
const utils = @import("../utils.zig");

const Allocator = std.mem.Allocator;
const DynamicString = std.ArrayList(u8);

const termbox = interop.termbox;

const Text = @This();

allocator: Allocator,
buffer: *TerminalBuffer,
text: DynamicString,
end: usize,
cursor: usize,
visible_start: usize,
visible_length: usize,
x: usize,
y: usize,
masked: bool,
maybe_mask: ?u8,

pub fn init(allocator: Allocator, buffer: *TerminalBuffer, masked: bool, maybe_mask: ?u8) Text {
    const text = DynamicString.init(allocator);

    return .{
        .allocator = allocator,
        .buffer = buffer,
        .text = text,
        .end = 0,
        .cursor = 0,
        .visible_start = 0,
        .visible_length = 0,
        .x = 0,
        .y = 0,
        .masked = masked,
        .maybe_mask = maybe_mask,
    };
}

pub fn deinit(self: Text) void {
    self.text.deinit();
}

pub fn position(self: *Text, x: usize, y: usize, visible_length: usize) void {
    self.x = x;
    self.y = y;
    self.visible_length = visible_length;
}

pub fn handle(self: *Text, maybe_event: ?*termbox.tb_event, insert_mode: bool) !void {
    if (maybe_event) |event| blk: {
        if (event.type != termbox.TB_EVENT_KEY) break :blk;

        switch (event.key) {
            termbox.TB_KEY_ARROW_LEFT => self.goLeft(),
            termbox.TB_KEY_ARROW_RIGHT => self.goRight(),
            termbox.TB_KEY_DELETE => self.delete(),
            termbox.TB_KEY_BACKSPACE, termbox.TB_KEY_BACKSPACE2 => {
                if (insert_mode) {
                    self.backspace();
                } else {
                    self.goLeft();
                }
            },
            termbox.TB_KEY_SPACE => try self.write(' '),
            else => {
                if (event.ch > 31 and event.ch < 127) {
                    if (insert_mode) {
                        try self.write(@intCast(event.ch));
                    } else {
                        switch (event.ch) {
                            'h' => self.goLeft(),
                            'l' => self.goRight(),
                            else => {},
                        }
                    }
                }
            },
        }
    }

    if (self.masked and self.maybe_mask == null) {
        _ = termbox.tb_set_cursor(@intCast(self.x), @intCast(self.y));
        return;
    }

    _ = termbox.tb_set_cursor(@intCast(self.x + (self.cursor - self.visible_start)), @intCast(self.y));
}

pub fn draw(self: Text) void {
    if (self.masked) {
        if (self.maybe_mask) |mask| {
            const length = @min(self.text.items.len, self.visible_length - 1);
            if (length == 0) return;

            self.buffer.drawCharMultiple(mask, self.x, self.y, length);
        }
        return;
    }

    const length = @min(self.text.items.len, self.visible_length);
    if (length == 0) return;

    const visible_slice = vs: {
        if (self.text.items.len > self.visible_length and self.cursor < self.text.items.len) {
            break :vs self.text.items[self.visible_start..(self.visible_length + self.visible_start)];
        } else {
            break :vs self.text.items[self.visible_start..];
        }
    };

    self.buffer.drawLabel(visible_slice, self.x, self.y);
}

pub fn clear(self: *Text) void {
    self.text.clearRetainingCapacity();
    self.end = 0;
    self.cursor = 0;
    self.visible_start = 0;
}

fn goLeft(self: *Text) void {
    if (self.cursor == 0) return;
    if (self.visible_start > 0) self.visible_start -= 1;

    self.cursor -= 1;
}

fn goRight(self: *Text) void {
    if (self.cursor >= self.end) return;
    if (self.cursor - self.visible_start == self.visible_length - 1) self.visible_start += 1;

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

    try self.text.insert(self.cursor, char);

    self.end += 1;
    self.goRight();
}
