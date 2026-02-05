const std = @import("std");
const builtin = @import("builtin");
const UidRange = @import("UidRange.zig");

pub const pam = @cImport({
    @cInclude("security/pam_appl.h");
});

pub const utmp = @cImport({
    @cInclude("utmpx.h");
});

// Exists for X11 support only
pub const xcb = @cImport({
    @cInclude("xcb/xcb.h");
});

const pwd = @cImport({
    @cInclude("pwd.h");
    // We include a FreeBSD-specific header here since login_cap.h references
    // the passwd struct directly, so we can't import it separately
    if (builtin.os.tag == .freebsd) {
        @cInclude("sys/types.h");
        @cInclude("login_cap.h");
    }
});

const stdlib = @cImport({
    @cInclude("stdlib.h");
});

const unistd = @cImport({
    @cInclude("unistd.h");
});

const grp = @cImport({
    @cInclude("grp.h");
});

const system_time = @cImport({
    @cInclude("sys/time.h");
});

const time = @cImport({
    @cInclude("time.h");
});

pub const TimeOfDay = struct {
    seconds: i64,
    microseconds: i64,
};

pub const UsernameEntry = struct {
    username: ?[]const u8,
    uid: std.posix.uid_t,
    gid: std.posix.gid_t,
    home: ?[]const u8,
    shell: ?[]const u8,
    passwd_struct: [*c]pwd.passwd,
};

// Contains the platform-specific code
fn PlatformStruct() type {
    return switch (builtin.os.tag) {
        .linux => struct {
            pub const kd = @cImport({
                @cInclude("sys/kd.h");
            });

            pub const vt = @cImport({
                @cInclude("sys/vt.h");
            });

            pub const LedState = c_char;
            pub const get_led_state = kd.KDGKBLED;
            pub const set_led_state = kd.KDSKBLED;
            pub const numlock_led = kd.K_NUMLOCK;
            pub const capslock_led = kd.K_CAPSLOCK;
            pub const vt_activate = vt.VT_ACTIVATE;
            pub const vt_waitactive = vt.VT_WAITACTIVE;

            pub fn setUserContextImpl(username: [*:0]const u8, entry: UsernameEntry) !void {
                const status = grp.initgroups(username, @intCast(entry.gid));
                if (status != 0) return error.GroupInitializationFailed;

                std.posix.setgid(@intCast(entry.gid)) catch return error.SetUserGidFailed;
                std.posix.setuid(@intCast(entry.uid)) catch return error.SetUserUidFailed;
            }

            // Procedure:
            // 1. Open /proc/self/stat to retrieve the tty_nr field
            // 2. Parse the tty_nr field to extract the major and minor device
            //    numbers
            // 3. Then, read every /sys/class/tty/[dir]/dev, where [dir] is
            //    every sub-directory
            // 4. Finally, compare the major and minor device numbers with the
            //    extracted values. If they correspond, parse [dir] to get the
            //    TTY ID
            pub fn getActiveTtyImpl(allocator: std.mem.Allocator, use_kmscon_vt: bool) !u8 {
                var file_buffer: [256]u8 = undefined;

                if (use_kmscon_vt) {
                    var file = try std.fs.openFileAbsolute("/sys/class/tty/tty0/active", .{});
                    defer file.close();

                    var reader = file.reader(&file_buffer);
                    var buffer: [16]u8 = undefined;
                    const read = try readBuffer(&reader.interface, &buffer);

                    const tty = buffer[0..(read - 1)];
                    return std.fmt.parseInt(u8, tty["tty".len..], 10);
                }

                var tty_major: u16 = undefined;
                var tty_minor: u16 = undefined;

                {
                    var file = try std.fs.openFileAbsolute("/proc/self/stat", .{});
                    defer file.close();

                    var reader = file.reader(&file_buffer);
                    var buffer: [1024]u8 = undefined;
                    const read = try readBuffer(&reader.interface, &buffer);

                    var iterator = std.mem.splitScalar(u8, buffer[0..read], ' ');
                    var fields: [52][]const u8 = undefined;
                    var index: usize = 0;

                    while (iterator.next()) |field| {
                        fields[index] = field;
                        index += 1;
                    }

                    const tty_nr = try std.fmt.parseInt(u16, fields[6], 10);
                    tty_major = tty_nr / 256;
                    tty_minor = tty_nr % 256;
                }

                var directory = try std.fs.openDirAbsolute("/sys/class/tty", .{ .iterate = true });
                defer directory.close();

                var iterator = directory.iterate();
                while (try iterator.next()) |entry| {
                    const path = try std.fmt.allocPrint(allocator, "/sys/class/tty/{s}/dev", .{entry.name});
                    defer allocator.free(path);

                    var file = try std.fs.openFileAbsolute(path, .{});
                    defer file.close();

                    var reader = file.reader(&file_buffer);
                    var buffer: [16]u8 = undefined;
                    const read = try readBuffer(&reader.interface, &buffer);

                    var device_iterator = std.mem.splitScalar(u8, buffer[0..(read - 1)], ':');
                    const device_major_str = device_iterator.next() orelse continue;
                    const device_minor_str = device_iterator.next() orelse continue;

                    const device_major = try std.fmt.parseInt(u8, device_major_str, 10);
                    const device_minor = try std.fmt.parseInt(u8, device_minor_str, 10);

                    if (device_major == tty_major and device_minor == tty_minor) {
                        const tty_id_str = entry.name["tty".len..];
                        return try std.fmt.parseInt(u8, tty_id_str, 10);
                    }
                }

                return error.NoTtyFound;
            }

            // This is very bad parsing, but we only need to get 2 values..
            // and the format of the file seems to be standard? So this should
            // be fine...
            pub fn getUserIdRange(allocator: std.mem.Allocator, file_path: []const u8) !UidRange {
                const login_defs_file = try std.fs.cwd().openFile(file_path, .{});
                defer login_defs_file.close();

                const login_defs_buffer = try login_defs_file.readToEndAlloc(allocator, std.math.maxInt(u16));
                defer allocator.free(login_defs_buffer);

                var iterator = std.mem.splitScalar(u8, login_defs_buffer, '\n');
                var uid_range = UidRange{};
                var nameFound = false;

                while (iterator.next()) |line| {
                    const trimmed_line = std.mem.trim(u8, line, " \n\r\t");

                    if (std.mem.startsWith(u8, trimmed_line, "UID_MIN")) {
                        uid_range.uid_min = try parseValue(std.posix.uid_t, "UID_MIN", trimmed_line);
                        nameFound = true;
                    } else if (std.mem.startsWith(u8, trimmed_line, "UID_MAX")) {
                        uid_range.uid_max = try parseValue(std.posix.uid_t, "UID_MAX", trimmed_line);
                        nameFound = true;
                    }
                }

                if (!nameFound) return error.UidNameNotFound;

                return uid_range;
            }

            fn parseValue(comptime T: type, name: []const u8, buffer: []const u8) !T {
                var iterator = std.mem.splitAny(u8, buffer, " \t");
                var maybe_value: ?T = null;

                while (iterator.next()) |slice| {
                    // Skip the slice if it's empty (whitespace) or is the name of the
                    // property (e.g. UID_MIN or UID_MAX)
                    if (slice.len == 0 or std.mem.eql(u8, slice, name)) continue;
                    maybe_value = std.fmt.parseInt(T, slice, 10) catch continue;
                }

                return maybe_value orelse error.ValueNotFound;
            }

            fn readBuffer(reader: *std.Io.Reader, buffer: []u8) !usize {
                var bytes_read: usize = 0;
                var byte: u8 = try reader.takeByte();

                while (byte != 0 and bytes_read < buffer.len) {
                    buffer[bytes_read] = byte;
                    bytes_read += 1;
                    byte = reader.takeByte() catch break;
                }

                return bytes_read;
            }
        },
        .freebsd => struct {
            pub const kbio = @cImport({
                @cInclude("sys/kbio.h");
            });

            pub const consio = @cImport({
                @cInclude("sys/consio.h");
            });

            pub const LedState = c_int;
            pub const get_led_state = kbio.KDGETLED;
            pub const set_led_state = kbio.KDSETLED;
            pub const numlock_led = kbio.LED_NUM;
            pub const capslock_led = kbio.LED_CAP;
            pub const vt_activate = consio.VT_ACTIVATE;
            pub const vt_waitactive = consio.VT_WAITACTIVE;

            const FREEBSD_UID_MIN = 1000;
            const FREEBSD_UID_MAX = 32000;

            pub fn setUserContextImpl(username: [*:0]const u8, entry: UsernameEntry) !void {
                // FreeBSD has initgroups() in unistd
                const status = unistd.initgroups(username, @intCast(entry.gid));
                if (status != 0) return error.GroupInitializationFailed;

                // FreeBSD sets the GID and UID with setusercontext()
                const result = pwd.setusercontext(null, entry.passwd_struct, @intCast(entry.uid), pwd.LOGIN_SETALL);
                if (result != 0) return error.SetUserUidFailed;
            }

            pub fn getActiveTtyImpl(_: std.mem.Allocator, _: bool) !u8 {
                return error.FeatureUnimplemented;
            }

            pub fn getUserIdRange(_: std.mem.Allocator, _: []const u8) !UidRange {
                return .{
                    // Hardcoded default values chosen from
                    // /usr/src/usr.sbin/pw/pw_conf.c
                    .uid_min = FREEBSD_UID_MIN,
                    .uid_max = FREEBSD_UID_MAX,
                };
            }
        },
        else => @compileError("Unsupported target: " ++ builtin.os.tag),
    };
}

const platform_struct = PlatformStruct();

pub fn supportsUnicode() bool {
    return builtin.os.tag == .linux or builtin.os.tag == .freebsd;
}

pub fn timeAsString(buf: [:0]u8, format: [:0]const u8) []u8 {
    const timer = std.time.timestamp();
    const tm_info = time.localtime(&timer);
    const len = time.strftime(buf, buf.len, format, tm_info);

    return buf[0..len];
}

pub fn getTimeOfDay() !TimeOfDay {
    var tv: system_time.timeval = undefined;
    const status = system_time.gettimeofday(&tv, null);

    if (status != 0) return error.FailedToGetTimeOfDay;

    return .{
        .seconds = @intCast(tv.tv_sec),
        .microseconds = @intCast(tv.tv_usec),
    };
}

pub fn getActiveTty(allocator: std.mem.Allocator, use_kmscon_vt: bool) !u8 {
    return platform_struct.getActiveTtyImpl(allocator, use_kmscon_vt);
}

pub fn switchTty(tty: u8) !void {
    var status = std.c.ioctl(std.posix.STDIN_FILENO, platform_struct.vt_activate, tty);
    if (status != 0) return error.FailedToActivateTty;

    status = std.c.ioctl(std.posix.STDIN_FILENO, platform_struct.vt_waitactive, tty);
    if (status != 0) return error.FailedToWaitForActiveTty;
}

pub fn getLockState() !struct {
    numlock: bool,
    capslock: bool,
} {
    var led: platform_struct.LedState = undefined;
    const status = std.c.ioctl(std.posix.STDIN_FILENO, platform_struct.get_led_state, &led);
    if (status != 0) return error.FailedToGetLockState;

    return .{
        .numlock = (led & platform_struct.numlock_led) != 0,
        .capslock = (led & platform_struct.capslock_led) != 0,
    };
}

pub fn setNumlock(val: bool) !void {
    var led: platform_struct.LedState = undefined;
    var status = std.c.ioctl(std.posix.STDIN_FILENO, platform_struct.get_led_state, &led);
    if (status != 0) return error.FailedToGetNumlock;

    const numlock = (led & platform_struct.numlock_led) != 0;
    if (numlock != val) {
        status = std.c.ioctl(std.posix.STDIN_FILENO, platform_struct.set_led_state, led ^ platform_struct.numlock_led);
        if (status != 0) return error.FailedToSetNumlock;
    }
}

pub fn setUserContext(allocator: std.mem.Allocator, entry: UsernameEntry) !void {
    const username_z = try allocator.dupeZ(u8, entry.username.?);
    defer allocator.free(username_z);

    return platform_struct.setUserContextImpl(username_z.ptr, entry);
}

pub fn setUserShell(entry: *UsernameEntry) void {
    unistd.setusershell();

    const shell = unistd.getusershell();
    entry.shell = std.mem.span(shell);

    unistd.endusershell();
}

pub fn setEnvironmentVariable(allocator: std.mem.Allocator, name: []const u8, value: []const u8, replace: bool) !void {
    const name_z = try allocator.dupeZ(u8, name);
    defer allocator.free(name_z);

    const value_z = try allocator.dupeZ(u8, value);
    defer allocator.free(value_z);

    const status = stdlib.setenv(name_z.ptr, value_z.ptr, @intFromBool(replace));
    if (status != 0) return error.SetEnvironmentVariableFailed;
}

pub fn putEnvironmentVariable(name_and_value: [*c]u8) !void {
    const status = stdlib.putenv(name_and_value);
    if (status != 0) return error.PutEnvironmentVariableFailed;
}

pub fn getNextUsernameEntry() ?UsernameEntry {
    const entry = pwd.getpwent();
    if (entry == null) return null;

    return .{
        .username = if (entry.*.pw_name) |name| std.mem.span(name) else null,
        .uid = @intCast(entry.*.pw_uid),
        .gid = @intCast(entry.*.pw_gid),
        .home = if (entry.*.pw_dir) |dir| std.mem.span(dir) else null,
        .shell = if (entry.*.pw_shell) |shell| std.mem.span(shell) else null,
        .passwd_struct = entry,
    };
}

pub fn getUsernameEntry(username: [:0]const u8) ?UsernameEntry {
    const entry = pwd.getpwnam(username);
    if (entry == null) return null;

    return .{
        .username = if (entry.*.pw_name) |name| std.mem.span(name) else null,
        .uid = @intCast(entry.*.pw_uid),
        .gid = @intCast(entry.*.pw_gid),
        .home = if (entry.*.pw_dir) |dir| std.mem.span(dir) else null,
        .shell = if (entry.*.pw_shell) |shell| std.mem.span(shell) else null,
        .passwd_struct = entry,
    };
}

pub fn closePasswordDatabase() void {
    pwd.endpwent();
}

// This is very bad parsing, but we only need to get 2 values... and the format
// of the file doesn't seem to be standard? So this should be fine...
pub fn getUserIdRange(allocator: std.mem.Allocator, file_path: []const u8) !UidRange {
    return platform_struct.getUserIdRange(allocator, file_path);
}
