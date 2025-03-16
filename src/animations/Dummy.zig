const std = @import("std");
const Animation = @import("../tui/Animation.zig");

const Dummy = @This();

pub fn animation(self: *Dummy) Animation {
    return Animation.init(self, deinit, realloc, draw);
}

fn deinit(_: *Dummy) void {}

fn realloc(_: *Dummy) anyerror!void {}

fn draw(_: *Dummy) void {}
