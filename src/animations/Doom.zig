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
height: u8,
fire: [STEPS + 1]Cell,

pub fn init(allocator: Allocator, terminal_buffer: *TerminalBuffer, fire_height: u8, default_colors: bool, top_color: u32, middle_color: u32, bottom_color: u32) !Doom {
    const buffer = try allocator.alloc(u8, terminal_buffer.width * terminal_buffer.height);
    initBuffer(buffer, terminal_buffer.width);

    const levels = if (default_colors)
        [_]Cell{
            Cell.init(' ', TerminalBuffer.Color.DEFAULT, TerminalBuffer.Color.DEFAULT),
            Cell.init(0x2591, 0x070707, TerminalBuffer.Color.DEFAULT),
            Cell.init(0x2592, 0x470F07, TerminalBuffer.Color.DEFAULT),
            Cell.init(0x2593, 0x771F07, TerminalBuffer.Color.DEFAULT),
            Cell.init(0x2588, 0xAF3F07, TerminalBuffer.Color.DEFAULT),
            Cell.init(0x2591, 0xC74707, 0xAF3F07),
            Cell.init(0x2592, 0xDF5707, 0xAF3F07),
            Cell.init(0x2593, 0xCF6F0F, 0xAF3F07),
            Cell.init(0x2588, 0xC78F17, 0xAF3F07),
            Cell.init(0x2591, 0xBF9F1F, 0xAF3F07),
            Cell.init(0x2592, 0xBFAF2F, 0xAF3F07),
            Cell.init(0x2593, 0xCFCF6F, 0xAF3F07),
            Cell.init(0x2588, 0xFFFFFF, 0xAF3F07),
        }
    else
        [_]Cell{
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
        };

    return .{
        .allocator = allocator,
        .terminal_buffer = terminal_buffer,
        .buffer = buffer,
        .height = @min(9, fire_height),
        .fire = levels,
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
            // Get index of current cell in fire level buffer
            const from = y * self.terminal_buffer.width + x;

            // Generate random datum for fire propagation
            const random = (self.terminal_buffer.random.int(u16) % 10);

            // Select semi-random target cell
            const to = from -| self.terminal_buffer.width -| (random & 3) + 1;

            // Get fire level of current cell
            const level_buf_from = self.buffer[from];

            // Choose new fire level and store in level buffer
            var level_buf_to = level_buf_from;
            if (random >= self.height) level_buf_to -|= 1;
            self.buffer[to] = @intCast(level_buf_to);

            // Send fire level to terminal buffer
            const to_cell = self.fire[level_buf_to];
            to_cell.put(x, y);
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
