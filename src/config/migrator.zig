const std = @import("std");
const ini = @import("zigini");
const Save = @import("Save.zig");

pub fn tryMigrateSaveFile(user_buf: *[32]u8, path: []const u8) Save {
    var save = Save{};

    var file = std.fs.openFileAbsolute(path, .{}) catch return save;
    defer file.close();

    const reader = file.reader();

    var user_fbs = std.io.fixedBufferStream(user_buf);
    reader.streamUntilDelimiter(user_fbs.writer(), '\n', 32) catch return save;
    const user = user_fbs.getWritten();
    if (user.len > 0) save.user = user;

    var session_buf: [20]u8 = undefined;
    var session_fbs = std.io.fixedBufferStream(&session_buf);
    reader.streamUntilDelimiter(session_fbs.writer(), '\n', 20) catch {};

    const session_index_str = session_fbs.getWritten();
    var session_index: ?usize = null;
    if (session_index_str.len > 0) {
        session_index = std.fmt.parseUnsigned(usize, session_index_str, 10) catch return save;
    }
    save.session_index = session_index;

    return save;
}
