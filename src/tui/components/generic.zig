const std = @import("std");
const enums = @import("../../enums.zig");
const interop = @import("../../interop.zig");
const TerminalBuffer = @import("../TerminalBuffer.zig");

pub fn CyclableLabel(comptime ItemType: type) type {
    return struct {
        const Allocator = std.mem.Allocator;
        const ItemList = std.ArrayList(ItemType);
        const DrawItemFn = *const fn (*Self, ItemType, usize, usize) bool;

        const termbox = interop.termbox;

        const Self = @This();

        allocator: Allocator,
        buffer: *TerminalBuffer,
        list: ItemList,
        current: usize,
        visible_length: usize,
        x: usize,
        y: usize,
        first_char_x: usize,
        text_in_center: bool,
        draw_item_fn: DrawItemFn,

        pub fn init(allocator: Allocator, buffer: *TerminalBuffer, draw_item_fn: DrawItemFn) Self {
            return .{
                .allocator = allocator,
                .buffer = buffer,
                .list = ItemList.init(allocator),
                .current = 0,
                .visible_length = 0,
                .x = 0,
                .y = 0,
                .first_char_x = 0,
                .text_in_center = false,
                .draw_item_fn = draw_item_fn,
            };
        }

        pub fn deinit(self: Self) void {
            self.list.deinit();
        }

        pub fn position(self: *Self, x: usize, y: usize, visible_length: usize, text_in_center: ?bool) void {
            self.x = x;
            self.y = y;
            self.visible_length = visible_length;
            self.first_char_x = x + 2;
            if (text_in_center) |value| {
                self.text_in_center = value;
            }
        }

        pub fn addItem(self: *Self, item: ItemType) !void {
            try self.list.append(item);
            self.current = self.list.items.len - 1;
        }

        pub fn handle(self: *Self, maybe_event: ?*termbox.tb_event, insert_mode: bool) void {
            if (maybe_event) |event| blk: {
                if (event.type != termbox.TB_EVENT_KEY) break :blk;

                switch (event.key) {
                    termbox.TB_KEY_ARROW_LEFT, termbox.TB_KEY_CTRL_H => self.goLeft(),
                    termbox.TB_KEY_ARROW_RIGHT, termbox.TB_KEY_CTRL_L => self.goRight(),
                    else => {
                        if (!insert_mode) {
                            switch (event.ch) {
                                'h' => self.goLeft(),
                                'l' => self.goRight(),
                                else => {},
                            }
                        }
                    },
                }
            }

            _ = termbox.tb_set_cursor(@intCast(self.first_char_x), @intCast(self.y));
        }

        pub fn draw(self: *Self) void {
            if (self.list.items.len == 0) return;

            const current_item = self.list.items[self.current];
            const x = self.buffer.box_x + self.buffer.margin_box_h;
            const y = self.buffer.box_y + self.buffer.margin_box_v + 2;

            const continue_drawing = @call(.auto, self.draw_item_fn, .{ self, current_item, x, y });
            if (!continue_drawing) return;

            _ = termbox.tb_set_cell(@intCast(self.x), @intCast(self.y), '<', self.buffer.fg, self.buffer.bg);
            _ = termbox.tb_set_cell(@intCast(self.x + self.visible_length - 1), @intCast(self.y), '>', self.buffer.fg, self.buffer.bg);
        }

        fn goLeft(self: *Self) void {
            if (self.current == 0) {
                self.current = self.list.items.len - 1;
                return;
            }

            self.current -= 1;
        }

        fn goRight(self: *Self) void {
            if (self.current == self.list.items.len - 1) {
                self.current = 0;
                return;
            }

            self.current += 1;
        }
    };
}
