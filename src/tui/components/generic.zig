const std = @import("std");

const Cell = @import("../Cell.zig");
const keyboard = @import("../keyboard.zig");
const TerminalBuffer = @import("../TerminalBuffer.zig");
const Position = @import("../Position.zig");

pub fn CyclableLabel(comptime ItemType: type, comptime ChangeItemType: type) type {
    return struct {
        const Allocator = std.mem.Allocator;
        const ItemList = std.ArrayListUnmanaged(ItemType);
        const DrawItemFn = *const fn (*Self, ItemType, usize, usize, usize) void;
        const ChangeItemFn = *const fn (ItemType, ?ChangeItemType) void;

        const Self = @This();

        allocator: Allocator,
        buffer: *TerminalBuffer,
        list: ItemList,
        current: usize,
        width: usize,
        component_pos: Position,
        children_pos: Position,
        text_in_center: bool,
        fg: u32,
        bg: u32,
        cursor: usize,
        draw_item_fn: DrawItemFn,
        change_item_fn: ?ChangeItemFn,
        change_item_arg: ?ChangeItemType,

        pub fn init(
            allocator: Allocator,
            buffer: *TerminalBuffer,
            draw_item_fn: DrawItemFn,
            change_item_fn: ?ChangeItemFn,
            change_item_arg: ?ChangeItemType,
            width: usize,
            text_in_center: bool,
            fg: u32,
            bg: u32,
        ) Self {
            return .{
                .allocator = allocator,
                .buffer = buffer,
                .list = .empty,
                .current = 0,
                .width = width,
                .component_pos = TerminalBuffer.START_POSITION,
                .children_pos = TerminalBuffer.START_POSITION,
                .text_in_center = text_in_center,
                .fg = fg,
                .bg = bg,
                .cursor = 0,
                .draw_item_fn = draw_item_fn,
                .change_item_fn = change_item_fn,
                .change_item_arg = change_item_arg,
            };
        }

        pub fn deinit(self: *Self) void {
            self.list.deinit(self.allocator);
        }

        pub fn positionX(self: *Self, original_pos: Position) void {
            self.component_pos = original_pos;
            self.cursor = self.component_pos.x + 2;
            self.children_pos = original_pos.addX(self.width);
        }

        pub fn positionY(self: *Self, original_pos: Position) void {
            self.component_pos = original_pos;
            self.cursor = self.component_pos.x + 2;
            self.children_pos = original_pos.addY(1);
        }

        pub fn positionXY(self: *Self, original_pos: Position) void {
            self.component_pos = original_pos;
            self.cursor = self.component_pos.x + 2;
            self.children_pos = Position.init(
                self.width,
                1,
            ).add(original_pos);
        }

        pub fn childrenPosition(self: Self) Position {
            return self.children_pos;
        }

        pub fn addItem(self: *Self, item: ItemType) !void {
            try self.list.append(self.allocator, item);
            self.current = self.list.items.len - 1;
        }

        pub fn handle(self: *Self, maybe_key: ?keyboard.Key, insert_mode: bool) void {
            if (maybe_key) |key| {
                if (key.left or (key.ctrl and key.h) or (!insert_mode and key.h)) {
                    self.goLeft();
                } else if (key.right or (key.ctrl and key.l) or (!insert_mode and key.l)) {
                    self.goRight();
                }
            }

            TerminalBuffer.setCursor(
                self.component_pos.x + self.cursor + 2,
                self.component_pos.y,
            );
        }

        pub fn draw(self: *Self) void {
            if (self.list.items.len == 0) return;
            if (self.width < 2) return;

            var left_arrow = Cell.init('<', self.fg, self.bg);
            var right_arrow = Cell.init('>', self.fg, self.bg);

            left_arrow.put(self.component_pos.x, self.component_pos.y);
            right_arrow.put(
                self.component_pos.x + self.width - 1,
                self.component_pos.y,
            );

            const current_item = self.list.items[self.current];
            const x = self.component_pos.x + 2;
            const y = self.component_pos.y;
            const width = self.width - 2;

            @call(
                .auto,
                self.draw_item_fn,
                .{ self, current_item, x, y, width },
            );
        }

        fn goLeft(self: *Self) void {
            self.current = if (self.current == 0) self.list.items.len - 1 else self.current - 1;

            if (self.change_item_fn) |change_item_fn| {
                @call(
                    .auto,
                    change_item_fn,
                    .{ self.list.items[self.current], self.change_item_arg },
                );
            }
        }

        fn goRight(self: *Self) void {
            self.current = if (self.current == self.list.items.len - 1) 0 else self.current + 1;

            if (self.change_item_fn) |change_item_fn| {
                @call(
                    .auto,
                    change_item_fn,
                    .{ self.list.items[self.current], self.change_item_arg },
                );
            }
        }
    };
}
