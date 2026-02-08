const std = @import("std");
const Allocator = std.mem.Allocator;

const ly_core = @import("ly-core");
const interop = ly_core.interop;

const en = @import("bigLabelLocales/en.zig");
const fa = @import("bigLabelLocales/fa.zig");
const Cell = @import("../Cell.zig");
const Position = @import("../Position.zig");
const TerminalBuffer = @import("../TerminalBuffer.zig");
const termbox = TerminalBuffer.termbox;

pub const CHAR_WIDTH = 5;
pub const CHAR_HEIGHT = 5;
pub const CHAR_SIZE = CHAR_WIDTH * CHAR_HEIGHT;
pub const X: u32 = if (ly_core.interop.supportsUnicode()) 0x2593 else '#';
pub const O: u32 = 0;

// zig fmt: off
pub const LocaleChars = struct {
    ZERO:   [CHAR_SIZE]u21,
    ONE:    [CHAR_SIZE]u21,
    TWO:    [CHAR_SIZE]u21,
    THREE:  [CHAR_SIZE]u21,
    FOUR:   [CHAR_SIZE]u21,
    FIVE:   [CHAR_SIZE]u21,
    SIX:    [CHAR_SIZE]u21,
    SEVEN:  [CHAR_SIZE]u21,
    EIGHT:  [CHAR_SIZE]u21,
    NINE:   [CHAR_SIZE]u21,
    S:      [CHAR_SIZE]u21,
    E:      [CHAR_SIZE]u21,
    P:      [CHAR_SIZE]u21,
    A:      [CHAR_SIZE]u21,
    M:      [CHAR_SIZE]u21,
};
// zig fmt: on

pub const BigLabelLocale = enum {
    en,
    fa,
};

pub fn BigLabel(comptime ContextType: type) type {
    return struct {
        const Self = @This();

        buffer: *TerminalBuffer,
        text: []const u8,
        max_width: ?usize,
        fg: u32,
        bg: u32,
        locale: BigLabelLocale,
        update_fn: ?*const fn (*Self, ContextType) anyerror!void,
        is_text_allocated: bool,
        component_pos: Position,
        children_pos: Position,

        pub fn init(
            buffer: *TerminalBuffer,
            text: []const u8,
            max_width: ?usize,
            fg: u32,
            bg: u32,
            locale: BigLabelLocale,
            update_fn: ?*const fn (*Self, ContextType) anyerror!void,
        ) Self {
            return .{
                .buffer = buffer,
                .text = text,
                .max_width = max_width,
                .fg = fg,
                .bg = bg,
                .locale = locale,
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
            self.children_pos = original_pos.addX(self.text.len * CHAR_WIDTH);
        }

        pub fn positionY(self: *Self, original_pos: Position) void {
            self.component_pos = original_pos;
            self.children_pos = original_pos.addY(CHAR_HEIGHT);
        }

        pub fn positionXY(self: *Self, original_pos: Position) void {
            self.component_pos = original_pos;
            self.children_pos = Position.init(
                self.text.len * CHAR_WIDTH,
                CHAR_HEIGHT,
            ).add(original_pos);
        }

        pub fn childrenPosition(self: Self) Position {
            return self.children_pos;
        }

        pub fn draw(self: Self) void {
            for (self.text, 0..) |c, i| {
                const clock_cell = clockCell(
                    c,
                    self.fg,
                    self.bg,
                    self.locale,
                );

                alphaBlit(
                    self.component_pos.x + i * (CHAR_WIDTH + 1),
                    self.component_pos.y,
                    self.buffer.width,
                    self.buffer.height,
                    clock_cell,
                );
            }
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

        fn clockCell(char: u8, fg: u32, bg: u32, locale: BigLabelLocale) [CHAR_SIZE]Cell {
            var cells: [CHAR_SIZE]Cell = undefined;

            //@divTrunc(time.microseconds, 500000) != 0)
            const clock_chars = toBigNumber(char, locale);
            for (0..cells.len) |i| cells[i] = Cell.init(clock_chars[i], fg, bg);

            return cells;
        }

        fn alphaBlit(x: usize, y: usize, tb_width: usize, tb_height: usize, cells: [CHAR_SIZE]Cell) void {
            if (x + CHAR_WIDTH >= tb_width or y + CHAR_HEIGHT >= tb_height) return;

            for (0..CHAR_HEIGHT) |yy| {
                for (0..CHAR_WIDTH) |xx| {
                    const cell = cells[yy * CHAR_WIDTH + xx];
                    cell.put(x + xx, y + yy);
                }
            }
        }

        fn toBigNumber(char: u8, locale: BigLabelLocale) [CHAR_SIZE]u21 {
            const locale_chars = switch (locale) {
                .fa => fa.locale_chars,
                .en => en.locale_chars,
            };
            return switch (char) {
                '0' => locale_chars.ZERO,
                '1' => locale_chars.ONE,
                '2' => locale_chars.TWO,
                '3' => locale_chars.THREE,
                '4' => locale_chars.FOUR,
                '5' => locale_chars.FIVE,
                '6' => locale_chars.SIX,
                '7' => locale_chars.SEVEN,
                '8' => locale_chars.EIGHT,
                '9' => locale_chars.NINE,
                'p', 'P' => locale_chars.P,
                'a', 'A' => locale_chars.A,
                'm', 'M' => locale_chars.M,
                ':' => locale_chars.S,
                else => locale_chars.E,
            };
        }
    };
}
