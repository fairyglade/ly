const std = @import("std");
pub const Animation = enum {
    none,
    doom,
    matrix,
    colormix,
    gameoflife,
    dur_file,
};

pub const DisplayServer = enum {
    wayland,
    shell,
    xinitrc,
    x11,
    custom,
};

pub const Input = enum {
    info_line,
    session,
    login,
    password,

    /// Moves the current Input forwards by one entry. If `reverse`, then the Input
    /// moves backwards. If `wrap` is true, then the entry will wrap back around
    pub fn move(self: *Input, reverse: bool, wrap: bool) void {
        const maxNum = @typeInfo(Input).@"enum".fields.len - 1;
        const selfNum = @intFromEnum(self.*);
        if (reverse) {
            if (wrap) {
                self.* = @enumFromInt(selfNum -% 1);
            } else if (selfNum != 0) {
                self.* = @enumFromInt(selfNum - 1);
            }
        } else {
            if (wrap) {
                self.* = @enumFromInt(selfNum +% 1);
            } else if (selfNum != maxNum) {
                self.* = @enumFromInt(selfNum + 1);
            }
        }
    }
};

pub const ViMode = enum {
    normal,
    insert,
};

pub const Bigclock = enum {
    none,
    en,
    fa,
};
