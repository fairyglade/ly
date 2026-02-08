const std = @import("std");
const Allocator = std.mem.Allocator;

const SavedUsers = @import("../../config/SavedUsers.zig");
const TerminalBuffer = @import("../TerminalBuffer.zig");
const generic = @import("generic.zig");
const Session = @import("Session.zig");

const StringList = std.ArrayListUnmanaged([]const u8);
pub const User = struct {
    name: []const u8,
    session_index: *usize,
    allocated_index: bool,
    first_run: bool,
};
const UserLabel = generic.CyclableLabel(User, *Session);

const UserList = @This();

label: UserLabel,

pub fn init(
    allocator: Allocator,
    buffer: *TerminalBuffer,
    usernames: StringList,
    saved_users: *SavedUsers,
    session: *Session,
    width: usize,
    text_in_center: bool,
) !UserList {
    var userList = UserList{
        .label = UserLabel.init(
            allocator,
            buffer,
            drawItem,
            usernameChanged,
            session,
            width,
            text_in_center,
        ),
    };

    for (usernames.items) |username| {
        if (username.len == 0) continue;

        var maybe_session_index: ?*usize = null;
        var first_run = true;
        for (saved_users.user_list.items) |*saved_user| {
            if (std.mem.eql(u8, username, saved_user.username)) {
                maybe_session_index = &saved_user.session_index;
                first_run = saved_user.first_run;
                break;
            }
        }

        var allocated_index = false;
        if (maybe_session_index == null) {
            maybe_session_index = try allocator.create(usize);
            maybe_session_index.?.* = 0;
            allocated_index = true;
        }

        try userList.label.addItem(.{
            .name = username,
            .session_index = maybe_session_index.?,
            .allocated_index = allocated_index,
            .first_run = first_run,
        });
    }

    return userList;
}

pub fn deinit(self: *UserList) void {
    for (self.label.list.items) |user| {
        if (user.allocated_index) {
            self.label.allocator.destroy(user.session_index);
        }
    }

    self.label.deinit();
}

pub fn getCurrentUsername(self: UserList) []const u8 {
    return self.label.list.items[self.label.current].name;
}

fn usernameChanged(user: User, maybe_session: ?*Session) void {
    if (maybe_session) |session| {
        session.label.current = @min(user.session_index.*, session.label.list.items.len - 1);
    }
}

fn drawItem(label: *UserLabel, user: User, x: usize, y: usize, width: usize) void {
    const length = @min(user.name.len, width - 3);
    if (length == 0) return;

    const x_offset = if (label.text_in_center) (width - length) / 2 else 0;

    label.item_width = length + x_offset;
    label.buffer.drawLabel(user.name, x + x_offset, y);
}
