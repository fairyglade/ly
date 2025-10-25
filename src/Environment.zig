const enums = @import("enums.zig");
const ini = @import("zigini");

const DisplayServer = enums.DisplayServer;
const Ini = ini.Ini;

pub const DesktopEntry = struct {
    Exec: []const u8 = "",
    Name: []const u8 = "",
    DesktopNames: ?[]u8 = null,
    Terminal: ?bool = null,
};

pub const Entry = struct { @"Desktop Entry": DesktopEntry = .{} };

entry_ini: ?Ini(Entry) = null,
name: []const u8 = "",
xdg_session_desktop: ?[]const u8 = null,
xdg_session_desktop_owned: bool = false,
xdg_desktop_names: ?[]const u8 = null,
cmd: ?[]const u8 = null,
specifier: []const u8 = "",
display_server: DisplayServer = .wayland,
is_terminal: bool = false,
