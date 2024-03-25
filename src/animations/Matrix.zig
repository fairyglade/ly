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

pub fn draw(self: *Matrix) void {
    const buf_height = self.terminal_buffer.height;
    const buf_width = self.terminal_buffer.width;
    self.count += 1;
    if (self.count > FRAME_DELAY) {
        self.frame += 1;
        if (self.frame > 4) self.frame = 1;
        self.count = 0;

        var j: u64 = 0;
        while (j < self.terminal_buffer.width) : (j += 2) {
            var tail: u64 = 0;
            var line = &self.lines[j];
            if (self.frame > line.update) {
                if (self.dots[j].value == -1 and self.dots[self.terminal_buffer.width + j].value == ' ') {
                    if (line.space > 0) {
                        line.space -= 1;
                    } else {
                        const randint = self.terminal_buffer.random.int(i16);
                        const h: isize = @intCast(self.terminal_buffer.height);
                        line.length = @mod(randint, h - 3) + 3;
                        self.dots[j].value = @mod(randint, MAX_CODEPOINT) + MIN_CODEPOINT;
                        line.space = @mod(randint, h + 1);
                    }
                }

                var i: u64 = 0;
                var first_col = true;
                var seg_len: u64 = 0;
                height_it: while (i <= buf_height) {
                    var dot = &self.dots[buf_width * i + j];
                    // Skip over spaces
                    while (i <= buf_height and (dot.value == ' ' or dot.value == -1)) {
                        i += 1;
                        if (i > buf_height) break :height_it;
                        dot = &self.dots[buf_width * i + j];
                    }

                    // Find the head of this col
                    tail = i;
                    seg_len = 0;
                    while (i <= buf_height and (dot.value != ' ' and dot.value != -1)) {
                        dot.is_head = false;
                        if (MID_SCROLL_CHANGE) {
                            const randint = self.terminal_buffer.random.int(i16);
                            if (@mod(randint, 8) == 0)
                                dot.value = @mod(randint, MAX_CODEPOINT) + MIN_CODEPOINT;
                        }

                        i += 1;
                        seg_len += 1;
                        // Head's down offscreen
                        if (i > buf_height) {
                            self.dots[buf_width * tail + j].value = ' ';
                            continue :height_it;
                        }
                        dot = &self.dots[buf_width * i + j];
                    }

                    const randint = self.terminal_buffer.random.int(i16);
                    dot.value = @mod(randint, MAX_CODEPOINT) + MIN_CODEPOINT;
                    dot.is_head = true;

                    if (seg_len > self.lines[j].length or !first_col) {
                        self.dots[buf_width * tail + j].value = ' ';
                        self.dots[j].value = -1;
                    }
                    first_col = false;
                    i += 1;
                }
            }
        }
    }

    var j: u64 = 0;
    while (j < buf_width) : (j += 2) {
        var i: u64 = 1;
        while (i <= self.terminal_buffer.height) : (i += 1) {
            const dot = self.dots[buf_width * i + j];
            var fg: u32 = @intCast(termbox.TB_GREEN);

            if (dot.value == -1 or dot.value == ' ') {
                termbox.tb_change_cell(@intCast(j), @intCast(i - 1), ' ', fg, termbox.TB_DEFAULT);
                continue;
            }

            if (dot.is_head) fg = @intCast(termbox.TB_WHITE | termbox.TB_BOLD);
            termbox.tb_change_cell(@intCast(j), @intCast(i - 1), @intCast(dot.value), fg, termbox.TB_DEFAULT);
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
