const std = @import("std");

const SavedUsers = @This();

const User = struct {
    username: []const u8,
    session_index: usize,
};

user_list: std.ArrayList(User),
last_username_index: ?usize,

pub fn init() SavedUsers {
    return .{
        .user_list = .empty,
        .last_username_index = null,
    };
}

pub fn deinit(self: *SavedUsers, allocator: std.mem.Allocator) void {
    self.user_list.deinit(allocator);
}
