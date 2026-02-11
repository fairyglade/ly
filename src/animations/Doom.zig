const std = @import("std");
const Allocator = std.mem.Allocator;

const ly_core = @import("ly-core");
const interop = ly_core.interop;
const TimeOfDay = interop.TimeOfDay;

const Cell = @import("../tui/Cell.zig");
const TerminalBuffer = @import("../tui/TerminalBuffer.zig");
const Widget = @import("../tui/Widget.zig");

const Doom = @This();

pub const STEPS = 12;
pub const HEIGHT_MAX = 9;
pub const SPREAD_MAX = 4;

start_time: TimeOfDay,
allocator: Allocator,
terminal_buffer: *TerminalBuffer,
animate: *bool,
timeout_sec: u12,
frame_delay: u16,
buffer: []u8,
height: u8,
spread: u8,
fire: [STEPS + 1]Cell,

pub fn init(
    allocator: Allocator,
    terminal_buffer: *TerminalBuffer,
    top_color: u32,
    middle_color: u32,
    bottom_color: u32,
    fire_height: u8,
    fire_spread: u8,
    animate: *bool,
    timeout_sec: u12,
    frame_delay: u16,
) !Doom {
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
        .start_time = try interop.getTimeOfDay(),
        .allocator = allocator,
        .terminal_buffer = terminal_buffer,
        .animate = animate,
        .timeout_sec = timeout_sec,
        .frame_delay = frame_delay,
        .buffer = buffer,
        .height = @min(HEIGHT_MAX, fire_height),
        .spread = @min(SPREAD_MAX, fire_spread),
        .fire = levels,
    };
}

pub fn widget(self: *Doom) Widget {
    return Widget.init(
        "Doom",
        self,
        deinit,
        realloc,
        draw,
        update,
        null,
        calculateTimeout,
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
    if (!self.animate.*) return;

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

fn update(self: *Doom, _: *anyopaque) !void {
    const time = try interop.getTimeOfDay();

    if (self.timeout_sec > 0 and time.seconds - self.start_time.seconds > self.timeout_sec) {
        self.animate.* = false;
    }
}

fn calculateTimeout(self: *Doom, _: *anyopaque) !?usize {
    return self.frame_delay;
}
