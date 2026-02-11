const std = @import("std");
const math = std.math;

const Cell = @import("../tui/Cell.zig");
const TerminalBuffer = @import("../tui/TerminalBuffer.zig");
const Widget = @import("../tui/Widget.zig");

const Cascade = @This();

buffer: *TerminalBuffer,
current_auth_fails: *usize,
max_auth_fails: usize,

pub fn init(
    buffer: *TerminalBuffer,
    current_auth_fails: *usize,
    max_auth_fails: usize,
) Cascade {
    return .{
        .buffer = buffer,
        .current_auth_fails = current_auth_fails,
        .max_auth_fails = max_auth_fails,
    };
}

pub fn widget(self: *Cascade) Widget {
    return Widget.init(
        "Cascade",
        self,
        null,
        null,
        draw,
        null,
        null,
        null,
    );
}

fn draw(self: *Cascade) void {
    while (self.current_auth_fails.* >= self.max_auth_fails) {
        std.Thread.sleep(std.time.ns_per_ms * 10);

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
            std.Thread.sleep(std.time.ns_per_s * 7);
            self.current_auth_fails.* = 0;
        }

        TerminalBuffer.presentBuffer();
    }
}
