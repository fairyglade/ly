const std = @import("std");
const enums = @import("enums.zig");
const interop = @import("interop.zig");
const TerminalBuffer = @import("tui/TerminalBuffer.zig");
const Desktop = @import("tui/components/Desktop.zig");
const Text = @import("tui/components/Text.zig");
const Config = @import("config/Config.zig");
const Allocator = std.mem.Allocator;
const utmp = interop.utmp;
const Utmp = utmp.utmp;
const SharedError = @import("SharedError.zig");

var xorg_pid: std.posix.pid_t = 0;
pub fn xorgSignalHandler(i: c_int) callconv(.C) void {
    if (xorg_pid > 0) _ = std.c.kill(xorg_pid, i);
}

var child_pid: std.posix.pid_t = 0;
pub fn sessionSignalHandler(i: c_int) callconv(.C) void {
    if (child_pid > 0) _ = std.c.kill(child_pid, i);
}

pub fn authenticate(config: Config, current_environment: Desktop.Environment, login: [:0]const u8, password: [:0]const u8) !void {
    var tty_buffer: [2]u8 = undefined;
    const tty_str = try std.fmt.bufPrintZ(&tty_buffer, "{d}", .{config.tty});

    // Set the XDG environment variables
    setXdgSessionEnv(current_environment.display_server);
    try setXdgEnv(tty_str, current_environment.xdg_session_desktop, current_environment.xdg_desktop_names orelse "");

    // Open the PAM session
    var credentials = [_:null]?[*:0]const u8{ login, password };

    const conv = interop.pam.pam_conv{
        .conv = loginConv,
        .appdata_ptr = @ptrCast(&credentials),
    };
    var handle: ?*interop.pam.pam_handle = undefined;

    var status = interop.pam.pam_start(config.service_name.ptr, null, &conv, &handle);
    if (status != interop.pam.PAM_SUCCESS) return pamDiagnose(status);
    defer _ = interop.pam.pam_end(handle, status);

    // Do the PAM routine
    status = interop.pam.pam_authenticate(handle, 0);
    if (status != interop.pam.PAM_SUCCESS) return pamDiagnose(status);

    status = interop.pam.pam_acct_mgmt(handle, 0);
    if (status != interop.pam.PAM_SUCCESS) return pamDiagnose(status);

    status = interop.pam.pam_setcred(handle, interop.pam.PAM_ESTABLISH_CRED);
    if (status != interop.pam.PAM_SUCCESS) return pamDiagnose(status);
    defer status = interop.pam.pam_setcred(handle, interop.pam.PAM_DELETE_CRED);

    status = interop.pam.pam_open_session(handle, 0);
    if (status != interop.pam.PAM_SUCCESS) return pamDiagnose(status);
    defer status = interop.pam.pam_close_session(handle, 0);

    var pwd: *interop.passwd = undefined;
    {
        defer interop.endpwent();

        // Get password structure from username
        pwd = interop.getpwnam(login.ptr) orelse return error.GetPasswordNameFailed;
    }

    // Set user shell if it hasn't already been set
    if (pwd.pw_shell[0] == 0) {
        interop.setusershell();
        pwd.pw_shell = interop.getusershell();
        interop.endusershell();
    }

    var shared_err = try SharedError.init();
    defer shared_err.deinit();

    child_pid = try std.posix.fork();
    if (child_pid == 0) {
        startSession(config, pwd, handle, current_environment) catch |e| {
            shared_err.writeError(e);
            std.process.exit(1);
        };
        std.process.exit(0);
    }

    var entry = std.mem.zeroes(Utmp);

    {
        // If an error occurs here, we can send SIGTERM to the session
        errdefer cleanup: {
            _ = std.posix.kill(child_pid, std.posix.SIG.TERM) catch break :cleanup;
            _ = std.posix.waitpid(child_pid, 0);
        }

        // If we receive SIGTERM, forward it to child_pid
        const act = std.posix.Sigaction{
            .handler = .{ .handler = &sessionSignalHandler },
            .mask = std.posix.empty_sigset,
            .flags = 0,
        };
        try std.posix.sigaction(std.posix.SIG.TERM, &act, null);

        try addUtmpEntry(&entry, pwd.pw_name, child_pid);
    }
    // Wait for the session to stop
    _ = std.posix.waitpid(child_pid, 0);

    removeUtmpEntry(&entry);

    try resetTerminal(pwd.pw_shell, config.term_reset_cmd);

    if (shared_err.readError()) |err| return err;
}

fn startSession(
    config: Config,
    pwd: *interop.passwd,
    handle: ?*interop.pam.pam_handle,
    current_environment: Desktop.Environment,
) !void {
    const status = interop.initgroups(pwd.pw_name, pwd.pw_gid);
    if (status != 0) return error.GroupInitializationFailed;

    std.posix.setgid(pwd.pw_gid) catch return error.SetUserGidFailed;
    std.posix.setuid(pwd.pw_uid) catch return error.SetUserUidFailed;

    // Set up the environment
    try initEnv(pwd, config.path);

    // Set the PAM variables
    const pam_env_vars: ?[*:null]?[*:0]u8 = interop.pam.pam_getenvlist(handle);
    if (pam_env_vars == null) return error.GetEnvListFailed;

    const env_list = std.mem.span(pam_env_vars.?);
    for (env_list) |env_var| _ = interop.putenv(env_var.?);

    // Execute what the user requested
    std.posix.chdirZ(pwd.pw_dir) catch return error.ChangeDirectoryFailed;

    try resetTerminal(pwd.pw_shell, config.term_reset_cmd);

    switch (current_environment.display_server) {
        .wayland => try executeWaylandCmd(pwd.pw_shell, config.wayland_cmd, current_environment.cmd),
        .shell => try executeShellCmd(pwd.pw_shell),
        .xinitrc, .x11 => {
            var vt_buf: [5]u8 = undefined;
            const vt = try std.fmt.bufPrint(&vt_buf, "vt{d}", .{config.tty});
            try executeX11Cmd(pwd.pw_shell, pwd.pw_dir, config, current_environment.cmd, vt);
        },
    }
}

fn initEnv(pwd: *interop.passwd, path_env: ?[:0]const u8) !void {
    _ = interop.setenv("HOME", pwd.pw_dir, 1);
    _ = interop.setenv("PWD", pwd.pw_dir, 1);
    _ = interop.setenv("SHELL", pwd.pw_shell, 1);
    _ = interop.setenv("USER", pwd.pw_name, 1);
    _ = interop.setenv("LOGNAME", pwd.pw_name, 1);

    if (path_env) |path| {
        const status = interop.setenv("PATH", path, 1);
        if (status != 0) return error.SetPathFailed;
    }
}

fn setXdgSessionEnv(display_server: enums.DisplayServer) void {
    _ = interop.setenv("XDG_SESSION_TYPE", switch (display_server) {
        .wayland => "wayland",
        .shell => "tty",
        .xinitrc, .x11 => "x11",
    }, 0);
}

fn setXdgEnv(tty_str: [:0]u8, desktop_name: [:0]const u8, xdg_desktop_names: [:0]const u8) !void {
    const uid = interop.getuid();
    var uid_buffer: [10 + @sizeOf(u32) + 1]u8 = undefined;
    const uid_str = try std.fmt.bufPrintZ(&uid_buffer, "/run/user/{d}", .{uid});

    _ = interop.setenv("XDG_CURRENT_DESKTOP", xdg_desktop_names.ptr, 0);
    _ = interop.setenv("XDG_RUNTIME_DIR", uid_str.ptr, 0);
    _ = interop.setenv("XDG_SESSION_CLASS", "user", 0);
    _ = interop.setenv("XDG_SESSION_ID", "1", 0);
    _ = interop.setenv("XDG_SESSION_DESKTOP", desktop_name.ptr, 0);
    _ = interop.setenv("XDG_SEAT", "seat0", 0);
    _ = interop.setenv("XDG_VTNR", tty_str.ptr, 0);
}

fn loginConv(
    num_msg: c_int,
    msg: ?[*]?*const interop.pam.pam_message,
    resp: ?*?[*]interop.pam.pam_response,
    appdata_ptr: ?*anyopaque,
) callconv(.C) c_int {
    const message_count: u32 = @intCast(num_msg);
    const messages = msg.?;

    const allocator = std.heap.c_allocator;
    const response = allocator.alloc(interop.pam.pam_response, message_count) catch return interop.pam.PAM_BUF_ERR;

    // Initialise allocated memory to 0
    // This ensures memory can be freed by pam on success
    @memset(response, std.mem.zeroes(interop.pam.pam_response));

    var username: ?[:0]u8 = null;
    var password: ?[:0]u8 = null;
    var status: c_int = interop.pam.PAM_SUCCESS;

    for (0..message_count) |i| set_credentials: {
        switch (messages[i].?.msg_style) {
            interop.pam.PAM_PROMPT_ECHO_ON => {
                const data: [*][*:0]u8 = @ptrCast(@alignCast(appdata_ptr));
                username = allocator.dupeZ(u8, std.mem.span(data[0])) catch {
                    status = interop.pam.PAM_BUF_ERR;
                    break :set_credentials;
                };
                response[i].resp = username.?.ptr;
            },
            interop.pam.PAM_PROMPT_ECHO_OFF => {
                const data: [*][*:0]u8 = @ptrCast(@alignCast(appdata_ptr));
                password = allocator.dupeZ(u8, std.mem.span(data[1])) catch {
                    status = interop.pam.PAM_BUF_ERR;
                    break :set_credentials;
                };
                response[i].resp = password.?.ptr;
            },
            interop.pam.PAM_ERROR_MSG => {
                status = interop.pam.PAM_CONV_ERR;
                break :set_credentials;
            },
            else => {},
        }
    }

    if (status != interop.pam.PAM_SUCCESS) {
        // Memory is freed by pam otherwise
        allocator.free(response);
        if (username != null) allocator.free(username.?);
        if (password != null) allocator.free(password.?);
    } else {
        resp.?.* = response.ptr;
    }

    return status;
}

fn resetTerminal(shell: [*:0]const u8, term_reset_cmd: [:0]const u8) !void {
    const pid = try std.posix.fork();
    if (pid == 0) {
        const args = [_:null]?[*:0]const u8{ shell, "-c", term_reset_cmd };
        std.posix.execveZ(shell, &args, std.c.environ) catch {};
        std.process.exit(1);
    }

    _ = std.posix.waitpid(pid, 0);
}

fn getFreeDisplay() !u8 {
    var buf: [15]u8 = undefined;
    var i: u8 = 0;
    while (i < 200) : (i += 1) {
        const xlock = try std.fmt.bufPrint(&buf, "/tmp/.X{d}-lock", .{i});
        std.posix.access(xlock, std.posix.F_OK) catch break;
    }
    return i;
}

fn getXPid(display_num: u8) !i32 {
    var buf: [15]u8 = undefined;
    const file_name = try std.fmt.bufPrint(&buf, "/tmp/.X{d}-lock", .{display_num});
    const file = try std.fs.openFileAbsolute(file_name, .{});
    defer file.close();

    var file_buf: [20]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&file_buf);

    _ = try file.reader().streamUntilDelimiter(fbs.writer(), '\n', 20);
    const line = fbs.getWritten();

    return std.fmt.parseInt(i32, std.mem.trim(u8, line, " "), 10);
}

fn createXauthFile(pwd: [:0]const u8) ![:0]const u8 {
    var xauth_buf: [100]u8 = undefined;
    var xauth_dir: [:0]const u8 = undefined;
    const xdg_rt_dir = std.posix.getenv("XDG_RUNTIME_DIR");
    var xauth_file: []const u8 = "lyxauth";

    if (xdg_rt_dir == null) {
        const xdg_cfg_home = std.posix.getenv("XDG_CONFIG_HOME");
        var sb: std.c.Stat = undefined;
        if (xdg_cfg_home == null) {
            xauth_dir = try std.fmt.bufPrintZ(&xauth_buf, "{s}/.config", .{pwd});
            _ = std.c.stat(xauth_dir, &sb);
            const mode = sb.mode & std.posix.S.IFMT;
            if (mode == std.posix.S.IFDIR) {
                xauth_dir = try std.fmt.bufPrintZ(&xauth_buf, "{s}/ly", .{xauth_dir});
            } else {
                xauth_dir = pwd;
                xauth_file = ".lyxauth";
            }
        } else {
            xauth_dir = try std.fmt.bufPrintZ(&xauth_buf, "{s}/ly", .{xdg_cfg_home.?});
        }

        _ = std.c.stat(xauth_dir, &sb);
        const mode = sb.mode & std.posix.S.IFMT;
        if (mode != std.posix.S.IFDIR) {
            std.posix.mkdir(xauth_dir, 777) catch {
                xauth_dir = pwd;
                xauth_file = ".lyxauth";
            };
        }
    } else {
        xauth_dir = xdg_rt_dir.?;
    }

    // Trim trailing slashes
    var i = xauth_dir.len - 1;
    while (xauth_dir[i] == '/') i -= 1;
    const trimmed_xauth_dir = xauth_dir[0 .. i + 1];

    var buf: [256]u8 = undefined;
    const xauthority: [:0]u8 = try std.fmt.bufPrintZ(&buf, "{s}/{s}", .{ trimmed_xauth_dir, xauth_file });
    const file = try std.fs.createFileAbsoluteZ(xauthority, .{});
    file.close();

    return xauthority;
}

pub fn mcookie(cmd: [:0]const u8) ![32]u8 {
    const pipe = try std.posix.pipe();
    defer std.posix.close(pipe[1]);

    const output = std.fs.File{ .handle = pipe[0] };
    defer output.close();

    const pid = try std.posix.fork();
    if (pid == 0) {
        std.posix.close(pipe[0]);

        std.posix.dup2(pipe[1], std.posix.STDOUT_FILENO) catch std.process.exit(1);
        std.posix.close(pipe[1]);

        const args = [_:null]?[*:0]u8{};
        std.posix.execveZ(cmd.ptr, &args, std.c.environ) catch {};
        std.process.exit(1);
    }

    const result = std.posix.waitpid(pid, 0);

    if (result.status != 0) return error.McookieFailed;

    var buf: [32]u8 = undefined;
    const len = try output.read(&buf);
    if (len != 32) return error.McookieFailed;
    return buf;
}

fn xauth(display_name: [:0]u8, shell: [*:0]const u8, pw_dir: [*:0]const u8, xauth_cmd: []const u8, mcookie_cmd: [:0]const u8) !void {
    var pwd_buf: [100]u8 = undefined;
    const pwd = try std.fmt.bufPrintZ(&pwd_buf, "{s}", .{pw_dir});

    const xauthority = try createXauthFile(pwd);
    _ = interop.setenv("XAUTHORITY", xauthority, 1);
    _ = interop.setenv("DISPLAY", display_name, 1);

    const mcookie_output = try mcookie(mcookie_cmd);

    const pid = try std.posix.fork();
    if (pid == 0) {
        var cmd_buffer: [1024]u8 = undefined;
        const cmd_str = std.fmt.bufPrintZ(&cmd_buffer, "{s} add {s} . {s}", .{ xauth_cmd, display_name, mcookie_output }) catch std.process.exit(1);
        const args = [_:null]?[*:0]const u8{ shell, "-c", cmd_str };
        std.posix.execveZ(shell, &args, std.c.environ) catch {};
        std.process.exit(1);
    }

    const status = std.posix.waitpid(pid, 0);
    if (status.status != 0) return error.XauthFailed;
}

fn executeShellCmd(shell: [*:0]const u8) !void {
    const args = [_:null]?[*:0]const u8{shell};
    return std.posix.execveZ(shell, &args, std.c.environ);
}

fn executeWaylandCmd(shell: [*:0]const u8, wayland_cmd: []const u8, desktop_cmd: []const u8) !void {
    var cmd_buffer: [1024]u8 = undefined;
    const cmd_str = try std.fmt.bufPrintZ(&cmd_buffer, "{s} {s}", .{ wayland_cmd, desktop_cmd });
    const args = [_:null]?[*:0]const u8{ shell, "-c", cmd_str };
    return std.posix.execveZ(shell, &args, std.c.environ);
}

fn executeX11Cmd(shell: [*:0]const u8, pw_dir: [*:0]const u8, config: Config, desktop_cmd: []const u8, vt: []const u8) !void {
    const display_num = try getFreeDisplay();
    var buf: [5]u8 = undefined;
    const display_name = try std.fmt.bufPrintZ(&buf, ":{d}", .{display_num});
    try xauth(display_name, shell, pw_dir, config.xauth_cmd, config.mcookie_cmd);

    const pid = try std.posix.fork();
    if (pid == 0) {
        var cmd_buffer: [1024]u8 = undefined;
        const cmd_str = std.fmt.bufPrintZ(&cmd_buffer, "{s} {s} {s}", .{ config.x_cmd, display_name, vt }) catch std.process.exit(1);
        const args = [_:null]?[*:0]const u8{ shell, "-c", cmd_str };
        std.posix.execveZ(shell, &args, std.c.environ) catch {};
        std.process.exit(1);
    }

    var ok: c_int = undefined;
    var xcb: ?*interop.xcb.xcb_connection_t = null;
    while (ok != 0) {
        xcb = interop.xcb.xcb_connect(null, null);
        ok = interop.xcb.xcb_connection_has_error(xcb);
        std.posix.kill(pid, 0) catch |e| {
            if (e == error.ProcessNotFound and ok != 0) return error.XcbConnectionFailed;
        };
    }

    // X Server detaches from the process.
    // PID can be fetched from /tmp/X{d}.lock
    const x_pid = try getXPid(display_num);

    xorg_pid = try std.posix.fork();
    if (xorg_pid == 0) {
        var cmd_buffer: [1024]u8 = undefined;
        const cmd_str = std.fmt.bufPrintZ(&cmd_buffer, "{s} {s}", .{ config.x_cmd_setup, desktop_cmd }) catch std.process.exit(1);
        const args = [_:null]?[*:0]const u8{ shell, "-c", cmd_str };
        std.posix.execveZ(shell, &args, std.c.environ) catch {};
        std.process.exit(1);
    }

    // If we receive SIGTERM, clean up by killing the xorg_pid process
    const act = std.posix.Sigaction{
        .handler = .{ .handler = &xorgSignalHandler },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    try std.posix.sigaction(std.posix.SIG.TERM, &act, null);

    _ = std.posix.waitpid(xorg_pid, 0);
    interop.xcb.xcb_disconnect(xcb);

    std.posix.kill(x_pid, 0) catch return;
    std.posix.kill(x_pid, std.posix.SIG.TERM) catch {};

    var status: c_int = 0;
    _ = std.c.waitpid(x_pid, &status, 0);
}

fn addUtmpEntry(entry: *Utmp, username: [*:0]const u8, pid: c_int) !void {
    entry.ut_type = utmp.USER_PROCESS;
    entry.ut_pid = pid;

    var buf: [4096]u8 = undefined;
    const ttyname = try std.os.getFdPath(std.posix.STDIN_FILENO, &buf);

    var ttyname_buf: [32]u8 = undefined;
    _ = try std.fmt.bufPrintZ(&ttyname_buf, "{s}", .{ttyname["/dev/".len..]});

    entry.ut_line = ttyname_buf;
    entry.ut_id = ttyname_buf["tty".len..7].*;

    var username_buf: [32]u8 = undefined;
    _ = try std.fmt.bufPrintZ(&username_buf, "{s}", .{username});

    entry.ut_user = username_buf;

    var host: [256]u8 = undefined;
    host[0] = 0;
    entry.ut_host = host;

    var tv: std.c.timeval = undefined;
    _ = std.c.gettimeofday(&tv, null);

    entry.ut_tv = .{
        .tv_sec = @intCast(tv.tv_sec),
        .tv_usec = @intCast(tv.tv_usec),
    };
    entry.ut_addr_v6[0] = 0;

    utmp.setutent();
    _ = utmp.pututline(entry);
    utmp.endutent();
}

fn removeUtmpEntry(entry: *Utmp) void {
    entry.ut_type = utmp.DEAD_PROCESS;
    entry.ut_line[0] = 0;
    entry.ut_user[0] = 0;
    utmp.setutent();
    _ = utmp.pututline(entry);
    utmp.endutent();
}

fn pamDiagnose(status: c_int) anyerror {
    return switch (status) {
        interop.pam.PAM_ACCT_EXPIRED => return error.PamAccountExpired,
        interop.pam.PAM_AUTH_ERR => return error.PamAuthError,
        interop.pam.PAM_AUTHINFO_UNAVAIL => return error.PamAuthInfoUnavailable,
        interop.pam.PAM_BUF_ERR => return error.PamBufferError,
        interop.pam.PAM_CRED_ERR => return error.PamCredentialsError,
        interop.pam.PAM_CRED_EXPIRED => return error.PamCredentialsExpired,
        interop.pam.PAM_CRED_INSUFFICIENT => return error.PamCredentialsInsufficient,
        interop.pam.PAM_CRED_UNAVAIL => return error.PamCredentialsUnavailable,
        interop.pam.PAM_MAXTRIES => return error.PamMaximumTries,
        interop.pam.PAM_NEW_AUTHTOK_REQD => return error.PamNewAuthTokenRequired,
        interop.pam.PAM_PERM_DENIED => return error.PamPermissionDenied,
        interop.pam.PAM_SESSION_ERR => return error.PamSessionError,
        interop.pam.PAM_SYSTEM_ERR => return error.PamSystemError,
        interop.pam.PAM_USER_UNKNOWN => return error.PamUserUnknown,
        else => return error.PamAbort,
    };
}
