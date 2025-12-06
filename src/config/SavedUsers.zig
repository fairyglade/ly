const std = @import("std");

const SavedUsers = @This();

const User = struct {
    username: []const u8,
    session_index: usize,
    first_run: bool,
    allocated_username: bool,
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
    for (self.user_list.items) |user| {
        if (user.allocated_username) allocator.free(user.username);
    }

    self.user_list.deinit(allocator);
}
