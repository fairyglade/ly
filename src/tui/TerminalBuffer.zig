const std = @import("std");
const builtin = @import("builtin");
const interop = @import("../interop.zig");
const Cell = @import("Cell.zig");

const Random = std.Random;

const termbox = interop.termbox;

const TerminalBuffer = @This();

pub const InitOptions = struct {
    fg: u32,
    bg: u32,
    border_fg: u32,
    margin_box_h: u8,
    margin_box_v: u8,
    input_len: u8,
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
    pub const BLACK = Styling.HI_BLACK;
    pub const RED = 0x00FF0000;
    pub const GREEN = 0x0000FF00;
    pub const YELLOW = 0x00FFFF00;
    pub const BLUE = 0x000000FF;
    pub const MAGENTA = 0x00FF00FF;
    pub const CYAN = 0x0000FFFF;
    pub const WHITE = 0x00FFFFFF;
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

pub fn init(options: InitOptions, labels_max_length: usize, random: Random) TerminalBuffer {
    return .{
        .random = random,
        .width = @intCast(termbox.tb_width()),
        .height = @intCast(termbox.tb_height()),
        .fg = options.fg,
        .bg = options.bg,
        .border_fg = options.border_fg,
        .box_chars = if (builtin.os.tag == .linux or builtin.os.tag.isBSD()) .{
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
        .labels_max_length = labels_max_length,
        .box_x = 0,
        .box_y = 0,
        .box_width = (2 * options.margin_box_h) + options.input_len + 1 + labels_max_length,
        .box_height = 7 + (2 * options.margin_box_v),
        .margin_box_v = options.margin_box_v,
        .margin_box_h = options.margin_box_h,
        .blank_cell = Cell.init(' ', options.fg, options.bg),
    };
}

pub fn cascade(self: TerminalBuffer) bool {
    var changed = false;
    var y = self.height - 2;

    while (y > 0) : (y -= 1) {
        for (0..self.width) |x| {
            var cell: termbox.tb_cell = undefined;
            var cell_under: termbox.tb_cell = undefined;

            _ = termbox.tb_get_cell(@intCast(x), @intCast(y - 1), 1, &cell);
            _ = termbox.tb_get_cell(@intCast(x), @intCast(y), 1, &cell_under);

            const char: u8 = @truncate(cell.ch);
            if (std.ascii.isWhitespace(char)) continue;

            const char_under: u8 = @truncate(cell_under.ch);
            if (!std.ascii.isWhitespace(char_under)) continue;

            changed = true;

            if ((self.random.int(u16) % 10) > 7) continue;

            _ = termbox.tb_set_cell(@intCast(x), @intCast(y), cell.ch, cell.fg, cell.bg);
            _ = termbox.tb_set_cell(@intCast(x), @intCast(y - 1), ' ', cell_under.fg, cell_under.bg);
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

    var i = x;
    while (utf8.nextCodepoint()) |codepoint| : (i += 1) {
        _ = termbox.tb_set_cell(@intCast(i), yc, codepoint, fg, bg);
    }
}

pub fn drawConfinedLabel(self: TerminalBuffer, text: []const u8, x: usize, y: usize, max_length: usize) void {
    const yc: c_int = @intCast(y);
    const utf8view = std.unicode.Utf8View.init(text) catch return;
    var utf8 = utf8view.iterator();

    var i: usize = 0;
    while (utf8.nextCodepoint()) |codepoint| : (i += 1) {
        if (i >= max_length) break;
        _ = termbox.tb_set_cell(@intCast(i + x), yc, codepoint, self.fg, self.bg);
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
    var i: u8 = 0;
    while (utf8.nextCodepoint()) |_| i += 1;
    return i;
}
