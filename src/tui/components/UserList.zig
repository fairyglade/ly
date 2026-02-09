const std = @import("std");
const Allocator = std.mem.Allocator;

const SavedUsers = @import("../../config/SavedUsers.zig");
const keyboard = @import("../keyboard.zig");
const TerminalBuffer = @import("../TerminalBuffer.zig");
const Widget = @import("../Widget.zig");
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
    fg: u32,
    bg: u32,
) !UserList {
    var user_list = UserList{
        .label = UserLabel.init(
            allocator,
            buffer,
            drawItem,
            usernameChanged,
            session,
            width,
            text_in_center,
            fg,
            bg,
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

        try user_list.label.addItem(.{
            .name = username,
            .session_index = maybe_session_index.?,
            .allocated_index = allocated_index,
            .first_run = first_run,
        });
    }

    return user_list;
}

pub fn deinit(self: *UserList) void {
    for (self.label.list.items) |user| {
        if (user.allocated_index) {
            self.label.allocator.destroy(user.session_index);
        }
    }

    self.label.deinit();
}

pub fn widget(self: *UserList) Widget {
    return Widget.init(
        self,
        deinit,
        null,
        draw,
        null,
        handle,
    );
}

pub fn getCurrentUsername(self: UserList) []const u8 {
    return self.label.list.items[self.label.current].name;
}

fn draw(self: *UserList) void {
    self.label.draw();
}

fn handle(self: *UserList, maybe_key: ?keyboard.Key, insert_mode: bool) !void {
    self.label.handle(maybe_key, insert_mode);
}

fn usernameChanged(user: User, maybe_session: ?*Session) void {
    if (maybe_session) |session| {
        session.label.current = @min(user.session_index.*, session.label.list.items.len - 1);
    }
}

fn drawItem(label: *UserLabel, user: User, x: usize, y: usize, width: usize) void {
    if (width < 3) return;

    const length = @min(TerminalBuffer.strWidth(user.name), width - 3);
    if (length == 0) return;

    const x_offset = if (label.text_in_center and width >= length) (width - length) / 2 else 0;

    label.cursor = length + x_offset;
    TerminalBuffer.drawConfinedText(
        user.name,
        x + x_offset,
        y,
        width,
        label.fg,
        label.bg,
    );
}
