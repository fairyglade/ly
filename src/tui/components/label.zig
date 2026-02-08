const std = @import("std");
const Allocator = std.mem.Allocator;

const Cell = @import("../Cell.zig");
const Position = @import("../Position.zig");
const TerminalBuffer = @import("../TerminalBuffer.zig");
const termbox = TerminalBuffer.termbox;

pub fn Label(comptime ContextType: type) type {
    return struct {
        const Self = @This();

        text: []const u8,
        max_width: ?usize,
        fg: u32,
        bg: u32,
        update_fn: ?*const fn (*Self, ContextType) anyerror!void,
        is_text_allocated: bool,
        component_pos: Position,
        children_pos: Position,

        pub fn init(
            text: []const u8,
            max_width: ?usize,
            fg: u32,
            bg: u32,
            update_fn: ?*const fn (*Self, ContextType) anyerror!void,
        ) Self {
            return .{
                .text = text,
                .max_width = max_width,
                .fg = fg,
                .bg = bg,
                .update_fn = update_fn,
                .is_text_allocated = false,
                .component_pos = TerminalBuffer.START_POSITION,
                .children_pos = TerminalBuffer.START_POSITION,
            };
        }

        pub fn setTextAlloc(
            self: *Self,
            allocator: Allocator,
            comptime fmt: []const u8,
            args: anytype,
        ) !void {
            self.text = try std.fmt.allocPrint(allocator, fmt, args);
            self.is_text_allocated = true;
        }

        pub fn setTextBuf(
            self: *Self,
            buffer: []u8,
            comptime fmt: []const u8,
            args: anytype,
        ) !void {
            self.text = try std.fmt.bufPrint(buffer, fmt, args);
            self.is_text_allocated = false;
        }

        pub fn setText(self: *Self, text: []const u8) void {
            self.text = text;
            self.is_text_allocated = false;
        }

        pub fn deinit(self: Self, allocator: ?Allocator) void {
            if (self.is_text_allocated) {
                if (allocator) |alloc| alloc.free(self.text);
            }
        }

        pub fn positionX(self: *Self, original_pos: Position) void {
            self.component_pos = original_pos;
            self.children_pos = original_pos.addX(self.text.len);
        }

        pub fn positionY(self: *Self, original_pos: Position) void {
            self.component_pos = original_pos;
            self.children_pos = original_pos.addY(1);
        }

        pub fn positionXY(self: *Self, original_pos: Position) void {
            self.component_pos = original_pos;
            self.children_pos = Position.init(
                self.text.len,
                1,
            ).add(original_pos);
        }

        pub fn childrenPosition(self: Self) Position {
            return self.children_pos;
        }

        pub fn draw(self: Self) void {
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

        pub fn update(self: *Self, context: ContextType) !void {
            if (self.update_fn) |update_fn| {
                return @call(
                    .auto,
                    update_fn,
                    .{ self, context },
                );
            }
        }
    };
}
