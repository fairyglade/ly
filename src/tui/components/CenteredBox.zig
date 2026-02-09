const std = @import("std");

const Cell = @import("../Cell.zig");
const Position = @import("../Position.zig");
const TerminalBuffer = @import("../TerminalBuffer.zig");
const Widget = @import("../Widget.zig");

const CenteredBox = @This();

buffer: *TerminalBuffer,
horizontal_margin: usize,
vertical_margin: usize,
width: usize,
height: usize,
show_borders: bool,
blank_box: bool,
top_title: ?[]const u8,
bottom_title: ?[]const u8,
border_fg: u32,
title_fg: u32,
bg: u32,
left_pos: Position,
right_pos: Position,
children_pos: Position,

pub fn init(
    buffer: *TerminalBuffer,
    horizontal_margin: usize,
    vertical_margin: usize,
    width: usize,
    height: usize,
    show_borders: bool,
    blank_box: bool,
    top_title: ?[]const u8,
    bottom_title: ?[]const u8,
    border_fg: u32,
    title_fg: u32,
    bg: u32,
) CenteredBox {
    return .{
        .buffer = buffer,
        .horizontal_margin = horizontal_margin,
        .vertical_margin = vertical_margin,
        .width = width,
        .height = height,
        .show_borders = show_borders,
        .blank_box = blank_box,
        .top_title = top_title,
        .bottom_title = bottom_title,
        .border_fg = border_fg,
        .title_fg = title_fg,
        .bg = bg,
        .left_pos = TerminalBuffer.START_POSITION,
        .right_pos = TerminalBuffer.START_POSITION,
        .children_pos = TerminalBuffer.START_POSITION,
    };
}

pub fn widget(self: *CenteredBox) Widget {
    return Widget.init(
        self,
        null,
        null,
        draw,
        null,
        null,
    );
}

pub fn positionXY(self: *CenteredBox, original_pos: Position) void {
    if (self.buffer.width < 2 or self.buffer.height < 2) return;

    self.left_pos = Position.init(
        (self.buffer.width - @min(self.buffer.width - 2, self.width)) / 2,
        (self.buffer.height - @min(self.buffer.height - 2, self.height)) / 2,
    ).add(original_pos);

    self.right_pos = Position.init(
        (self.buffer.width + @min(self.buffer.width, self.width)) / 2,
        (self.buffer.height + @min(self.buffer.height, self.height)) / 2,
    ).add(original_pos);

    self.children_pos = Position.init(
        self.left_pos.x + self.horizontal_margin,
        self.left_pos.y + self.vertical_margin,
    ).add(original_pos);
}

pub fn childrenPosition(self: CenteredBox) Position {
    return self.children_pos;
}

pub fn draw(self: *CenteredBox) void {
    if (self.show_borders) {
        var left_up = Cell.init(
            self.buffer.box_chars.left_up,
            self.border_fg,
            self.bg,
        );
        var right_up = Cell.init(
            self.buffer.box_chars.right_up,
            self.border_fg,
            self.bg,
        );
        var left_down = Cell.init(
            self.buffer.box_chars.left_down,
            self.border_fg,
            self.bg,
        );
        var right_down = Cell.init(
            self.buffer.box_chars.right_down,
            self.border_fg,
            self.bg,
        );
        var top = Cell.init(
            self.buffer.box_chars.top,
            self.border_fg,
            self.bg,
        );
        var bottom = Cell.init(
            self.buffer.box_chars.bottom,
            self.border_fg,
            self.bg,
        );

        left_up.put(self.left_pos.x - 1, self.left_pos.y - 1);
        right_up.put(self.right_pos.x, self.left_pos.y - 1);
        left_down.put(self.left_pos.x - 1, self.right_pos.y);
        right_down.put(self.right_pos.x, self.right_pos.y);

        for (0..self.width) |i| {
            top.put(self.left_pos.x + i, self.left_pos.y - 1);
            bottom.put(self.left_pos.x + i, self.right_pos.y);
        }

        top.ch = self.buffer.box_chars.left;
        bottom.ch = self.buffer.box_chars.right;

        for (0..self.height) |i| {
            top.put(self.left_pos.x - 1, self.left_pos.y + i);
            bottom.put(self.right_pos.x, self.left_pos.y + i);
        }
    }

    if (self.blank_box) {
        for (0..self.height) |y| {
            for (0..self.width) |x| {
                self.buffer.blank_cell.put(self.left_pos.x + x, self.left_pos.y + y);
            }
        }
    }

    if (self.top_title) |title| {
        TerminalBuffer.drawConfinedText(
            title,
            self.left_pos.x,
            self.left_pos.y - 1,
            self.width,
            self.title_fg,
            self.bg,
        );
    }

    if (self.bottom_title) |title| {
        TerminalBuffer.drawConfinedText(
            title,
            self.left_pos.x,
            self.left_pos.y + self.height,
            self.width,
            self.title_fg,
            self.bg,
        );
    }
}
