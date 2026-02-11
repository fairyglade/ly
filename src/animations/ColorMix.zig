const std = @import("std");
const math = std.math;

const ly_core = @import("ly-core");
const interop = ly_core.interop;
const TimeOfDay = interop.TimeOfDay;

const Cell = @import("../tui/Cell.zig");
const TerminalBuffer = @import("../tui/TerminalBuffer.zig");
const Widget = @import("../tui/Widget.zig");

const ColorMix = @This();

const Vec2 = @Vector(2, f32);

const time_scale: f32 = 0.01;
const palette_len: usize = 12;

fn length(vec: Vec2) f32 {
    return math.sqrt(vec[0] * vec[0] + vec[1] * vec[1]);
}

start_time: TimeOfDay,
terminal_buffer: *TerminalBuffer,
animate: *bool,
timeout_sec: u12,
frame_delay: u16,
frames: u64,
pattern_cos_mod: f32,
pattern_sin_mod: f32,
palette: [palette_len]Cell,

pub fn init(
    terminal_buffer: *TerminalBuffer,
    col1: u32,
    col2: u32,
    col3: u32,
    animate: *bool,
    timeout_sec: u12,
    frame_delay: u16,
) !ColorMix {
    return .{
        .start_time = try interop.getTimeOfDay(),
        .terminal_buffer = terminal_buffer,
        .animate = animate,
        .timeout_sec = timeout_sec,
        .frame_delay = frame_delay,
        .frames = 0,
        .pattern_cos_mod = terminal_buffer.random.float(f32) * math.pi * 2.0,
        .pattern_sin_mod = terminal_buffer.random.float(f32) * math.pi * 2.0,
        .palette = [palette_len]Cell{
            Cell.init(0x2588, col1, col2),
            Cell.init(0x2593, col1, col2),
            Cell.init(0x2592, col1, col2),
            Cell.init(0x2591, col1, col2),
            Cell.init(0x2588, col2, col3),
            Cell.init(0x2593, col2, col3),
            Cell.init(0x2592, col2, col3),
            Cell.init(0x2591, col2, col3),
            Cell.init(0x2588, col3, col1),
            Cell.init(0x2593, col3, col1),
            Cell.init(0x2592, col3, col1),
            Cell.init(0x2591, col3, col1),
        },
    };
}

pub fn widget(self: *ColorMix) Widget {
    return Widget.init(
        "ColorMix",
        self,
        null,
        null,
        draw,
        update,
        null,
        calculateTimeout,
    );
}

fn draw(self: *ColorMix) void {
    if (!self.animate.*) return;

    self.frames +%= 1;
    const time: f32 = @as(f32, @floatFromInt(self.frames)) * time_scale;

    for (0..self.terminal_buffer.width) |x| {
        for (0..self.terminal_buffer.height) |y| {
            const xi: i32 = @intCast(x);
            const yi: i32 = @intCast(y);
            const wi: i32 = @intCast(self.terminal_buffer.width);
            const hi: i32 = @intCast(self.terminal_buffer.height);

            var uv: Vec2 = .{
                @as(f32, @floatFromInt(xi * 2 - wi)) / @as(f32, @floatFromInt(self.terminal_buffer.height * 2)),
                @as(f32, @floatFromInt(yi * 2 - hi)) / @as(f32, @floatFromInt(self.terminal_buffer.height)),
            };

            var uv2: Vec2 = @splat(uv[0] + uv[1]);

            for (0..3) |_| {
                uv2 += uv + @as(Vec2, @splat(length(uv)));
                uv += @as(Vec2, @splat(0.5)) * Vec2{
                    math.cos(self.pattern_cos_mod + uv2[1] * 0.2 + time * 0.1),
                    math.sin(self.pattern_sin_mod + uv2[0] - time * 0.1),
                };
                uv -= @splat(1.0 * math.cos(uv[0] + uv[1]) - math.sin(uv[0] * 0.7 - uv[1]));
            }

            const cell = self.palette[@as(usize, @intFromFloat(math.floor(length(uv) * 5.0))) % palette_len];
            cell.put(x, y);
        }
    }
}

fn update(self: *ColorMix, _: *anyopaque) !void {
    const time = try interop.getTimeOfDay();

    if (self.timeout_sec > 0 and time.seconds - self.start_time.seconds > self.timeout_sec) {
        self.animate.* = false;
    }
}

fn calculateTimeout(self: *ColorMix, _: *anyopaque) !?usize {
    return self.frame_delay;
}
