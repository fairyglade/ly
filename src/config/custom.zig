const std = @import("std");

const custom = @This();

pub const CustomCommandBind = struct {
    name: []const u8 = "",
    cmd: []const u8 = "",
};

pub const UNDEFINED_CMD: []const u8 = "echo \"You forgot to define 'cmd'!\"";

pub const CustomCommandInfo = struct {
    name: []const u8 = "",
    cmd: ?[]const u8 = null,
    /// To be set to the label's widget ID
    id: u64 = 0,

    /// In frames, the refresh rate for the `cmd` to run again
    /// If 0, only run once.
    refresh: u32 = 0,
    counter: u32 = 0,
};

pub var binds: std.StringHashMap(CustomCommandBind) = undefined;
pub var labels: std.StringHashMap(CustomCommandInfo) = undefined;
