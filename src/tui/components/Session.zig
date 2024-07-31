const std = @import("std");
const TerminalBuffer = @import("../TerminalBuffer.zig");
const enums = @import("../../enums.zig");
const generic = @import("generic.zig");
const Ini = @import("zigini").Ini;
const Lang = @import("../../config/Lang.zig");

const Allocator = std.mem.Allocator;

const DisplayServer = enums.DisplayServer;

const EnvironmentLabel = generic.CyclableLabel(Environment);

const Session = @This();

pub const Environment = struct {
    entry_ini: ?Ini(Entry) = null,
    name: [:0]const u8 = "",
    xdg_session_desktop: [:0]const u8 = "",
    xdg_desktop_names: ?[:0]const u8 = "",
    cmd: []const u8 = "",
    specifier: []const u8 = "",
    display_server: DisplayServer = .wayland,
};

const DesktopEntry = struct {
    Exec: []const u8 = "",
    Name: [:0]const u8 = "",
    DesktopNames: ?[]const u8 = null,
};

pub const Entry = struct { @"Desktop Entry": DesktopEntry = .{} };

label: EnvironmentLabel,
lang: Lang,

pub fn init(allocator: Allocator, buffer: *TerminalBuffer, lang: Lang) Session {
    return .{
        .label = EnvironmentLabel.init(allocator, buffer, drawItem),
        .lang = lang,
    };
}

pub fn deinit(self: Session) void {
    for (self.label.list.items) |*environment| {
        if (environment.entry_ini) |*entry_ini| entry_ini.deinit();
        if (environment.xdg_desktop_names) |desktop_name| self.label.allocator.free(desktop_name);
        self.label.allocator.free(environment.xdg_session_desktop);
    }

    self.label.deinit();
}

pub fn addEnvironment(self: *Session, entry: DesktopEntry, xdg_session_desktop: []const u8, display_server: DisplayServer) !void {
    var xdg_desktop_names: ?[:0]const u8 = null;
    if (entry.DesktopNames) |desktop_names| {
        const desktop_names_z = try self.label.allocator.dupeZ(u8, desktop_names);
        for (desktop_names_z) |*c| {
            if (c.* == ';') c.* = ':';
        }
        xdg_desktop_names = desktop_names_z;
    }

    errdefer {
        if (xdg_desktop_names) |desktop_names| self.label.allocator.free(desktop_names);
    }

    const session_desktop = try self.label.allocator.dupeZ(u8, xdg_session_desktop);
    errdefer self.label.allocator.free(session_desktop);

    try self.label.addItem(.{
        .entry_ini = null,
        .name = entry.Name,
        .xdg_session_desktop = session_desktop,
        .xdg_desktop_names = xdg_desktop_names,
        .cmd = entry.Exec,
        .specifier = switch (display_server) {
            .wayland => self.lang.wayland,
            .x11 => self.lang.x11,
            else => self.lang.other,
        },
        .display_server = display_server,
    });
}

pub fn addEnvironmentWithIni(self: *Session, entry_ini: Ini(Entry), xdg_session_desktop: []const u8, display_server: DisplayServer) !void {
    const entry = entry_ini.data.@"Desktop Entry";
    var xdg_desktop_names: ?[:0]const u8 = null;
    if (entry.DesktopNames) |desktop_names| {
        const desktop_names_z = try self.label.allocator.dupeZ(u8, desktop_names);
        for (desktop_names_z) |*c| {
            if (c.* == ';') c.* = ':';
        }
        xdg_desktop_names = desktop_names_z;
    }

    errdefer {
        if (xdg_desktop_names) |desktop_names| self.label.allocator.free(desktop_names);
    }

    const session_desktop = try self.label.allocator.dupeZ(u8, xdg_session_desktop);
    errdefer self.label.allocator.free(session_desktop);

    try self.label.addItem(.{
        .entry_ini = entry_ini,
        .name = entry.Name,
        .xdg_session_desktop = session_desktop,
        .xdg_desktop_names = xdg_desktop_names,
        .cmd = entry.Exec,
        .specifier = switch (display_server) {
            .wayland => self.lang.wayland,
            .x11 => self.lang.x11,
            else => self.lang.other,
        },
        .display_server = display_server,
    });
}

pub fn crawl(self: *Session, path: []const u8, display_server: DisplayServer) !void {
    var iterable_directory = std.fs.openDirAbsolute(path, .{ .iterate = true }) catch return;
    defer iterable_directory.close();

    var iterator = iterable_directory.iterate();
    while (try iterator.next()) |item| {
        if (!std.mem.eql(u8, std.fs.path.extension(item.name), ".desktop")) continue;

        const entry_path = try std.fmt.allocPrint(self.label.allocator, "{s}/{s}", .{ path, item.name });
        defer self.label.allocator.free(entry_path);
        var entry_ini = Ini(Entry).init(self.label.allocator);
        _ = try entry_ini.readFileToStruct(entry_path, "#", null);
        errdefer entry_ini.deinit();

        var xdg_session_desktop: []const u8 = undefined;
        const maybe_desktop_names = entry_ini.data.@"Desktop Entry".DesktopNames;
        if (maybe_desktop_names) |desktop_names| {
            xdg_session_desktop = std.mem.sliceTo(desktop_names, ';');
        } else {
            // if DesktopNames is empty, we'll take the name of the session file
            xdg_session_desktop = std.fs.path.stem(item.name);
        }

        try self.addEnvironmentWithIni(entry_ini, xdg_session_desktop, display_server);
    }
}

fn drawItem(label: *EnvironmentLabel, environment: Environment, x: usize, y: usize) bool {
    const length = @min(environment.name.len, label.visible_length - 3);
    if (length == 0) return false;

    label.buffer.drawLabel(environment.specifier, x, y);
    label.buffer.drawLabel(environment.name, label.x + 2, label.y);
    return true;
}
