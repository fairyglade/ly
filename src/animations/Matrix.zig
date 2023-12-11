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

pub fn init(allocator: Allocator, terminal_buffer: *TerminalBuffer) !Matrix {
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

// TODO: Fix!!
pub fn draw(self: *Matrix) void {
    var first_column = false;

    self.count += 1;
    if (self.count > FRAME_DELAY) {
        self.frame += 1;
        if (self.frame > 4) self.frame = 1;
        self.count = 0;

        var x: u64 = 0;
        while (x < self.terminal_buffer.width) : (x += 2) {
            var line = self.lines[x];
            if (self.frame <= line.update) continue;

            var tail: u64 = 0;
            if (self.dots[x].value == -1 and self.dots[self.terminal_buffer.width + x].value == ' ') {
                if (line.space <= 0) {
                    const random = self.terminal_buffer.random.int(i16);
                    const h: isize = @intCast(self.terminal_buffer.height);
                    line.length = @mod(random, h - 3) + 3;
                    line.space = @mod(random, h) + 1;
                    self.dots[x].value = @mod(random, MAX_CODEPOINT) + MIN_CODEPOINT;
                } else {
                    line.space -= 1;
                }

                self.lines[x] = line;
                first_column = true;

                var y: u64 = 0;
                var seg_length: u64 = 0;

                while (y <= self.terminal_buffer.height) : (y += 1) {
                    // TODO: Are all these y/height checks required?
                    var dot = self.dots[y * self.terminal_buffer.width + x];

                    // Skip over spaces
                    while (dot.value == ' ' or dot.value == -1) {
                        y += 1;
                        if (y > self.terminal_buffer.height) break;

                        dot = self.dots[y * self.terminal_buffer.width + x];
                    }
                    if (y > self.terminal_buffer.height) break;

                    // Find the head of this column
                    tail = y;
                    seg_length = 0;
                    while (y <= self.terminal_buffer.height and dot.value != ' ' and dot.value != -1) {
                        dot.is_head = false;
                        if (MID_SCROLL_CHANGE) {
                            const random = self.terminal_buffer.random.int(i16);
                            if (@mod(random, 8) == 0) dot.value = @mod(random, MAX_CODEPOINT) + MIN_CODEPOINT;
                        }
                        self.dots[y * self.terminal_buffer.width + x] = dot;

                        y += 1;
                        seg_length += 1;
                        dot = self.dots[y * self.terminal_buffer.width + x];
                    }

                    // The head is down offscreen
                    if (y > self.terminal_buffer.height) {
                        self.dots[tail * self.terminal_buffer.width + x].value = ' ';
                        continue; // TODO: Shouldn't this be break?
                    }

                    const random = self.terminal_buffer.random.int(i16);
                    self.dots[y * self.terminal_buffer.width + x].value = @mod(random, MAX_CODEPOINT) + MIN_CODEPOINT;
                    self.dots[y * self.terminal_buffer.width + x].is_head = true;

                    if (seg_length > line.length or !first_column) {
                        self.dots[tail * self.terminal_buffer.width + x].value = ' ';
                        self.dots[x].value = -1;
                    }
                    first_column = false;
                }
            }
        }
    }

    var x: u64 = 0;
    while (x < self.terminal_buffer.width) : (x += 2) {
        var y: u64 = 1;
        while (y <= self.terminal_buffer.height) : (y += 1) {
            const dot = self.dots[y * self.terminal_buffer.width + x];
            var fg: u32 = @intCast(termbox.TB_GREEN);

            if (dot.value == -1 or dot.value == ' ') {
                termbox.tb_change_cell(@intCast(x), @intCast(y - 1), ' ', fg, termbox.TB_DEFAULT);
                continue;
            }

            if (dot.is_head) fg = @intCast(termbox.TB_WHITE | termbox.TB_BOLD);
            termbox.tb_change_cell(@intCast(x), @intCast(y - 1), @intCast(dot.value), fg, termbox.TB_DEFAULT);
        }
    }
}

fn initBuffers(dots: []Dot, lines: []Line, width: u64, height: u64, random: Random) void {
    var y: u64 = 0;
    while (y <= height) : (y += 1) {
        var x: u64 = 0;
        while (x < width) : (x += 2) {
            dots[y * width + x].value = -1;
        }
    }

    var x: u64 = 0;
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
