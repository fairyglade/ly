const std = @import("std");
const Allocator = std.mem.Allocator;
const Animation = @import("../tui/Animation.zig");
const Cell = @import("../tui/Cell.zig");
const TerminalBuffer = @import("../tui/TerminalBuffer.zig");

const Metaballs = @This();

const math = std.math;
const Vec2 = @Vector(2, f32);

const num_metaballs = 5;
const min_radius: f32 = 5.0;
const max_radius: f32 = 12.0;
const max_speed: f32 = 0.2;

const threshold: f32 = 0.7;

const Metaball = struct {
    pos: Vec2,
    vel: Vec2,
    radius: f32,
};

allocator: Allocator,
terminal_buffer: *TerminalBuffer,
balls: [num_metaballs]Metaball,
palette: [5]Cell,

pub fn init(allocator: Allocator, terminal_buffer: *TerminalBuffer) !Metaballs {
    var self = Metaballs{
        .allocator = allocator,
        .terminal_buffer = terminal_buffer,
        .balls = undefined,
        .palette = [_]Cell{
            Cell.init(' ', 0x2c0000, 0x4f0000),
            Cell.init(0x2591, 0x8b0000, 0xae0000),
            Cell.init(0x2592, 0xff4500, 0xff6347),
            Cell.init(0x2593, 0xffa500, 0xffd700),
            Cell.init(0x2588, 0xffff00, 0xffffe0),
        },
    };

    self.initBalls();
    return self;
}

fn initBalls(self: *Metaballs) void {
    const width_f = @as(f32, @floatFromInt(self.terminal_buffer.width));
    const height_f = @as(f32, @floatFromInt(self.terminal_buffer.height));
    const rand = self.terminal_buffer.random;

    for (&self.balls) |*ball| {
        ball.* = .{
            .pos = .{
                rand.float(f32) * width_f,
                rand.float(f32) * height_f,
            },
            .vel = .{
                (rand.float(f32) - 0.5) * 2.0 * max_speed,
                (rand.float(f32) - 0.5) * 2.0 * max_speed,
            },
            .radius = min_radius + (rand.float(f32) * (max_radius - min_radius)),
        };
    }
}

pub fn animation(self: *Metaballs) Animation {
    return Animation.init(self, deinit, realloc, draw);
}

fn deinit(_: *Metaballs) void {}

fn realloc(self: *Metaballs) anyerror!void {
    self.initBalls();
}

fn draw(self: *Metaballs) void {
    const width = self.terminal_buffer.width;
    const height = self.terminal_buffer.height;
    const width_f = @as(f32, @floatFromInt(width));
    const height_f = @as(f32, @floatFromInt(height));

    for (&self.balls) |*ball| {
        ball.pos += ball.vel;

        if (ball.pos[0] < 0 or ball.pos[0] > width_f) {
            ball.vel[0] *= -1.0;
            ball.pos[0] = math.clamp(ball.pos[0], 0, width_f);
        }
        if (ball.pos[1] < 0 or ball.pos[1] > height_f) {
            ball.vel[1] *= -1.0;
            ball.pos[1] = math.clamp(ball.pos[1], 0, height_f);
        }
    }

    for (0..height) |y| {
        for (0..width) |x| {
            const cell_pos = Vec2{
                @as(f32, @floatFromInt(x)) + 0.5,
                @as(f32, @floatFromInt(y)) + 0.5,
            };

            var sum_influence: f32 = 0.0;
            for (self.balls) |ball| {
                const dist_vec = cell_pos - ball.pos;
                const dist_sq = (dist_vec[0] * dist_vec[0]) + (dist_vec[1] * dist_vec[1]);

                if (dist_sq == 0) {
                    sum_influence += 1000.0;
                } else {
                    sum_influence += (ball.radius * ball.radius) / dist_sq;
                }
            }

            if (sum_influence > threshold * 1.1) {
                self.palette[4].put(x, y);
            } else if (sum_influence > threshold * 1.0) {
                self.palette[3].put(x, y);
            } else if (sum_influence > threshold * 0.9) {
                self.palette[2].put(x, y);
            } else if (sum_influence > threshold * 0.8) {
                self.palette[1].put(x, y);
            } else {
                self.palette[0].put(x, y);
            }
        }
    }
}
