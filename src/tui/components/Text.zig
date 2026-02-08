const std = @import("std");
const Allocator = std.mem.Allocator;

const TerminalBuffer = @import("../TerminalBuffer.zig");
const Position = @import("../Position.zig");
const termbox = TerminalBuffer.termbox;

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
        _ = termbox.tb_set_cursor(@intCast(self.component_pos.x), @intCast(self.component_pos.y));
        return;
    }

    _ = termbox.tb_set_cursor(
        @intCast(self.component_pos.x + (self.cursor - self.visible_start)),
        @intCast(self.component_pos.y),
    );
}

pub fn draw(self: Text) void {
    if (self.masked) {
        if (self.maybe_mask) |mask| {
            if (self.width < 1) return;

            const length = @min(self.text.items.len, self.width - 1);
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

    const length = @min(self.text.items.len, self.width);
    if (length == 0) return;

    const visible_slice = vs: {
        if (self.text.items.len > self.width and self.cursor < self.text.items.len) {
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
