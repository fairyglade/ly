const std = @import("std");
const enums = @import("../../enums.zig");
const interop = @import("../../interop.zig");
const TerminalBuffer = @import("../TerminalBuffer.zig");
const Ini = @import("zigini").Ini;
const Lang = @import("../../config/Lang.zig");

const Allocator = std.mem.Allocator;
const EnvironmentList = std.ArrayList(Environment);

const DisplayServer = enums.DisplayServer;

const termbox = interop.termbox;

const Desktop = @This();

pub const Environment = struct {
    entry_ini: ?Ini(Entry) = null,
    name: [:0]const u8 = "",
    xdg_name: [:0]const u8 = "",
    cmd: []const u8 = "",
    specifier: []const u8 = "",
    display_server: DisplayServer = .wayland,
};

const DesktopEntry = struct {
    Exec: []const u8 = "",
    Name: [:0]const u8 = "",
    DesktopNames: [:0]const u8 = "",
};

pub const Entry = struct { @"Desktop Entry": DesktopEntry = DesktopEntry{} };

allocator: Allocator,
buffer: *TerminalBuffer,
environments: EnvironmentList,
current: u64,
visible_length: u64,
x: u64,
y: u64,
lang: Lang,

pub fn init(allocator: Allocator, buffer: *TerminalBuffer, max_length: u64, lang: Lang) !Desktop {
    return .{
        .allocator = allocator,
        .buffer = buffer,
        .environments = try EnvironmentList.initCapacity(allocator, max_length),
        .current = 0,
        .visible_length = 0,
        .x = 0,
        .y = 0,
        .lang = lang,
    };
}

pub fn deinit(self: Desktop) void {
    for (self.environments.items) |*environment| {
        if (environment.entry_ini) |*entry_ini| entry_ini.deinit();
    }

    self.environments.deinit();
}

pub fn position(self: *Desktop, x: u64, y: u64, visible_length: u64) void {
    self.x = x;
    self.y = y;
    self.visible_length = visible_length;
}

pub fn addEnvironment(self: *Desktop, entry: DesktopEntry, display_server: DisplayServer) !void {
    try self.environments.append(.{
        .entry_ini = null,
        .name = entry.Name,
        .xdg_name = entry.DesktopNames,
        .cmd = entry.Exec,
        .specifier = switch (display_server) {
            .wayland => self.lang.wayland,
            .x11 => self.lang.x11,
            else => self.lang.other,
        },
        .display_server = display_server,
    });

    self.current = self.environments.items.len - 1;
}

pub fn addEnvironmentWithIni(self: *Desktop, entry_ini: Ini(Entry), display_server: DisplayServer) !void {
    const entry = entry_ini.data.@"Desktop Entry";
    try self.environments.append(.{
        .entry_ini = entry_ini,
        .name = entry.Name,
        .xdg_name = entry.DesktopNames,
        .cmd = entry.Exec,
        .specifier = switch (display_server) {
            .wayland => self.lang.wayland,
            .x11 => self.lang.x11,
            else => self.lang.other,
        },
        .display_server = display_server,
    });

    self.current = self.environments.items.len - 1;
}

pub fn crawl(self: *Desktop, path: []const u8, display_server: DisplayServer) !void {
    var iterable_directory = std.fs.openDirAbsolute(path, .{ .iterate = true }) catch return;
    defer iterable_directory.close();

    var iterator = iterable_directory.iterate();
    while (try iterator.next()) |item| {
        if (!std.mem.eql(u8, std.fs.path.extension(item.name), ".desktop")) continue;

        const entry_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ path, item.name });
        defer self.allocator.free(entry_path);
        var entry_ini = Ini(Entry).init(self.allocator);
        _ = try entry_ini.readFileToStruct(entry_path);

        try self.addEnvironmentWithIni(entry_ini, display_server);
    }
}

pub fn handle(self: *Desktop, maybe_event: ?*termbox.tb_event, insert_mode: bool) void {
    if (maybe_event) |event| blk: {
        if (event.type != termbox.TB_EVENT_KEY) break :blk;

        switch (event.key) {
            termbox.TB_KEY_ARROW_LEFT, termbox.TB_KEY_CTRL_H => self.goLeft(),
            termbox.TB_KEY_ARROW_RIGHT, termbox.TB_KEY_CTRL_L => self.goRight(),
            else => {
                if (!insert_mode) {
                    switch (event.ch) {
                        'h' => self.goLeft(),
                        'l' => self.goRight(),
                        else => {},
                    }
                }
            },
        }
    }

    termbox.tb_set_cursor(@intCast(self.x + 2), @intCast(self.y));
}

pub fn draw(self: Desktop) void {
    const environment = self.environments.items[self.current];

    const length = @min(environment.name.len, self.visible_length - 3);
    if (length == 0) return;

    const x = self.buffer.box_x + self.buffer.margin_box_h;
    const y = self.buffer.box_y + self.buffer.margin_box_v + 2;
    self.buffer.drawLabel(environment.specifier, x, y);

    termbox.tb_change_cell(@intCast(self.x), @intCast(self.y), '<', self.buffer.fg, self.buffer.bg);
    termbox.tb_change_cell(@intCast(self.x + self.visible_length - 1), @intCast(self.y), '>', self.buffer.fg, self.buffer.bg);

    self.buffer.drawLabel(environment.name, self.x + 2, self.y);
}

fn goLeft(self: *Desktop) void {
    if (self.current == 0) {
        self.current = self.environments.items.len - 1;
        return;
    }

    self.current -= 1;
}

fn goRight(self: *Desktop) void {
    if (self.current == self.environments.items.len - 1) {
        self.current = 0;
        return;
    }

    self.current += 1;
}
