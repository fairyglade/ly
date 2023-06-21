const std = @import("std");
const main = @import("main.zig");
const ini = @import("ini.zig");
const config = @import("config.zig");
const interop = @import("interop.zig");

const DESKTOP_ENTRY_MAX_SIZE: usize = 8 * 1024;

const Entry = struct {
    Desktop_Entry: struct {
        Name: []const u8,
        Comment: []const u8,
        Exec: []const u8,
        Type: []const u8,
        DesktopNames: []const u8,
    },
};

pub export fn desktop_load(target: *main.c.struct_desktop) void {
    // We don't care about desktop environments presence
    // because the fallback shell is always available
    // so we just dismiss any "throw" for now
    var err: c_int = 0;

    desktop_crawl(target, config.ly_config.ly.waylandsessions, main.c.DS_WAYLAND) catch {};

    if (main.c.dgn_catch() != 0) {
        err += 1;
        main.c.dgn_reset();
    }

    desktop_crawl(target, config.ly_config.ly.xsessions, main.c.DS_XORG) catch {};

    if (main.c.dgn_catch() != 0) {
        err += 1;
        main.c.dgn_reset();
    }
}

pub fn save(desktop: *main.c.struct_desktop, login: *main.c.struct_text) !void {
    if (!config.ly_config.ly.save) {
        return;
    }

    var file = std.fs.openFileAbsolute(config.ly_config.ly.save_file, .{ .mode = .write_only }) catch {
        return;
    };
    defer file.close();

    var buffer = try std.fmt.allocPrint(main.allocator, "{s}\n{d}", .{ login.*.text, desktop.*.cur });
    defer main.allocator.free(buffer);

    try file.writeAll(buffer);
}

pub fn load(desktop: *main.c.struct_desktop, login: *main.c.struct_text) !void {
    if (!config.ly_config.ly.load) {
        return;
    }

    var file = std.fs.openFileAbsolute(config.ly_config.ly.save_file, .{}) catch {
        return;
    };
    defer file.close();

    var buffer = try main.allocator.alloc(u8, config.ly_config.ly.max_login_len * 2 + 1);
    defer main.allocator.free(buffer);

    _ = try file.readAll(buffer);

    var array = std.mem.splitSequence(u8, buffer, "\n");

    login.*.text = try interop.c_str(array.first()); // TODO: Free?
    desktop.*.cur = try std.fmt.parseUnsigned(u16, array.next().?, 0);
}

fn desktop_crawl(target: *main.c.struct_desktop, sessions: []const u8, server: main.c.enum_display_server) !void {
    var iterable_dir = std.fs.openIterableDirAbsolute(sessions, .{}) catch {
        main.c.dgn_throw(main.c.DGN_XSESSIONS_OPEN);
        return;
    };
    defer iterable_dir.close();

    var iterator = iterable_dir.iterate();

    var dir = std.fs.openDirAbsolute(sessions, .{}) catch {
        main.c.dgn_throw(main.c.DGN_XSESSIONS_OPEN);
        return;
    };
    defer dir.close();

    while (try iterator.next()) |item| {
        if (!std.mem.endsWith(u8, item.name, ".desktop")) {
            continue;
        }

        var file = try dir.openFile(item.name, .{});
        defer file.close();

        var buffer = try main.allocator.alloc(u8, DESKTOP_ENTRY_MAX_SIZE); // TODO: Free
        var length = try file.readAll(buffer);
        var entry = try ini.readToStruct(Entry, buffer[0..length]);

        // TODO: If it's a wayland session, add " (Wayland)" to its name,
        // as long as it doesn't already contain that string

        const name = entry.Desktop_Entry.Name;
        const exec = entry.Desktop_Entry.Exec;

        if (name.len > 0 and exec.len > 0) {
            main.c.input_desktop_add(target, (try interop.c_str(name)).ptr, (try interop.c_str(exec)).ptr, server);
        }
    }
}
