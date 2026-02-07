const std = @import("std");
const Random = std.Random;

const ly_core = @import("ly-core");
const interop = ly_core.interop;
const LogFile = ly_core.LogFile;
pub const termbox = @import("termbox2");

const Cell = @import("Cell.zig");

const TerminalBuffer = @This();

pub const InitOptions = struct {
    fg: u32,
    bg: u32,
    border_fg: u32,
    margin_box_h: u8,
    margin_box_v: u8,
    input_len: u8,
    full_color: bool,
    labels_max_length: usize,
    is_tty: bool,
};

pub const Styling = struct {
    pub const BOLD = termbox.TB_BOLD;
    pub const UNDERLINE = termbox.TB_UNDERLINE;
    pub const REVERSE = termbox.TB_REVERSE;
    pub const ITALIC = termbox.TB_ITALIC;
    pub const BLINK = termbox.TB_BLINK;
    pub const HI_BLACK = termbox.TB_HI_BLACK;
    pub const BRIGHT = termbox.TB_BRIGHT;
    pub const DIM = termbox.TB_DIM;
};

pub const Color = struct {
    pub const DEFAULT = 0x00000000;
    pub const TRUE_BLACK = Styling.HI_BLACK;
    pub const TRUE_RED = 0x00FF0000;
    pub const TRUE_GREEN = 0x0000FF00;
    pub const TRUE_YELLOW = 0x00FFFF00;
    pub const TRUE_BLUE = 0x000000FF;
    pub const TRUE_MAGENTA = 0x00FF00FF;
    pub const TRUE_CYAN = 0x0000FFFF;
    pub const TRUE_WHITE = 0x00FFFFFF;
    pub const TRUE_DIM_RED = 0x00800000;
    pub const TRUE_DIM_GREEN = 0x00008000;
    pub const TRUE_DIM_YELLOW = 0x00808000;
    pub const TRUE_DIM_BLUE = 0x00000080;
    pub const TRUE_DIM_MAGENTA = 0x00800080;
    pub const TRUE_DIM_CYAN = 0x00008080;
    pub const TRUE_DIM_WHITE = 0x00C0C0C0;
    pub const ECOL_BLACK = 1;
    pub const ECOL_RED = 2;
    pub const ECOL_GREEN = 3;
    pub const ECOL_YELLOW = 4;
    pub const ECOL_BLUE = 5;
    pub const ECOL_MAGENTA = 6;
    pub const ECOL_CYAN = 7;
    pub const ECOL_WHITE = 8;
};

random: Random,
width: usize,
height: usize,
fg: u32,
bg: u32,
border_fg: u32,
box_chars: struct {
    left_up: u32,
    left_down: u32,
    right_up: u32,
    right_down: u32,
    top: u32,
    bottom: u32,
    left: u32,
    right: u32,
},
labels_max_length: usize,
box_x: usize,
box_y: usize,
box_width: usize,
box_height: usize,
margin_box_v: u8,
margin_box_h: u8,
blank_cell: Cell,
full_color: bool,
termios: ?std.posix.termios,

pub fn init(options: InitOptions, log_file: *LogFile, random: Random) !TerminalBuffer {
    // Initialize termbox
    _ = termbox.tb_init();

    if (options.full_color) {
        _ = termbox.tb_set_output_mode(termbox.TB_OUTPUT_TRUECOLOR);
        try log_file.info("tui", "termbox2 set to 24-bit color output mode", .{});
    } else {
        try log_file.info("tui", "termbox2 set to eight-color output mode", .{});
    }

    _ = termbox.tb_clear();

    // Let's take some precautions here and clear the back buffer as well
    try clearBackBuffer();

    const width: usize = @intCast(termbox.tb_width());
    const height: usize = @intCast(termbox.tb_height());

    try log_file.info("tui", "screen resolution is {d}x{d}", .{ width, height });

    return .{
        .random = random,
        .width = width,
        .height = height,
        .fg = options.fg,
        .bg = options.bg,
        .border_fg = options.border_fg,
        .box_chars = if (interop.supportsUnicode()) .{
            .left_up = 0x250C,
            .left_down = 0x2514,
            .right_up = 0x2510,
            .right_down = 0x2518,
            .top = 0x2500,
            .bottom = 0x2500,
            .left = 0x2502,
            .right = 0x2502,
        } else .{
            .left_up = '+',
            .left_down = '+',
            .right_up = '+',
            .right_down = '+',
            .top = '-',
            .bottom = '-',
            .left = '|',
            .right = '|',
        },
        .labels_max_length = options.labels_max_length,
        .box_x = 0,
        .box_y = 0,
        .box_width = (2 * options.margin_box_h) + options.input_len + 1 + options.labels_max_length,
        .box_height = 7 + (2 * options.margin_box_v),
        .margin_box_v = options.margin_box_v,
        .margin_box_h = options.margin_box_h,
        .blank_cell = Cell.init(' ', options.fg, options.bg),
        .full_color = options.full_color,
        // Needed to reclaim the TTY after giving up its control
        .termios = try std.posix.tcgetattr(std.posix.STDIN_FILENO),
    };
}

pub fn setCursorStatic(x: usize, y: usize) void {
    _ = termbox.tb_set_cursor(@intCast(x), @intCast(y));
}

pub fn clearScreenStatic(clear_back_buffer: bool) !void {
    _ = termbox.tb_clear();
    if (clear_back_buffer) try clearBackBuffer();
}

pub fn shutdownStatic() void {
    _ = termbox.tb_shutdown();
}

pub fn presentBufferStatic() struct { width: usize, height: usize } {
    _ = termbox.tb_present();
    return .{
        .width = @intCast(termbox.tb_width()),
        .height = @intCast(termbox.tb_height()),
    };
}

pub fn reclaim(self: TerminalBuffer) !void {
    if (self.termios) |termios| {
        // Take back control of the TTY
        _ = termbox.tb_init();

        if (self.full_color) {
            _ = termbox.tb_set_output_mode(termbox.TB_OUTPUT_TRUECOLOR);
        }

        try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, termios);
    }
}

pub fn cascade(self: TerminalBuffer) bool {
    var changed = false;
    var y = self.height - 2;

    while (y > 0) : (y -= 1) {
        for (0..self.width) |x| {
            var cell: ?*termbox.tb_cell = undefined;
            var cell_under: ?*termbox.tb_cell = undefined;

            _ = termbox.tb_get_cell(@intCast(x), @intCast(y - 1), 1, &cell);
            _ = termbox.tb_get_cell(@intCast(x), @intCast(y), 1, &cell_under);

            // This shouldn't happen under normal circumstances, but because
            // this is a *secret* animation, there's no need to care that much
            if (cell == null or cell_under == null) continue;

            const char: u8 = @truncate(cell.?.ch);
            if (std.ascii.isWhitespace(char)) continue;

            const char_under: u8 = @truncate(cell_under.?.ch);
            if (!std.ascii.isWhitespace(char_under)) continue;

            changed = true;

            if ((self.random.int(u16) % 10) > 7) continue;

            _ = termbox.tb_set_cell(@intCast(x), @intCast(y), cell.?.ch, cell.?.fg, cell.?.bg);
            _ = termbox.tb_set_cell(@intCast(x), @intCast(y - 1), ' ', cell_under.?.fg, cell_under.?.bg);
        }
    }

    return changed;
}

pub fn drawBoxCenter(self: *TerminalBuffer, show_borders: bool, blank_box: bool) void {
    if (self.width < 2 or self.height < 2) return;
    const x1 = (self.width - @min(self.width - 2, self.box_width)) / 2;
    const y1 = (self.height - @min(self.height - 2, self.box_height)) / 2;
    const x2 = (self.width + @min(self.width, self.box_width)) / 2;
    const y2 = (self.height + @min(self.height, self.box_height)) / 2;

    self.box_x = x1;
    self.box_y = y1;

    if (show_borders) {
        _ = termbox.tb_set_cell(@intCast(x1 - 1), @intCast(y1 - 1), self.box_chars.left_up, self.border_fg, self.bg);
        _ = termbox.tb_set_cell(@intCast(x2), @intCast(y1 - 1), self.box_chars.right_up, self.border_fg, self.bg);
        _ = termbox.tb_set_cell(@intCast(x1 - 1), @intCast(y2), self.box_chars.left_down, self.border_fg, self.bg);
        _ = termbox.tb_set_cell(@intCast(x2), @intCast(y2), self.box_chars.right_down, self.border_fg, self.bg);

        var c1 = Cell.init(self.box_chars.top, self.border_fg, self.bg);
        var c2 = Cell.init(self.box_chars.bottom, self.border_fg, self.bg);

        for (0..self.box_width) |i| {
            c1.put(x1 + i, y1 - 1);
            c2.put(x1 + i, y2);
        }

        c1.ch = self.box_chars.left;
        c2.ch = self.box_chars.right;

        for (0..self.box_height) |i| {
            c1.put(x1 - 1, y1 + i);
            c2.put(x2, y1 + i);
        }
    }

    if (blank_box) {
        for (0..self.box_height) |y| {
            for (0..self.box_width) |x| {
                self.blank_cell.put(x1 + x, y1 + y);
            }
        }
    }
}

pub fn calculateComponentCoordinates(self: TerminalBuffer) struct {
    start_x: usize,
    x: usize,
    y: usize,
    full_visible_length: usize,
    visible_length: usize,
} {
    const start_x = self.box_x + self.margin_box_h;
    const x = start_x + self.labels_max_length + 1;
    const y = self.box_y + self.margin_box_v;
    const full_visible_length = self.box_x + self.box_width - self.margin_box_h - start_x;
    const visible_length = self.box_x + self.box_width - self.margin_box_h - x;

    return .{
        .start_x = start_x,
        .x = x,
        .y = y,
        .full_visible_length = full_visible_length,
        .visible_length = visible_length,
    };
}

pub fn drawLabel(self: TerminalBuffer, text: []const u8, x: usize, y: usize) void {
    drawColorLabel(text, x, y, self.fg, self.bg);
}

pub fn drawColorLabel(text: []const u8, x: usize, y: usize, fg: u32, bg: u32) void {
    const yc: c_int = @intCast(y);
    const utf8view = std.unicode.Utf8View.init(text) catch return;
    var utf8 = utf8view.iterator();

    var i: c_int = @intCast(x);
    while (utf8.nextCodepoint()) |codepoint| : (i += termbox.tb_wcwidth(codepoint)) {
        _ = termbox.tb_set_cell(i, yc, codepoint, fg, bg);
    }
}

pub fn drawConfinedLabel(self: TerminalBuffer, text: []const u8, x: usize, y: usize, max_length: usize) void {
    const yc: c_int = @intCast(y);
    const utf8view = std.unicode.Utf8View.init(text) catch return;
    var utf8 = utf8view.iterator();

    var i: c_int = @intCast(x);
    while (utf8.nextCodepoint()) |codepoint| : (i += termbox.tb_wcwidth(codepoint)) {
        if (i - @as(c_int, @intCast(x)) >= max_length) break;
        _ = termbox.tb_set_cell(i, yc, codepoint, self.fg, self.bg);
    }
}

pub fn drawCharMultiple(self: TerminalBuffer, char: u32, x: usize, y: usize, length: usize) void {
    const cell = Cell.init(char, self.fg, self.bg);
    for (0..length) |xx| cell.put(x + xx, y);
}

// Every codepoint is assumed to have a width of 1.
// Since Ly is normally running in a TTY, this should be fine.
pub fn strWidth(str: []const u8) !u8 {
    const utf8view = try std.unicode.Utf8View.init(str);
    var utf8 = utf8view.iterator();
    var i: c_int = 0;
    while (utf8.nextCodepoint()) |codepoint| i += termbox.tb_wcwidth(codepoint);

    return @intCast(i);
}

fn clearBackBuffer() !void {
    // Clear the TTY because termbox2 doesn't seem to do it properly
    const capability = termbox.global.caps[termbox.TB_CAP_CLEAR_SCREEN];
    const capability_slice = std.mem.span(capability);
    _ = try std.posix.write(termbox.global.ttyfd, capability_slice);
}
