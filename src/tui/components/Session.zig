const std = @import("std");
const TerminalBuffer = @import("../TerminalBuffer.zig");
const enums = @import("../../enums.zig");
const Environment = @import("../../Environment.zig");
const generic = @import("generic.zig");
const UserList = @import("UserList.zig");

const Allocator = std.mem.Allocator;
const DisplayServer = enums.DisplayServer;

const Env = struct {
    environment: Environment,
    index: usize,
};
const EnvironmentLabel = generic.CyclableLabel(Env, *UserList);

const Session = @This();

label: EnvironmentLabel,
user_list: *UserList,

pub fn init(allocator: Allocator, buffer: *TerminalBuffer, user_list: *UserList) Session {
    return .{
        .label = EnvironmentLabel.init(allocator, buffer, drawItem, sessionChanged, user_list),
        .user_list = user_list,
    };
}

pub fn deinit(self: *Session) void {
    for (self.label.list.items) |*env| {
        if (env.environment.entry_ini) |*entry_ini| entry_ini.deinit();
        self.label.allocator.free(env.environment.file_name);
    }

    self.label.deinit();
}

pub fn addEnvironment(self: *Session, environment: Environment) !void {
    const env = Env{ .environment = environment, .index = self.label.list.items.len };

    try self.label.addItem(env);
    addedSession(env, self.user_list);
}

fn addedSession(env: Env, user_list: *UserList) void {
    const user = user_list.label.list.items[user_list.label.current];
    if (!user.first_run) return;

    user.session_index.* = env.index;
}

fn sessionChanged(env: Env, maybe_user_list: ?*UserList) void {
    if (maybe_user_list) |user_list| {
        user_list.label.list.items[user_list.label.current].session_index.* = env.index;
    }
}

fn drawItem(label: *EnvironmentLabel, env: Env, x: usize, y: usize) bool {
    const length = @min(env.environment.name.len, label.visible_length - 3);
    if (length == 0) return false;

    const nx = if (label.text_in_center) (label.x + (label.visible_length - env.environment.name.len) / 2) else (label.x + 2);
    label.first_char_x = nx + env.environment.name.len;

    label.buffer.drawLabel(env.environment.specifier, x, y);
    label.buffer.drawLabel(env.environment.name, nx, label.y);
    return true;
}
