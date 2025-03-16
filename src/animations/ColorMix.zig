const std = @import("std");
const Animation = @import("../tui/Animation.zig");
const Cell = @import("../tui/Cell.zig");
const TerminalBuffer = @import("../tui/TerminalBuffer.zig");

const ColorMix = @This();

const math = std.math;
const Vec2 = @Vector(2, f32);

const time_scale: f32 = 0.01;
const palette_len: usize = 12;

fn length(vec: Vec2) f32 {
    return math.sqrt(vec[0] * vec[0] + vec[1] * vec[1]);
}

terminal_buffer: *TerminalBuffer,
frames: u64,
pattern_cos_mod: f32,
pattern_sin_mod: f32,
palette: [palette_len]Cell,

pub fn init(terminal_buffer: *TerminalBuffer, col1: u32, col2: u32, col3: u32) ColorMix {
    return .{
        .terminal_buffer = terminal_buffer,
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

pub fn animation(self: *ColorMix) Animation {
    return Animation.init(self, deinit, realloc, draw);
}

fn deinit(_: *ColorMix) void {}

fn realloc(_: *ColorMix) anyerror!void {}

fn draw(self: *ColorMix) void {
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
