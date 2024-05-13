const std = @import("std");
const builtin = @import("builtin");
const interop = @import("../interop.zig");
const utils = @import("utils.zig");
const Config = @import("../config/Config.zig");

const Random = std.rand.Random;

const termbox = interop.termbox;

const TerminalBuffer = @This();

random: Random,
width: u64,
height: u64,
buffer: [*]termbox.tb_cell,
fg: u8,
bg: u8,
border_fg: u8,
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
labels_max_length: u64,
box_x: u64,
box_y: u64,
box_width: u64,
box_height: u64,
margin_box_v: u8,
margin_box_h: u8,

pub fn init(config: Config, labels_max_length: u64) TerminalBuffer {
    var prng = std.rand.Isaac64.init(@intCast(std.time.timestamp()));

    return .{
        .random = prng.random(),
        .width = @intCast(termbox.tb_width()),
        .height = @intCast(termbox.tb_height()),
        .buffer = termbox.tb_cell_buffer(),
        .fg = config.fg,
        .bg = config.bg,
        .border_fg = config.border_fg,
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
        .box_width = (2 * config.margin_box_h) + config.input_len + 1 + labels_max_length,
        .box_height = 7 + (2 * config.margin_box_v),
        .margin_box_v = config.margin_box_v,
        .margin_box_h = config.margin_box_h,
    };
}

pub fn cascade(self: TerminalBuffer) bool {
    var changes = false;

    var y = self.height - 2;
    while (y > 0) : (y -= 1) {
        for (0..self.width) |x| {
            const c: u8 = @truncate(self.buffer[(y - 1) * self.width + x].ch);
            if (std.ascii.isWhitespace(c)) continue;

            const c_under: u8 = @truncate(self.buffer[y * self.width + x].ch);
            if (!std.ascii.isWhitespace(c_under)) continue;

            changes = true;

            if ((self.random.int(u16) % 10) > 7) continue;

            self.buffer[y * self.width + x] = self.buffer[(y - 1) * self.width + x];
            self.buffer[(y - 1) * self.width + x].ch = ' ';
        }
    }

    return changes;
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
        termbox.tb_change_cell(@intCast(x1 - 1), @intCast(y1 - 1), self.box_chars.left_up, self.border_fg, self.bg);
        termbox.tb_change_cell(@intCast(x2), @intCast(y1 - 1), self.box_chars.right_up, self.border_fg, self.bg);
        termbox.tb_change_cell(@intCast(x1 - 1), @intCast(y2), self.box_chars.left_down, self.border_fg, self.bg);
        termbox.tb_change_cell(@intCast(x2), @intCast(y2), self.box_chars.right_down, self.border_fg, self.bg);

        var c1 = utils.initCell(self.box_chars.top, self.border_fg, self.bg);
        var c2 = utils.initCell(self.box_chars.bottom, self.border_fg, self.bg);

        for (0..self.box_width) |i| {
            termbox.tb_put_cell(@intCast(x1 + i), @intCast(y1 - 1), &c1);
            termbox.tb_put_cell(@intCast(x1 + i), @intCast(y2), &c2);
        }

        c1.ch = self.box_chars.left;
        c2.ch = self.box_chars.right;

        for (0..self.box_height) |i| {
            termbox.tb_put_cell(@intCast(x1 - 1), @intCast(y1 + i), &c1);
            termbox.tb_put_cell(@intCast(x2), @intCast(y1 + i), &c2);
        }
    }

    if (blank_box) {
        const blank = utils.initCell(' ', self.fg, self.bg);

        for (0..self.box_height) |y| {
            for (0..self.box_width) |x| {
                termbox.tb_put_cell(@intCast(x1 + x), @intCast(y1 + y), &blank);
            }
        }
    }
}

pub fn calculateComponentCoordinates(self: TerminalBuffer) struct {
    x: u64,
    y: u64,
    visible_length: u64,
} {
    const x = self.box_x + self.margin_box_h + self.labels_max_length + 1;
    const y = self.box_y + self.margin_box_v;
    const visible_length = self.box_x + self.box_width - self.margin_box_h - x;

    return .{
        .x = x,
        .y = y,
        .visible_length = visible_length,
    };
}

pub fn drawLabel(self: TerminalBuffer, text: []const u8, x: u64, y: u64) void {
    const yc: c_int = @intCast(y);
    const utf8view = std.unicode.Utf8View.init(text) catch return;
    var utf8 = utf8view.iterator();

    var i = x;
    while (utf8.nextCodepoint()) |codepoint| : (i += 1) {
        termbox.tb_change_cell(@intCast(i), yc, codepoint, self.fg, self.bg);
    }
}

pub fn drawConfinedLabel(self: TerminalBuffer, text: []const u8, x: u64, y: u64, max_length: u64) void {
    var confined_text = text;
    if (text.len > max_length) confined_text = text[0..max_length];

    const yc: c_int = @intCast(y);
    const utf8view = std.unicode.Utf8View.init(confined_text) catch return;
    var utf8 = utf8view.iterator();

    var i = x;
    while (utf8.nextCodepoint()) |codepoint| : (i += 1) {
        termbox.tb_change_cell(@intCast(i), yc, codepoint, self.fg, self.bg);
    }
}

pub fn drawCharMultiple(self: TerminalBuffer, char: u8, x: u64, y: u64, length: u64) void {
    const yc: c_int = @intCast(y);
    const cell = utils.initCell(char, self.fg, self.bg);

    for (0..length) |xx| termbox.tb_put_cell(@intCast(x + xx), yc, &cell);
}
