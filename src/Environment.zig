const enums = @import("enums.zig");
const ini = @import("zigini");

const DisplayServer = enums.DisplayServer;
const Ini = ini.Ini;

pub const DesktopEntry = struct {
    Exec: []const u8 = "",
    Name: [:0]const u8 = "",
    DesktopNames: ?[:0]u8 = null,
};

pub const Entry = struct { @"Desktop Entry": DesktopEntry = .{} };

entry_ini: ?Ini(Entry) = null,
name: [:0]const u8 = "",
xdg_session_desktop: ?[:0]const u8 = null,
xdg_desktop_names: ?[:0]const u8 = null,
cmd: []const u8 = "",
specifier: []const u8 = "",
display_server: DisplayServer = .wayland,
