const std = @import("std");
const Allocator = std.mem.Allocator;
const Animation = @import("../tui/Animation.zig");
const Cell = @import("../tui/Cell.zig");
const TerminalBuffer = @import("../tui/TerminalBuffer.zig");

const Doom = @This();

pub const STEPS = 12;

allocator: Allocator,
terminal_buffer: *TerminalBuffer,
buffer: []u8,
fire: [STEPS + 1]Cell,

pub fn init(allocator: Allocator, terminal_buffer: *TerminalBuffer, top_color: u32, middle_color: u32, bottom_color: u32) !Doom {
    const buffer = try allocator.alloc(u8, terminal_buffer.width * terminal_buffer.height);
    initBuffer(buffer, terminal_buffer.width);

    return .{
        .allocator = allocator,
        .terminal_buffer = terminal_buffer,
        .buffer = buffer,
        .fire = [_]Cell{
            Cell.init(' ', TerminalBuffer.Color.DEFAULT, TerminalBuffer.Color.DEFAULT),
            Cell.init(0x2591, top_color, TerminalBuffer.Color.DEFAULT),
            Cell.init(0x2592, top_color, TerminalBuffer.Color.DEFAULT),
            Cell.init(0x2593, top_color, TerminalBuffer.Color.DEFAULT),
            Cell.init(0x2588, top_color, TerminalBuffer.Color.DEFAULT),
            Cell.init(0x2591, middle_color, top_color),
            Cell.init(0x2592, middle_color, top_color),
            Cell.init(0x2593, middle_color, top_color),
            Cell.init(0x2588, middle_color, top_color),
            Cell.init(0x2591, bottom_color, middle_color),
            Cell.init(0x2592, bottom_color, middle_color),
            Cell.init(0x2593, bottom_color, middle_color),
            Cell.init(0x2588, bottom_color, middle_color),
        },
    };
}

pub fn animation(self: *Doom) Animation {
    return Animation.init(self, deinit, realloc, draw);
}

fn deinit(self: *Doom) void {
    self.allocator.free(self.buffer);
}

fn realloc(self: *Doom) anyerror!void {
    const buffer = try self.allocator.realloc(self.buffer, self.terminal_buffer.width * self.terminal_buffer.height);
    initBuffer(buffer, self.terminal_buffer.width);
    self.buffer = buffer;
}

fn draw(self: *Doom) void {
    for (0..self.terminal_buffer.width) |x| {
        // We start from 1 so that we always have the topmost line when spreading fire
        for (1..self.terminal_buffer.height) |y| {
            // Get current cell
            const from = y * self.terminal_buffer.width + x;
            const cell_index = self.buffer[from];

            // Spread fire
            const propagate = self.terminal_buffer.random.int(u1);
            const to = from - self.terminal_buffer.width; // Get the line above

            self.buffer[to] = if (cell_index > 0) cell_index - propagate else cell_index;

            // Put the cell
            const cell = self.fire[cell_index];
            cell.put(x, y);
        }
    }
}

fn initBuffer(buffer: []u8, width: usize) void {
    const length = buffer.len - width;
    const slice_start = buffer[0..length];
    const slice_end = buffer[length..];

    // Initialize the framebuffer in black, except for the "fire source" as the
    // last color
    @memset(slice_start, 0);
    @memset(slice_end, STEPS);
}
