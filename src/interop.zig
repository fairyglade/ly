const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

pub const termbox = @import("termbox2");

pub const pam = @cImport({
    @cInclude("security/pam_appl.h");
});

pub const utmp = @cImport({
    @cInclude("utmp.h");
});

pub const xcb = @cImport({
    @cInclude("xcb/xcb.h");
});

pub const c_size = u64;
pub const c_uid = u32;
pub const c_gid = u32;
pub const c_time = c_long;
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
pub const passwd = extern struct {
    pw_name: [*:0]u8,
    pw_passwd: [*:0]u8,

    pw_uid: c_uid,
    pw_gid: c_gid,
    pw_gecos: [*:0]u8,
    pw_dir: [*:0]u8,
    pw_shell: [*:0]u8,
};

pub const VT_ACTIVATE: c_int = 0x5606;
pub const VT_WAITACTIVE: c_int = 0x5607;

pub const KDGETLED: c_int = 0x4B31;
pub const KDSETLED: c_int = 0x4B32;
pub const KDGKBLED: c_int = 0x4B64;
pub const KDSKBLED: c_int = 0x4B65;

pub const LED_NUM: c_int = 0x02;
pub const LED_CAP: c_int = 0x04;

pub const K_NUMLOCK: c_int = 0x02;
pub const K_CAPSLOCK: c_int = 0x04;

pub extern "c" fn localtime(timer: *const c_time) *tm;
pub extern "c" fn strftime(str: [*:0]u8, maxsize: c_size, format: [*:0]const u8, timeptr: *const tm) c_size;
pub extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
pub extern "c" fn putenv(name: [*:0]u8) c_int;
pub extern "c" fn getuid() c_uid;
pub extern "c" fn getpwnam(name: [*:0]const u8) ?*passwd;
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

pub fn getLockState(console_dev: [:0]const u8) !struct {
    numlock: bool,
    capslock: bool,
} {
    const fd = std.c.open(console_dev, .{ .ACCMODE = .RDONLY });
    if (fd < 0) return error.CannotOpenConsoleDev;
    defer _ = std.c.close(fd);

    var numlock = false;
    var capslock = false;

    if (builtin.os.tag.isBSD()) {
        var led: c_int = undefined;
        _ = std.c.ioctl(fd, KDGETLED, &led);
        numlock = (led & LED_NUM) != 0;
        capslock = (led & LED_CAP) != 0;
    } else {
        var led: c_char = undefined;
        _ = std.c.ioctl(fd, KDGKBLED, &led);
        numlock = (led & K_NUMLOCK) != 0;
        capslock = (led & K_CAPSLOCK) != 0;
    }

    return .{
        .numlock = numlock,
        .capslock = capslock,
    };
}

pub fn setNumlock(val: bool) !void {
    var led: c_char = undefined;
    _ = std.c.ioctl(0, KDGKBLED, &led);

    const numlock = (led & K_NUMLOCK) != 0;
    if (numlock != val) {
        const status = std.c.ioctl(std.posix.STDIN_FILENO, KDSKBLED, led ^ K_NUMLOCK);
        if (status != 0) return error.FailedToSetNumlock;
    }
}
