const std = @import("std");
const Animation = @import("../tui/Animation.zig");
const Cell = @import("../tui/Cell.zig");
const TerminalBuffer = @import("../tui/TerminalBuffer.zig");

const Allocator = std.mem.Allocator;
const Random = std.Random;

pub const FRAME_DELAY: usize = 8;

// Characters change mid-scroll
pub const MID_SCROLL_CHANGE = true;

const DOT_HEAD_COLOR: u32 = @intCast(TerminalBuffer.Color.WHITE | TerminalBuffer.Styling.BOLD);

const Matrix = @This();

pub const Dot = struct {
    value: ?usize,
    is_head: bool,
};

pub const Line = struct {
    space: usize,
    length: usize,
    update: usize,
};

allocator: Allocator,
terminal_buffer: *TerminalBuffer,
dots: []Dot,
lines: []Line,
frame: usize,
count: usize,
fg: u32,
min_codepoint: u16,
max_codepoint: u16,
default_cell: Cell,

pub fn init(allocator: Allocator, terminal_buffer: *TerminalBuffer, fg: u32, min_codepoint: u16, max_codepoint: u16) !Matrix {
    const dots = try allocator.alloc(Dot, terminal_buffer.width * (terminal_buffer.height + 1));
    const lines = try allocator.alloc(Line, terminal_buffer.width);

    initBuffers(dots, lines, terminal_buffer.width, terminal_buffer.height, terminal_buffer.random);

    return .{
        .allocator = allocator,
        .terminal_buffer = terminal_buffer,
        .dots = dots,
        .lines = lines,
        .frame = 3,
        .count = 0,
        .fg = fg,
        .min_codepoint = min_codepoint,
        .max_codepoint = max_codepoint - min_codepoint,
        .default_cell = .{ .ch = ' ', .fg = fg, .bg = terminal_buffer.bg },
    };
}

pub fn animation(self: *Matrix) Animation {
    return Animation.init(self, deinit, realloc, draw);
}

fn deinit(self: *Matrix) void {
    self.allocator.free(self.dots);
    self.allocator.free(self.lines);
}

fn realloc(self: *Matrix) anyerror!void {
    const dots = try self.allocator.realloc(self.dots, self.terminal_buffer.width * (self.terminal_buffer.height + 1));
    const lines = try self.allocator.realloc(self.lines, self.terminal_buffer.width);

    initBuffers(dots, lines, self.terminal_buffer.width, self.terminal_buffer.height, self.terminal_buffer.random);

    self.dots = dots;
    self.lines = lines;
}

fn draw(self: *Matrix) void {
    const buf_height = self.terminal_buffer.height;
    const buf_width = self.terminal_buffer.width;
    self.count += 1;
    if (self.count > FRAME_DELAY) {
        self.frame += 1;
        if (self.frame > 4) self.frame = 1;
        self.count = 0;

        var x: usize = 0;
        while (x < self.terminal_buffer.width) : (x += 2) {
            var tail: usize = 0;
            var line = &self.lines[x];
            if (self.frame <= line.update) continue;

            if (self.dots[x].value == null and self.dots[self.terminal_buffer.width + x].value == ' ') {
                if (line.space > 0) {
                    line.space -= 1;
                } else {
                    const randint = self.terminal_buffer.random.int(u16);
                    const h = self.terminal_buffer.height;
                    line.length = @mod(randint, h - 3) + 3;
                    self.dots[x].value = @mod(randint, self.max_codepoint) + self.min_codepoint;
                    line.space = @mod(randint, h + 1);
                }
            }

            var y: usize = 0;
            var first_col = true;
            var seg_len: u64 = 0;
            height_it: while (y <= buf_height) : (y += 1) {
                var dot = &self.dots[buf_width * y + x];
                // Skip over spaces
                while (y <= buf_height and (dot.value == ' ' or dot.value == null)) {
                    y += 1;
                    if (y > buf_height) break :height_it;
                    dot = &self.dots[buf_width * y + x];
                }

                // Find the head of this column
                tail = y;
                seg_len = 0;
                while (y <= buf_height and dot.value != ' ' and dot.value != null) {
                    dot.is_head = false;
                    if (MID_SCROLL_CHANGE) {
                        const randint = self.terminal_buffer.random.int(u16);
                        if (@mod(randint, 8) == 0) {
                            dot.value = @mod(randint, self.max_codepoint) + self.min_codepoint;
                        }
                    }

                    y += 1;
                    seg_len += 1;
                    // Head's down offscreen
                    if (y > buf_height) {
                        self.dots[buf_width * tail + x].value = ' ';
                        break :height_it;
                    }
                    dot = &self.dots[buf_width * y + x];
                }

                const randint = self.terminal_buffer.random.int(u16);
                dot.value = @mod(randint, self.max_codepoint) + self.min_codepoint;
                dot.is_head = true;

                if (seg_len > line.length or !first_col) {
                    self.dots[buf_width * tail + x].value = ' ';
                    self.dots[x].value = null;
                }
                first_col = false;
            }
        }
    }

    var x: usize = 0;
    while (x < buf_width) : (x += 2) {
        var y: usize = 1;
        while (y <= self.terminal_buffer.height) : (y += 1) {
            const dot = self.dots[buf_width * y + x];
            const cell = if (dot.value == null or dot.value == ' ') self.default_cell else Cell{
                .ch = @intCast(dot.value.?),
                .fg = if (dot.is_head) DOT_HEAD_COLOR else self.fg,
                .bg = self.terminal_buffer.bg,
            };

            cell.put(x, y - 1);
        }
    }
}

fn initBuffers(dots: []Dot, lines: []Line, width: usize, height: usize, random: Random) void {
    var y: usize = 0;
    while (y <= height) : (y += 1) {
        var x: usize = 0;
        while (x < width) : (x += 2) {
            dots[y * width + x].value = null;
        }
    }

    var x: usize = 0;
    while (x < width) : (x += 2) {
        var line = lines[x];
        line.space = @mod(random.int(u16), height) + 1;
        line.length = @mod(random.int(u16), height - 3) + 3;
        line.update = @mod(random.int(u16), 3) + 1;
        lines[x] = line;

        dots[width + x].value = ' ';
    }
}
