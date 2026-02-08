const std = @import("std");
const Allocator = std.mem.Allocator;

const enums = @import("../../enums.zig");
const DisplayServer = enums.DisplayServer;
const Environment = @import("../../Environment.zig");
const TerminalBuffer = @import("../TerminalBuffer.zig");
const generic = @import("generic.zig");
const UserList = @import("UserList.zig");

const Env = struct {
    environment: Environment,
    index: usize,
};
const EnvironmentLabel = generic.CyclableLabel(Env, *UserList);

const Session = @This();

label: EnvironmentLabel,
user_list: *UserList,

pub fn init(
    allocator: Allocator,
    buffer: *TerminalBuffer,
    user_list: *UserList,
    width: usize,
    text_in_center: bool,
    fg: u32,
    bg: u32,
) Session {
    return .{
        .label = EnvironmentLabel.init(
            allocator,
            buffer,
            drawItem,
            sessionChanged,
            user_list,
            width,
            text_in_center,
            fg,
            bg,
        ),
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

fn drawItem(label: *EnvironmentLabel, env: Env, x: usize, y: usize, width: usize) void {
    if (width < 3) return;

    const length = @min(env.environment.name.len, width - 3);
    if (length == 0) return;

    const x_offset = if (label.text_in_center and width >= length) (width - length) / 2 else 0;

    label.cursor = length + x_offset;
    TerminalBuffer.drawConfinedText(
        env.environment.name,
        x + x_offset,
        y,
        width,
        label.fg,
        label.bg,
    );
}
