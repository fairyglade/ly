const std = @import("std");

pub const allocator = std.heap.raw_c_allocator;

pub fn c_str(str: []const u8) ![:0]u8 {
    const new_str = try allocator.allocSentinel(u8, str.len, 0);

    for (str, 0..) |c, i| {
        new_str[i] = c;
    }

    return new_str;
}
