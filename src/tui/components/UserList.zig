const std = @import("std");
const TerminalBuffer = @import("../TerminalBuffer.zig");
const generic = @import("generic.zig");

const StringList = std.ArrayListUnmanaged([]const u8);
const Allocator = std.mem.Allocator;

const UsernameText = generic.CyclableLabel([]const u8);

const UserList = @This();

label: UsernameText,

pub fn init(allocator: Allocator, buffer: *TerminalBuffer, usernames: StringList) !UserList {
    var userList = UserList{
        .label = UsernameText.init(allocator, buffer, drawItem),
    };

    for (usernames.items) |username| {
        if (username.len == 0) continue;

        try userList.label.addItem(username);
    }

    return userList;
}

pub fn deinit(self: *UserList) void {
    self.label.deinit();
}

pub fn getCurrentUser(self: UserList) []const u8 {
    return self.label.list.items[self.label.current];
}

fn drawItem(label: *UsernameText, username: []const u8, _: usize, _: usize) bool {
    const length = @min(username.len, label.visible_length - 3);
    if (length == 0) return false;

    const x = if (label.text_in_center) (label.x + (label.visible_length - username.len) / 2) else (label.x + 2);
    label.first_char_x = x + username.len;

    label.buffer.drawLabel(username, x, label.y);
    return true;
}
