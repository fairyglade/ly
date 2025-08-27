const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

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
};

pub const termbox = @import("termbox2");

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
    if (builtin.os.tag == .freebsd) @cInclude("login_cap.h");
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

// BSD-specific headers
const kbio = @cImport({
    @cInclude("sys/kbio.h");
});

// Linux-specific headers
const kd = @cImport({
    @cInclude("sys/kd.h");
});

const vt = @cImport({
    @cInclude("sys/vt.h");
});

// Used for getting & setting the lock state
const LedState = if (builtin.os.tag.isBSD()) c_int else c_char;
const get_led_state = if (builtin.os.tag.isBSD()) kbio.KDGETLED else kd.KDGKBLED;
const set_led_state = if (builtin.os.tag.isBSD()) kbio.KDSETLED else kd.KDSKBLED;
const numlock_led = if (builtin.os.tag.isBSD()) kbio.LED_NUM else kd.K_NUMLOCK;
const capslock_led = if (builtin.os.tag.isBSD()) kbio.LED_CAP else kd.K_CAPSLOCK;

pub fn supportsUnicode() bool {
    return builtin.os.tag == .linux or builtin.os.tag.isBSD();
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

pub fn switchTty(tty: u8) !void {
    var status = std.c.ioctl(std.posix.STDIN_FILENO, vt.VT_ACTIVATE, tty);
    if (status != 0) return error.FailedToActivateTty;

    status = std.c.ioctl(std.posix.STDIN_FILENO, vt.VT_WAITACTIVE, tty);
    if (status != 0) return error.FailedToWaitForActiveTty;
}

pub fn getLockState() !struct {
    numlock: bool,
    capslock: bool,
} {
    var led: LedState = undefined;
    const status = std.c.ioctl(std.posix.STDIN_FILENO, get_led_state, &led);
    if (status != 0) return error.FailedToGetLockState;

    return .{
        .numlock = (led & numlock_led) != 0,
        .capslock = (led & capslock_led) != 0,
    };
}

pub fn setNumlock(val: bool) !void {
    var led: LedState = undefined;
    var status = std.c.ioctl(std.posix.STDIN_FILENO, get_led_state, &led);
    if (status != 0) return error.FailedToGetNumlock;

    const numlock = (led & numlock_led) != 0;
    if (numlock != val) {
        status = std.c.ioctl(std.posix.STDIN_FILENO, set_led_state, led ^ numlock_led);
        if (status != 0) return error.FailedToSetNumlock;
    }
}

pub fn setUserContext(allocator: std.mem.Allocator, entry: UsernameEntry) !void {
    const username_z = try allocator.dupeZ(u8, entry.username.?);
    defer allocator.free(username_z);

    if (builtin.os.tag == .freebsd) {
        // FreeBSD has initgroups() in unistd
        const status = unistd.initgroups(username_z.ptr, @intCast(entry.gid));
        if (status != 0) return error.GroupInitializationFailed;

        // FreeBSD sets the GID and UID with setusercontext()
        // TODO
        const result = pwd.setusercontext(null, entry, @intCast(entry.uid), pwd.LOGIN_SETALL);
        if (result != 0) return error.SetUserUidFailed;
    } else {
        const status = grp.initgroups(username_z.ptr, @intCast(entry.gid));
        if (status != 0) return error.GroupInitializationFailed;

        std.posix.setgid(@intCast(entry.gid)) catch return error.SetUserGidFailed;
        std.posix.setuid(@intCast(entry.uid)) catch return error.SetUserUidFailed;
    }
}

pub fn setUserShell(entry: *UsernameEntry) void {
    unistd.setusershell();

    const shell = unistd.getusershell();
    entry.shell = shell[0..std.mem.len(shell)];

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
        .username = if (entry.*.pw_name) |name| name[0..std.mem.len(name)] else null,
        .uid = @intCast(entry.*.pw_uid),
        .gid = @intCast(entry.*.pw_gid),
        .home = if (entry.*.pw_dir) |dir| dir[0..std.mem.len(dir)] else null,
        .shell = if (entry.*.pw_shell) |shell| shell[0..std.mem.len(shell)] else null,
    };
}

pub fn getUsernameEntry(username: [:0]const u8) ?UsernameEntry {
    const entry = pwd.getpwnam(username);
    if (entry == null) return null;

    return .{
        .username = if (entry.*.pw_name) |name| name[0..std.mem.len(name)] else null,
        .uid = @intCast(entry.*.pw_uid),
        .gid = @intCast(entry.*.pw_gid),
        .home = if (entry.*.pw_dir) |dir| dir[0..std.mem.len(dir)] else null,
        .shell = if (entry.*.pw_shell) |shell| shell[0..std.mem.len(shell)] else null,
    };
}

pub fn closePasswordDatabase() void {
    pwd.endpwent();
}
