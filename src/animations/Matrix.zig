const std = @import("std");
const Allocator = std.mem.Allocator;
const Random = std.rand.Random;
const TerminalBuffer = @import("../tui/TerminalBuffer.zig");

const interop = @import("../interop.zig");
const termbox = interop.termbox;

pub const FRAME_DELAY: u64 = 8;

// Allowed codepoints
pub const MIN_CODEPOINT: isize = 33;
pub const MAX_CODEPOINT: isize = 123 - MIN_CODEPOINT;

// Characters change mid-scroll
pub const MID_SCROLL_CHANGE = true;

const Matrix = @This();

pub const Dot = struct {
    value: isize,
    is_head: bool,
};

pub const Line = struct {
    space: isize,
    length: isize,
    update: isize,
};

allocator: Allocator,
terminal_buffer: *TerminalBuffer,
dots: []Dot,
lines: []Line,
frame: u64,
count: u64,
fg_ini: u16,

pub fn init(allocator: Allocator, terminal_buffer: *TerminalBuffer, fg_ini: u16) !Matrix {
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
        .fg_ini = fg_ini,
    };
}

pub fn deinit(self: Matrix) void {
    self.allocator.free(self.dots);
    self.allocator.free(self.lines);
}

pub fn realloc(self: *Matrix) !void {
    const dots = try self.allocator.realloc(self.dots, self.terminal_buffer.width * (self.terminal_buffer.height + 1));
    const lines = try self.allocator.realloc(self.lines, self.terminal_buffer.width);

    initBuffers(dots, lines, self.terminal_buffer.width, self.terminal_buffer.height, self.terminal_buffer.random);

    self.dots = dots;
    self.lines = lines;
}

pub fn draw(self: *Matrix) void {
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

            if (self.dots[x].value == -1 and self.dots[self.terminal_buffer.width + x].value == ' ') {
                if (line.space > 0) {
                    line.space -= 1;
                } else {
                    const randint = self.terminal_buffer.random.int(i16);
                    const h: isize = @intCast(self.terminal_buffer.height);
                    line.length = @mod(randint, h - 3) + 3;
                    self.dots[x].value = @mod(randint, MAX_CODEPOINT) + MIN_CODEPOINT;
                    line.space = @mod(randint, h + 1);
                }
            }

            var y: usize = 0;
            var first_col = true;
            var seg_len: u64 = 0;
            height_it: while (y <= buf_height) : (y += 1) {
                var dot = &self.dots[buf_width * y + x];
                // Skip over spaces
                while (y <= buf_height and (dot.value == ' ' or dot.value == -1)) {
                    y += 1;
                    if (y > buf_height) break :height_it;
                    dot = &self.dots[buf_width * y + x];
                }

                // Find the head of this column
                tail = y;
                seg_len = 0;
                while (y <= buf_height and dot.value != ' ' and dot.value != -1) {
                    dot.is_head = false;
                    if (MID_SCROLL_CHANGE) {
                        const randint = self.terminal_buffer.random.int(i16);
                        if (@mod(randint, 8) == 0) {
                            dot.value = @mod(randint, MAX_CODEPOINT) + MIN_CODEPOINT;
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

                const randint = self.terminal_buffer.random.int(i16);
                dot.value = @mod(randint, MAX_CODEPOINT) + MIN_CODEPOINT;
                dot.is_head = true;

                if (seg_len > line.length or !first_col) {
                    self.dots[buf_width * tail + x].value = ' ';
                    self.dots[x].value = -1;
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

            var fg = self.fg_ini;

            if (dot.value == -1 or dot.value == ' ') {
                _ = termbox.tb_set_cell(@intCast(x), @intCast(y - 1), ' ', fg, termbox.TB_DEFAULT);
                continue;
            }

            if (dot.is_head) fg = @intCast(termbox.TB_WHITE | termbox.TB_BOLD);
            _ = termbox.tb_set_cell(@intCast(x), @intCast(y - 1), @intCast(dot.value), fg, termbox.TB_DEFAULT);
        }
    }
}

fn initBuffers(dots: []Dot, lines: []Line, width: usize, height: usize, random: Random) void {
    var y: usize = 0;
    while (y <= height) : (y += 1) {
        var x: usize = 0;
        while (x < width) : (x += 2) {
            dots[y * width + x].value = -1;
        }
    }

    var x: usize = 0;
    while (x < width) : (x += 2) {
        var line = lines[x];
        const h: isize = @intCast(height);
        line.space = @mod(random.int(i16), h) + 1;
        line.length = @mod(random.int(i16), h - 3) + 3;
        line.update = @mod(random.int(i16), 3) + 1;
        lines[x] = line;

        dots[width + x].value = ' ';
    }
}
