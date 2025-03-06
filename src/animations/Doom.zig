const std = @import("std");
const Allocator = std.mem.Allocator;
const TerminalBuffer = @import("../tui/TerminalBuffer.zig");
const utils = @import("../tui/utils.zig");

const Doom = @This();

pub const STEPS = 12;

allocator: Allocator,
terminal_buffer: *TerminalBuffer,
buffer: []u8,
fire: [STEPS + 1]utils.Cell,

pub fn init(allocator: Allocator, terminal_buffer: *TerminalBuffer, top_color: u32, middle_color: u32, bottom_color: u32) !Doom {
    const buffer = try allocator.alloc(u8, terminal_buffer.width * terminal_buffer.height);
    initBuffer(buffer, terminal_buffer.width);

    return .{
        .allocator = allocator,
        .terminal_buffer = terminal_buffer,
        .buffer = buffer,
        .fire = [_]utils.Cell{
            utils.initCell(' ', 0x00000000, 0),
            utils.initCell(0x2591, top_color, 0),
            utils.initCell(0x2592, top_color, 0),
            utils.initCell(0x2593, top_color, 0),
            utils.initCell(0x2588, top_color, 0),
            utils.initCell(0x2591, middle_color, 2),
            utils.initCell(0x2592, middle_color, 2),
            utils.initCell(0x2593, middle_color, 2),
            utils.initCell(0x2588, middle_color, 2),
            utils.initCell(0x2591, bottom_color, 4),
            utils.initCell(0x2592, bottom_color, 4),
            utils.initCell(0x2593, bottom_color, 4),
            utils.initCell(0x2588, bottom_color, 4),
        },
    };
}

pub fn deinit(self: Doom) void {
    self.allocator.free(self.buffer);
}

pub fn realloc(self: *Doom) !void {
    const buffer = try self.allocator.realloc(self.buffer, self.terminal_buffer.width * self.terminal_buffer.height);
    initBuffer(buffer, self.terminal_buffer.width);
    self.buffer = buffer;
}

pub fn draw(self: Doom) void {
    for (0..self.terminal_buffer.width) |x| {
        for (1..self.terminal_buffer.height) |y| {
            const source = y * self.terminal_buffer.width + x;
            const random = (self.terminal_buffer.random.int(u16) % 7) & 3;

            var dest = (source - @min(source, random)) + 1;
            if (self.terminal_buffer.width > dest) dest = 0 else dest -= self.terminal_buffer.width;

            const buffer_source = self.buffer[source];
            const buffer_dest_offset = random & 1;

            if (buffer_source < buffer_dest_offset) continue;

            var buffer_dest = buffer_source - buffer_dest_offset;
            if (buffer_dest > STEPS) buffer_dest = 0;
            self.buffer[dest] = @intCast(buffer_dest);

            const dest_y = dest / self.terminal_buffer.width;
            const dest_x = dest % self.terminal_buffer.width;
            utils.putCell(dest_x, dest_y, self.fire[buffer_dest]);

            const source_y = source / self.terminal_buffer.width;
            const source_x = source % self.terminal_buffer.width;
            utils.putCell(source_x, source_y, self.fire[buffer_source]);
        }
    }
}

fn initBuffer(buffer: []u8, width: usize) void {
    const length = buffer.len - width;
    const slice_start = buffer[0..length];
    const slice_end = buffer[length..];

    @memset(slice_start, 0);
    @memset(slice_end, STEPS);
}
