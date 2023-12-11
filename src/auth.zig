const std = @import("std");
const enums = @import("enums.zig");
const interop = @import("interop.zig");
const TerminalBuffer = @import("tui/TerminalBuffer.zig");
const Desktop = @import("tui/components/Desktop.zig");
const Text = @import("tui/components/Text.zig");
const Allocator = std.mem.Allocator;

// TODO
pub fn authenticate(allocator: Allocator, tty: u8, buffer: TerminalBuffer, desktop: Desktop, login: Text, password: Text) !void {
    _ = buffer;

    const uid = interop.getuid();

    var tty_buffer = std.mem.zeroes([@sizeOf(u8) + 1]u8);
    var uid_buffer = std.mem.zeroes([10 + @sizeOf(u32) + 1]u8);

    const tty_str = try std.fmt.bufPrintZ(&tty_buffer, "{d}", .{tty});
    const uid_str = try std.fmt.bufPrintZ(&uid_buffer, "/run/user/{d}", .{uid});
    const current_environment = desktop.environments.items[desktop.current];

    // Add XDG environment variables
    setXdgSessionEnv(current_environment.display_server);
    try setXdgEnv(allocator, tty_str, uid_str, current_environment.xdg_name);

    // Open the PAM session
    var credentials = [_][]const u8{ login.text.items, password.text.items };
    const conv = interop.pam.pam_conv{
        .conv = loginConv,
        .appdata_ptr = @ptrCast(&credentials),
    };
    _ = conv;
}

fn setXdgSessionEnv(display_server: enums.DisplayServer) void {
    _ = interop.setenv("XDG_SESSION_TYPE", switch (display_server) {
        .wayland => "wayland",
        .shell => "tty",
        .xinitrc, .x11 => "x11",
    }, 0);
}

fn setXdgEnv(allocator: Allocator, tty_str: [:0]u8, uid_str: [:0]u8, desktop_name: []const u8) !void {
    const desktop_name_z = try allocator.dupeZ(u8, desktop_name);
    defer allocator.free(desktop_name_z);

    _ = interop.setenv("XDG_RUNTIME_DIR", uid_str, 0);
    _ = interop.setenv("XDG_SESSION_CLASS", "user", 0);
    _ = interop.setenv("XDG_SESSION_ID", "1", 0);
    _ = interop.setenv("XDG_SESSION_DESKTOP", desktop_name_z, 0);
    _ = interop.setenv("XDG_SEAT", "seat0", 0);
    _ = interop.setenv("XDG_VTNR", tty_str, 0);
}

fn loginConv(
    num_msg: c_int,
    msg: [*][*]const interop.pam.pam_message,
    resp: [*][*]const interop.pam.pam_response,
    appdata_ptr: ?*anyopaque,
) c_int {
    _ = num_msg;
    _ = msg;
    _ = resp;
    _ = appdata_ptr;
}
