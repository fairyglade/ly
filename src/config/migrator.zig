const std = @import("std");
const ini = @import("zigini");
const Save = @import("Save.zig");

const Allocator = std.mem.Allocator;

pub fn tryMigrateSaveFile(allocator: Allocator, path: []const u8) Save {
    var file = std.fs.openFileAbsolute(path, .{ .mode = .read_write }) catch return .{};
    defer file.close();

    const reader = file.reader();
    const user_length = reader.readIntLittle(u64) catch return .{};

    const user_buffer = allocator.alloc(u8, user_length) catch return .{};
    defer allocator.free(user_buffer);

    const read_user_length = reader.read(user_buffer) catch return .{};
    if (read_user_length != user_length) return .{};

    const session_index = reader.readIntLittle(u64) catch return .{};

    const save = .{
        .user = user_buffer,
        .session_index = session_index,
    };

    ini.writeFromStruct(save, file.writer(), null) catch return save;

    return save;
}
