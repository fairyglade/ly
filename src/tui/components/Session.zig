const std = @import("std");
const TerminalBuffer = @import("../TerminalBuffer.zig");
const enums = @import("../../enums.zig");
const ini = @import("zigini");
const Environment = @import("../../Environment.zig");
const generic = @import("generic.zig");

const Allocator = std.mem.Allocator;
const DisplayServer = enums.DisplayServer;
const Ini = ini.Ini;
const EnvironmentLabel = generic.CyclableLabel(Environment);

const Session = @This();

label: EnvironmentLabel,

pub fn init(allocator: Allocator, buffer: *TerminalBuffer) Session {
    return .{
        .label = EnvironmentLabel.init(allocator, buffer, drawItem),
    };
}

pub fn deinit(self: *Session) void {
    for (self.label.list.items) |*environment| {
        if (environment.entry_ini) |*entry_ini| entry_ini.deinit();
        if (environment.xdg_session_desktop) |session_desktop| self.label.allocator.free(session_desktop);
    }

    self.label.deinit();
}

pub fn addEnvironment(self: *Session, environment: Environment) !void {
    try self.label.addItem(environment);
}

fn drawItem(label: *EnvironmentLabel, environment: Environment, x: usize, y: usize) bool {
    const length = @min(environment.name.len, label.visible_length - 3);
    if (length == 0) return false;

    const nx = if (label.text_in_center) (label.x + (label.visible_length - environment.name.len) / 2) else (label.x + 2);
    label.first_char_x = nx + environment.name.len;

    label.buffer.drawLabel(environment.specifier, x, y);
    label.buffer.drawLabel(environment.name, nx, label.y);
    return true;
}
