const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

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

pub const unistd = @cImport({
    @cInclude("unistd.h");
});

// FreeBSD-specific headers
pub const logincap = @cImport({
    @cInclude("login_cap.h");
});

// BSD-specific headers
pub const kbio = @cImport({
    @cInclude("sys/kbio.h");
});

// Linux-specific headers
pub const kd = @cImport({
    @cInclude("sys/kd.h");
});

pub const vt = @cImport({
    @cInclude("sys/vt.h");
});

pub const c_size = usize;
pub const c_uid = u32;
pub const c_gid = u32;
pub const c_time = c_longlong;
pub const tm = extern struct {
    tm_sec: c_int,
    tm_min: c_int,
    tm_hour: c_int,
    tm_mday: c_int,
    tm_mon: c_int,
    tm_year: c_int,
    tm_wday: c_int,
    tm_yday: c_int,
    tm_isdst: c_int,
};

pub extern "c" fn localtime(timer: *const c_time) *tm;
pub extern "c" fn strftime(str: [*:0]u8, maxsize: c_size, format: [*:0]const u8, timeptr: *const tm) c_size;
pub extern "c" fn setenv(name: [*:0]const u8, value: ?[*:0]const u8, overwrite: c_int) c_int;
pub extern "c" fn putenv(name: [*:0]u8) c_int;
pub extern "c" fn getuid() c_uid;
pub extern "c" fn endpwent() void;
pub extern "c" fn setusershell() void;
pub extern "c" fn getusershell() [*:0]u8;
pub extern "c" fn endusershell() void;
pub extern "c" fn initgroups(user: [*:0]const u8, group: c_gid) c_int;

pub fn timeAsString(buf: [:0]u8, format: [:0]const u8) ![]u8 {
    const timer = std.time.timestamp();
    const tm_info = localtime(&timer);

    const len = strftime(buf, buf.len, format, tm_info);
    if (len < 0) return error.CannotGetFormattedTime;

    return buf[0..len];
}

pub fn switchTty(console_dev: []const u8, tty: u8) !void {
    const fd = try std.posix.open(console_dev, .{ .ACCMODE = .WRONLY }, 0);
    defer std.posix.close(fd);

    _ = std.c.ioctl(fd, vt.VT_ACTIVATE, tty);
    _ = std.c.ioctl(fd, vt.VT_WAITACTIVE, tty);
}

pub fn getLockState(console_dev: []const u8) !struct {
    numlock: bool,
    capslock: bool,
} {
    const fd = try std.posix.open(console_dev, .{ .ACCMODE = .RDONLY }, 0);
    defer std.posix.close(fd);

    var numlock = false;
    var capslock = false;

    if (builtin.os.tag.isBSD()) {
        var led: c_int = undefined;
        _ = std.c.ioctl(fd, kbio.KDGETLED, &led);
        numlock = (led & kbio.LED_NUM) != 0;
        capslock = (led & kbio.LED_CAP) != 0;
    } else {
        var led: c_char = undefined;
        _ = std.c.ioctl(fd, kd.KDGKBLED, &led);
        numlock = (led & kd.K_NUMLOCK) != 0;
        capslock = (led & kd.K_CAPSLOCK) != 0;
    }

    return .{
        .numlock = numlock,
        .capslock = capslock,
    };
}

pub fn setNumlock(val: bool) !void {
    if (builtin.os.tag.isBSD()) {
        var led: c_int = undefined;
        _ = std.c.ioctl(0, kbio.KDGETLED, &led);

        const numlock = (led & kbio.LED_NUM) != 0;
        if (numlock != val) {
            const status = std.c.ioctl(std.posix.STDIN_FILENO, kbio.KDSETLED, led ^ kbio.LED_NUM);
            if (status != 0) return error.FailedToSetNumlock;
        }

        return;
    }

    var led: c_char = undefined;
    _ = std.c.ioctl(0, kd.KDGKBLED, &led);

    const numlock = (led & kd.K_NUMLOCK) != 0;
    if (numlock != val) {
        const status = std.c.ioctl(std.posix.STDIN_FILENO, kd.KDSKBLED, led ^ kd.K_NUMLOCK);
        if (status != 0) return error.FailedToSetNumlock;
    }
}
