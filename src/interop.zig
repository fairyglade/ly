const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

pub const termbox = @cImport({
    @cInclude("termbox.h");
});

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

pub const SIGTERM: c_int = 15;
pub const ESRCH: c_int = 3;

pub const _POSIX_HOST_NAME_MAX: c_int = 0xFF;
pub const _SC_HOST_NAME_MAX: c_int = 0xB4;

pub const VT_ACTIVATE: c_int = 0x5606;
pub const VT_WAITACTIVE: c_int = 0x5607;

pub const KDGETLED: c_int = 0x4B31;
pub const KDGKBLED: c_int = 0x4B64;

pub const LED_NUM: c_int = 0x02;
pub const LED_CAP: c_int = 0x04;

pub const K_NUMLOCK: c_int = 0x02;
pub const K_CAPSLOCK: c_int = 0x04;

pub const O_RDONLY: c_uint = 0x00;
pub const O_WRONLY: c_uint = 0x01;
pub const O_RDWR: c_uint = 0x02;

pub extern "c" fn fileno(stream: *std.c.FILE) c_int;
pub extern "c" fn sysconf(name: c_int) c_long;
pub extern "c" fn time(second: ?*c_time) c_time;
pub extern "c" fn localtime(timer: *const c_time) *tm;
pub extern "c" fn strftime(str: [*:0]u8, maxsize: c_size, format: [*:0]const u8, timeptr: *const tm) c_size;
pub extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
pub extern "c" fn getenv(name: [*:0]const u8) [*:0]u8;
pub extern "c" fn putenv(name: [*:0]u8) c_int;
pub extern "c" fn clearenv() c_int;
pub extern "c" fn getuid() c_uid;
pub extern "c" fn getpwnam(name: [*:0]const u8) ?*passwd;
pub extern "c" fn endpwent() void;
pub extern "c" fn setusershell() void;
pub extern "c" fn getusershell() [*:0]u8;
pub extern "c" fn endusershell() void;
pub extern "c" fn initgroups(user: [*:0]const u8, group: c_gid) c_int;
pub extern "c" fn chdir(path: [*:0]const u8) c_int;
pub extern "c" fn execl(path: [*:0]const u8, arg: [*:0]const u8, ...) c_int;

pub fn getHostName(allocator: Allocator) !struct {
    buffer: []u8,
    slice: []const u8,
} {
    const hostname_sysconf = sysconf(_SC_HOST_NAME_MAX);
    const hostname_max_length: u64 = if (hostname_sysconf < 0) @intCast(_POSIX_HOST_NAME_MAX) else @intCast(hostname_sysconf);

    const buffer = try allocator.alloc(u8, hostname_max_length);

    const error_code = std.c.gethostname(buffer.ptr, hostname_max_length);
    if (error_code < 0) return error.CannotGetHostName;

    var hostname_length: u64 = 0;
    for (buffer, 0..) |char, i| {
        if (char == 0) {
            hostname_length = i + 1;
            break;
        }
    }

    return .{
        .buffer = buffer,
        .slice = buffer[0..hostname_length],
    };
}

pub fn timeAsString(allocator: Allocator, format: []const u8, max_length: u64) ![:0]u8 {
    const timer = time(null);
    const tm_info = localtime(&timer);
    const buffer = try allocator.allocSentinel(u8, max_length, 0);

    const format_z = try allocator.dupeZ(u8, format);
    defer allocator.free(format_z);

    if (strftime(buffer, max_length, format_z, tm_info) < 0) return error.CannotGetFormattedTime;

    return buffer;
}

pub fn getLockState(allocator: Allocator, console_dev: []const u8) !struct {
    numlock: bool,
    capslock: bool,
} {
    const console_dev_z = try allocator.dupeZ(u8, console_dev);
    defer allocator.free(console_dev_z);

    const fd = std.c.open(console_dev_z, O_RDONLY);
    if (fd < 0) return error.CannotOpenConsoleDev;

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

    _ = std.c.close(fd);

    return .{
        .numlock = numlock,
        .capslock = capslock,
    };
}
