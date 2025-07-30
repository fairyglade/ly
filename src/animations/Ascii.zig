const std = @import("std");
const Animation = @import("../tui/Animation.zig");
const Cell = @import("../tui/Cell.zig");
const TerminalBuffer = @import("../tui/TerminalBuffer.zig");

const Ascii = @This();

const MAX_WIDTH  = 512;
const MAX_HEIGHT = 256;

terminal_buffer: *TerminalBuffer,
ascii_art: [MAX_HEIGHT][MAX_WIDTH]u8 = undefined,
line_len: [MAX_HEIGHT]usize = undefined,
line_count: usize = undefined,
fg: u32 = undefined,
x: u32 = undefined,
y: u32 = undefined,

pub fn init(terminal_buffer: *TerminalBuffer, filename: []const u8, fg: u32, x: u32, y: u32) !Ascii {
    var ascii_art: [MAX_HEIGHT][MAX_WIDTH]u8 = undefined;
    var line_len: [MAX_HEIGHT]usize = [_]usize{0} ** MAX_HEIGHT;
    var line_count: usize = 0;

    var file = std.fs.openFileAbsolute(filename, .{}) catch {
        std.log.err("ASCII background file not found: {s}", .{filename});
        return .{
            .terminal_buffer = terminal_buffer,
            .ascii_art = undefined, // Undefined buffers here are safe, as line_count
            .line_len = undefined,  // is set to 0 so nothing will be drawn
            .line_count = 0,
            .fg = 0x00000000,
            .x = 0, .y = 0,
        };
    };
    var reader = file.reader();
    defer file.close();

    while (line_count < MAX_HEIGHT) {
        const line = reader.readUntilDelimiterOrEof(&ascii_art[line_count], '\n') catch |err| switch (err) {
            error.StreamTooLong => {
                _ = try reader.skipUntilDelimiterOrEof('\n'); // consume remainder of line
                line_len[line_count] = MAX_WIDTH;
                line_count += 1;
                continue;
            },
            else => return err,
        } orelse break;

        line_len[line_count] = line.len;
        line_count += 1;
    }

    return .{
        .terminal_buffer = terminal_buffer,
        .ascii_art = ascii_art,
        .line_len = line_len,
        .line_count = line_count,
        .fg = fg, .x = x, .y = y,
    };
}
pub fn animation(self: *Ascii) Animation {
    return Animation.init(self, deinit, realloc, draw);
}

fn deinit(_: *Ascii) void {}

fn realloc(_: *Ascii) anyerror!void {}

fn min(a: usize, b: usize) usize {
    if (a < b) return a;
    return b;
}

fn draw(self: *Ascii) void {
    const buf_width = self.terminal_buffer.width;
    const buf_height = self.terminal_buffer.height;

    var y: usize = 0;
    while (y < min(buf_height, self.line_count)) : (y += 1) {
        const line_width = self.line_len[y];
        var x: usize = 0;
        while (x < min(buf_width, line_width)) : (x += 1) {
            const cell = Cell {
                .ch = self.ascii_art[y][x],
                .fg = self.fg,
                .bg = self.terminal_buffer.bg,
            };
            cell.put(x + self.x, y + self.y);
        }
    }
}
