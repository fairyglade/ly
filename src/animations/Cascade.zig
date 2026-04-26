const std = @import("std");
const math = std.math;

const ly_ui = @import("ly-ui");
const Cell = ly_ui.Cell;
const TerminalBuffer = ly_ui.TerminalBuffer;
const Widget = ly_ui.Widget;

const Cascade = @This();

io: std.Io,
instance: ?Widget = null,
buffer: *TerminalBuffer,
current_auth_fails: *u64,
max_auth_fails: u64,

pub fn init(
    io: std.Io,
    buffer: *TerminalBuffer,
    current_auth_fails: *u64,
    max_auth_fails: u64,
) Cascade {
    return .{
        .io = io,
        .instance = null,
        .buffer = buffer,
        .current_auth_fails = current_auth_fails,
        .max_auth_fails = max_auth_fails,
    };
}

pub fn widget(self: *Cascade) *Widget {
    if (self.instance) |*instance| return instance;
    self.instance = Widget.init(
        "Cascade",
        null,
        self,
        null,
        null,
        draw,
        null,
        null,
        null,
    );
    return &self.instance.?;
}

fn draw(self: *Cascade) void {
    while (self.current_auth_fails.* >= self.max_auth_fails) {
        self.io.sleep(.fromMilliseconds(10), .real) catch {};

        var changed = false;
        var y = self.buffer.height - 2;

        while (y > 0) : (y -= 1) {
            for (0..self.buffer.width) |x| {
                const cell = TerminalBuffer.getCell(x, y - 1);
                const cell_under = TerminalBuffer.getCell(x, y);

                // This shouldn't happen under normal circumstances, but because
                // this is a *secret* animation, there's no need to care that much
                if (cell == null or cell_under == null) continue;

                const char: u8 = @truncate(cell.?.ch);
                if (std.ascii.isWhitespace(char)) continue;

                const char_under: u8 = @truncate(cell_under.?.ch);
                if (!std.ascii.isWhitespace(char_under)) continue;

                changed = true;

                if ((self.buffer.random.int(u16) % 10) > 7) continue;

                cell.?.put(x, y);

                var space = Cell.init(
                    ' ',
                    cell_under.?.fg,
                    cell_under.?.bg,
                );
                space.put(x, y - 1);
            }
        }

        if (!changed) {
            self.io.sleep(.fromSeconds(7), .real) catch {};
            self.current_auth_fails.* = 0;
        }

        TerminalBuffer.presentBuffer();
    }
}
