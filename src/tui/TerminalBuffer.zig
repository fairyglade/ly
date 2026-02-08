const std = @import("std");
const Random = std.Random;

const ly_core = @import("ly-core");
const interop = ly_core.interop;
const LogFile = ly_core.LogFile;
pub const termbox = @import("termbox2");

const Cell = @import("Cell.zig");
const Position = @import("Position.zig");

const TerminalBuffer = @This();

pub const InitOptions = struct {
    fg: u32,
    bg: u32,
    border_fg: u32,
    full_color: bool,
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

pub const START_POSITION = Position.init(0, 0);

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
