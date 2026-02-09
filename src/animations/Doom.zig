const std = @import("std");
const Allocator = std.mem.Allocator;

const Cell = @import("../tui/Cell.zig");
const TerminalBuffer = @import("../tui/TerminalBuffer.zig");
const Widget = @import("../tui/Widget.zig");

const Doom = @This();

pub const STEPS = 12;
pub const HEIGHT_MAX = 9;
pub const SPREAD_MAX = 4;

allocator: Allocator,
terminal_buffer: *TerminalBuffer,
buffer: []u8,
height: u8,
spread: u8,
fire: [STEPS + 1]Cell,

pub fn init(allocator: Allocator, terminal_buffer: *TerminalBuffer, top_color: u32, middle_color: u32, bottom_color: u32, fire_height: u8, fire_spread: u8) !Doom {
    const buffer = try allocator.alloc(u8, terminal_buffer.width * terminal_buffer.height);
    initBuffer(buffer, terminal_buffer.width);

    const levels =
        [_]Cell{
            Cell.init(' ', terminal_buffer.bg, terminal_buffer.bg),
            Cell.init(0x2591, top_color, terminal_buffer.bg),
            Cell.init(0x2592, top_color, terminal_buffer.bg),
            Cell.init(0x2593, top_color, terminal_buffer.bg),
            Cell.init(0x2588, top_color, terminal_buffer.bg),
            Cell.init(0x2591, middle_color, top_color),
            Cell.init(0x2592, middle_color, top_color),
            Cell.init(0x2593, middle_color, top_color),
            Cell.init(0x2588, middle_color, top_color),
            Cell.init(0x2591, bottom_color, middle_color),
            Cell.init(0x2592, bottom_color, middle_color),
            Cell.init(0x2593, bottom_color, middle_color),
            Cell.init(0x2588, bottom_color, middle_color),
        };

    return .{
        .allocator = allocator,
        .terminal_buffer = terminal_buffer,
        .buffer = buffer,
        .height = @min(HEIGHT_MAX, fire_height),
        .spread = @min(SPREAD_MAX, fire_spread),
        .fire = levels,
    };
}

pub fn widget(self: *Doom) Widget {
    return Widget.init(
        self,
        deinit,
        realloc,
        draw,
        null,
        null,
    );
}

fn deinit(self: *Doom) void {
    self.allocator.free(self.buffer);
}

fn realloc(self: *Doom) !void {
    const buffer = try self.allocator.realloc(self.buffer, self.terminal_buffer.width * self.terminal_buffer.height);
    initBuffer(buffer, self.terminal_buffer.width);
    self.buffer = buffer;
}

fn draw(self: *Doom) void {
    for (0..self.terminal_buffer.width) |x| {
        // We start from 1 so that we always have the topmost line when spreading fire
        for (1..self.terminal_buffer.height) |y| {
            // Get index of current cell in fire level buffer
            const from = y * self.terminal_buffer.width + x;

            // Generate random data for fire propagation
            const rand_loss = self.terminal_buffer.random.intRangeAtMost(u8, 0, HEIGHT_MAX);
            const rand_spread = self.terminal_buffer.random.intRangeAtMost(u8, 0, self.spread * 2);

            // Select semi-random target cell
            const to = from -| self.terminal_buffer.width + self.spread -| rand_spread;
            const to_x = to % self.terminal_buffer.width;
            const to_y = to / self.terminal_buffer.width;

            // Get fire level of current cell
            const level_buf_from = self.buffer[from];

            // Choose new fire level and store in level buffer
            const level_buf_to = level_buf_from -| @intFromBool(rand_loss >= self.height);
            self.buffer[to] = level_buf_to;

            // Send known fire levels to terminal buffer
            const from_cell = self.fire[level_buf_from];
            const to_cell = self.fire[level_buf_to];
            from_cell.put(x, y);
            to_cell.put(to_x, to_y);
        }

        // Draw bottom line (fire source)
        const src_cell = self.fire[STEPS];
        src_cell.put(x, self.terminal_buffer.height - 1);
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
