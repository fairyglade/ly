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

pub const time = @cImport({
    @cInclude("time.h");
});

pub const system_time = @cImport({
    @cInclude("sys/time.h");
});

pub const stdlib = @cImport({
    @cInclude("stdlib.h");
});

pub const pwd = @cImport({
    @cInclude("pwd.h");
    // We include a FreeBSD-specific header here since login_cap.h references
    // the passwd struct directly, so we can't import it separately
    if (builtin.os.tag == .freebsd) @cInclude("login_cap.h");
});

pub const grp = @cImport({
    @cInclude("grp.h");
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

// Used for getting & setting the lock state
const LedState = if (builtin.os.tag.isBSD()) c_int else c_char;
const get_led_state = if (builtin.os.tag.isBSD()) kbio.KDGETLED else kd.KDGKBLED;
const set_led_state = if (builtin.os.tag.isBSD()) kbio.KDSETLED else kd.KDSKBLED;
const numlock_led = if (builtin.os.tag.isBSD()) kbio.LED_NUM else kd.K_NUMLOCK;
const capslock_led = if (builtin.os.tag.isBSD()) kbio.LED_CAP else kd.K_CAPSLOCK;

pub fn timeAsString(buf: [:0]u8, format: [:0]const u8) ![]u8 {
    const timer = std.time.timestamp();
    const tm_info = time.localtime(&timer);

    const len = time.strftime(buf, buf.len, format, tm_info);
    if (len < 0) return error.CannotGetFormattedTime;

    return buf[0..len];
}

pub fn switchTty(tty: u8) !void {
    var status = std.c.ioctl(std.c.STDIN_FILENO, vt.VT_ACTIVATE, tty);
    if (status != 0) return error.FailedToActivateTty;

    status = std.c.ioctl(std.c.STDIN_FILENO, vt.VT_WAITACTIVE, tty);
    if (status != 0) return error.FailedToWaitForActiveTty;
}

pub fn getLockState() !struct {
    numlock: bool,
    capslock: bool,
} {
    var led: LedState = undefined;
    const status = std.c.ioctl(std.c.STDIN_FILENO, get_led_state, &led);
    if (status != 0) return error.FailedToGetLockState;

    return .{
        .numlock = (led & numlock_led) != 0,
        .capslock = (led & capslock_led) != 0,
    };
}

pub fn setNumlock(val: bool) !void {
    var led: LedState = undefined;
    var status = std.c.ioctl(std.c.STDIN_FILENO, get_led_state, &led);
    if (status != 0) return error.FailedToGetNumlock;

    const numlock = (led & numlock_led) != 0;
    if (numlock != val) {
        status = std.c.ioctl(std.posix.STDIN_FILENO, set_led_state, led ^ numlock_led);
        if (status != 0) return error.FailedToSetNumlock;
    }
}
