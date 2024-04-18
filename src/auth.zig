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

var xorg_pid: std.os.pid_t = 0;
pub fn xorgSignalHandler(i: c_int) callconv(.C) void {
    if (xorg_pid > 0) _ = std.c.kill(xorg_pid, i);
}

var child_pid: std.os.pid_t = 0;
pub fn sessionSignalHandler(i: c_int) callconv(.C) void {
    if (child_pid > 0) _ = std.c.kill(child_pid, i);
}

pub fn authenticate(config: Config, desktop: Desktop, login: [:0]const u8, password: [:0]const u8) !void {
    var tty_buffer: [2]u8 = undefined;
    const tty_str = try std.fmt.bufPrintZ(&tty_buffer, "{d}", .{config.tty});
    const current_environment = desktop.environments.items[desktop.current];

    // Set the XDG environment variables
    setXdgSessionEnv(current_environment.display_server);
    try setXdgEnv(tty_str, current_environment.name, current_environment.xdg_name);

    // Open the PAM session
    var credentials = [2:null][*c]const u8{ login, password };

    const conv = interop.pam.pam_conv{
        .conv = loginConv,
        .appdata_ptr = @ptrCast(&credentials),
    };
    var handle: ?*interop.pam.pam_handle = undefined;

    var status = interop.pam.pam_start(config.service_name.ptr, null, &conv, &handle);
    if (status != interop.pam.PAM_SUCCESS) return pamDiagnose(status);

    // Do the PAM routine
    status = interop.pam.pam_authenticate(handle, 0);
    if (status != interop.pam.PAM_SUCCESS) return pamDiagnose(status);

    status = interop.pam.pam_acct_mgmt(handle, 0);
    if (status != interop.pam.PAM_SUCCESS) return pamDiagnose(status);

    status = interop.pam.pam_setcred(handle, 0);
    if (status != interop.pam.PAM_SUCCESS) return pamDiagnose(status);

    status = interop.pam.pam_open_session(handle, 0);
    if (status != interop.pam.PAM_SUCCESS) return pamDiagnose(status);

    // Get password structure from username
    const maybe_pwd = interop.getpwnam(login.ptr);
    interop.endpwent();

    if (maybe_pwd == null) return error.GetPasswordNameFailed;
    const pwd = maybe_pwd.?;

    // Set user shell if it hasn't already been set
    if (pwd.pw_shell[0] == 0) {
        interop.setusershell();
        defer interop.endusershell();

        const shell = interop.getusershell();

        if (shell[0] != 0) {
            var index: usize = 0;

            while (true) : (index += 1) {
                const char = shell[index];
                pwd.pw_shell[index] = char;

                if (char == 0) break;
            }
        }
    }

    var shared_err = try SharedError.init();
    defer shared_err.deinit();

    child_pid = try std.os.fork();
    if (child_pid == 0) {
        // Set the user information
        status = interop.initgroups(pwd.pw_name, pwd.pw_gid);
        if (status != 0) {
            shared_err.writeError(error.GroupInitializationFailed);
            std.os.exit(1);
        }

        status = std.c.setgid(pwd.pw_gid);
        if (status != 0) {
            shared_err.writeError(error.SetUserGidFailed);
            std.os.exit(1);
        }

        status = std.c.setuid(pwd.pw_uid);
        if (status != 0) {
            shared_err.writeError(error.SetUserUidFailed);
            std.os.exit(1);
        }

        // Set up the environment
        initEnv(pwd, config.path) catch |e| {
            shared_err.writeError(e);
            std.os.exit(1);
        };

        // Set the PAM variables
        const pam_env_vars = interop.pam.pam_getenvlist(handle);
        var index: usize = 0;

        while (true) : (index += 1) {
            const pam_env_var = pam_env_vars[index];
            if (pam_env_var == null) break;

            _ = interop.putenv(pam_env_var);
        }

        // Execute what the user requested
        status = interop.chdir(pwd.pw_dir);
        if (status != 0) {
            shared_err.writeError(error.ChangeDirectoryFailed);
            std.os.exit(1);
        }

        resetTerminal(pwd.pw_shell, config.term_reset_cmd) catch |e| {
            shared_err.writeError(e);
            std.os.exit(1);
        };

        switch (current_environment.display_server) {
            .wayland => executeWaylandCmd(pwd.pw_shell, config.wayland_cmd, current_environment.cmd) catch |e| {
                shared_err.writeError(e);
                std.os.exit(1);
            },
            .shell => executeShellCmd(pwd.pw_shell),
            .xinitrc, .x11 => {
                var vt_buf: [5]u8 = undefined;
                const vt = std.fmt.bufPrint(&vt_buf, "vt{d}", .{config.tty}) catch |e| {
                    shared_err.writeError(e);
                    std.os.exit(1);
                };
                executeX11Cmd(pwd.pw_shell, pwd.pw_dir, config, current_environment.cmd, vt) catch |e| {
                    shared_err.writeError(e);
                    std.os.exit(1);
                };
            },
        }

        std.os.exit(0);
    }

    var entry: Utmp = std.mem.zeroes(Utmp);
    addUtmpEntry(&entry, pwd.pw_name, child_pid) catch {};

    // If we receive SIGTERM, forward it to child_pid
    const act = std.os.Sigaction{
        .handler = .{ .handler = &sessionSignalHandler },
        .mask = std.os.empty_sigset,
        .flags = 0,
    };
    try std.os.sigaction(std.os.SIG.TERM, &act, null);

    // Wait for the session to stop
    _ = std.os.waitpid(child_pid, 0);

    removeUtmpEntry(&entry);

    try resetTerminal(pwd.pw_shell, config.term_reset_cmd);

    // Close the PAM session
    status = interop.pam.pam_close_session(handle, 0);
    if (status != 0) return pamDiagnose(status);

    status = interop.pam.pam_setcred(handle, 0);
    if (status != 0) return pamDiagnose(status);

    status = interop.pam.pam_end(handle, status);
    if (status != 0) return pamDiagnose(status);

    if (shared_err.readError()) |err| return err;
}

fn initEnv(pwd: *interop.passwd, path_env: ?[:0]const u8) !void {
    const term_env = std.os.getenv("TERM");

    if (term_env) |term| _ = interop.setenv("TERM", term, 1);
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

fn setXdgEnv(tty_str: [:0]u8, desktop_name: [:0]const u8, desktop_names: [:0]const u8) !void {
    const uid = interop.getuid();
    var uid_buffer: [10 + @sizeOf(u32) + 1]u8 = undefined;
    const uid_str = try std.fmt.bufPrintZ(&uid_buffer, "/run/user/{d}", .{uid});

    _ = interop.setenv("XDG_CURRENT_DESKTOP", desktop_names.ptr, 0);
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

    var username: ?[:0]u8 = null;
    var password: ?[:0]u8 = null;
    var status: c_int = interop.pam.PAM_SUCCESS;

    for (0..message_count) |i| set_credentials: {
        switch (messages[i].?.msg_style) {
            interop.pam.PAM_PROMPT_ECHO_ON => {
                const data: [*][*:0]u8 = @ptrCast(@alignCast(appdata_ptr));
                username = allocator.dupeZ(u8, std.mem.span(data[0])) catch return interop.pam.PAM_BUF_ERR;
                response[i].resp = username.?.ptr;
            },
            interop.pam.PAM_PROMPT_ECHO_OFF => {
                const data: [*][*:0]u8 = @ptrCast(@alignCast(appdata_ptr));
                password = allocator.dupeZ(u8, std.mem.span(data[1])) catch return interop.pam.PAM_BUF_ERR;
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
    const pid = try std.os.fork();

    if (pid == 0) {
        _ = interop.execl(shell, shell, "-c", term_reset_cmd.ptr, @as([*c]const u8, 0));
        std.os.exit(0);
    }

    _ = std.os.waitpid(pid, 0);
}

fn getFreeDisplay() !u8 {
    var buf: [15]u8 = undefined;
    var i: u8 = 0;
    while (i < 200) : (i += 1) {
        const xlock = try std.fmt.bufPrint(&buf, "/tmp/.X{d}-lock", .{i});
        std.os.access(xlock, std.os.F_OK) catch break;
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
    var xdg_rt_dir = std.os.getenv("XDG_RUNTIME_DIR");
    var xauth_file: []const u8 = "lyxauth";

    if (xdg_rt_dir == null) {
        const xdg_cfg_home = std.os.getenv("XDG_CONFIG_HOME");
        var sb: std.c.Stat = undefined;
        if (xdg_cfg_home == null) {
            xauth_dir = try std.fmt.bufPrintZ(&xauth_buf, "{s}/.config", .{pwd});
            _ = std.c.stat(xauth_dir, &sb);
            const mode = sb.mode & std.os.S.IFMT;
            if (mode == std.os.S.IFDIR) {
                xauth_dir = try std.fmt.bufPrintZ(&xauth_buf, "{s}/ly", .{xauth_dir});
            } else {
                xauth_dir = pwd;
                xauth_file = ".lyxauth";
            }
        } else {
            xauth_dir = try std.fmt.bufPrintZ(&xauth_buf, "{s}/ly", .{xdg_cfg_home.?});
        }

        _ = std.c.stat(xauth_dir, &sb);
        const mode = sb.mode & std.os.S.IFMT;
        if (mode != std.os.S.IFDIR) {
            std.os.mkdir(xauth_dir, 777) catch {
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
    const file = try std.fs.createFileAbsolute(xauthority, .{});
    file.close();

    return xauthority;
}

fn xauth(display_name: [:0]u8, shell: [*:0]const u8, pw_dir: [*:0]const u8, xauth_cmd: []const u8, mcookie_cmd: []const u8) !void {
    var pwd_buf: [100]u8 = undefined;
    var pwd = try std.fmt.bufPrintZ(&pwd_buf, "{s}", .{pw_dir});

    const xauthority = try createXauthFile(pwd);
    _ = interop.setenv("XAUTHORITY", xauthority, 1);
    _ = interop.setenv("DISPLAY", display_name, 1);

    const pid = try std.os.fork();
    if (pid == 0) {
        var cmd_buffer: [1024]u8 = undefined;
        const cmd_str = std.fmt.bufPrintZ(&cmd_buffer, "{s} add {s} . $({s})", .{ xauth_cmd, display_name, mcookie_cmd }) catch std.os.exit(1);
        _ = interop.execl(shell, shell, "-c", cmd_str.ptr, @as([*c]const u8, 0));
        std.os.exit(0);
    }

    _ = std.os.waitpid(pid, 0);
}

fn executeWaylandCmd(shell: [*:0]const u8, wayland_cmd: []const u8, desktop_cmd: []const u8) !void {
    var cmd_buffer: [1024]u8 = undefined;

    const cmd_str = try std.fmt.bufPrintZ(&cmd_buffer, "{s} {s}", .{ wayland_cmd, desktop_cmd });
    _ = interop.execl(shell, shell, "-c", cmd_str.ptr, @as([*c]const u8, 0));
}

fn executeX11Cmd(shell: [*:0]const u8, pw_dir: [*:0]const u8, config: Config, desktop_cmd: []const u8, vt: []const u8) !void {
    const display_num = try getFreeDisplay();
    var buf: [5]u8 = undefined;
    var display_name = try std.fmt.bufPrintZ(&buf, ":{d}", .{display_num});
    try xauth(display_name, shell, pw_dir, config.xauth_cmd, config.mcookie_cmd);

    const pid = try std.os.fork();
    if (pid == 0) {
        var cmd_buffer: [1024]u8 = undefined;
        const cmd_str = std.fmt.bufPrintZ(&cmd_buffer, "{s} {s} {s}", .{ config.x_cmd, display_name, vt }) catch std.os.exit(1);
        _ = interop.execl(shell, shell, "-c", cmd_str.ptr, @as([*c]const u8, 0));
        std.os.exit(0);
    }

    var status: c_int = 0;
    var ok: c_int = undefined;
    var xcb: ?*interop.xcb.xcb_connection_t = null;
    while (ok != 0) {
        xcb = interop.xcb.xcb_connect(null, null);
        ok = interop.xcb.xcb_connection_has_error(xcb);
        status = std.c.kill(pid, 0);
        if (std.os.errno(status) == .SRCH and ok != 0) return;
    }

    // X Server detaches from the process.
    // PID can be fetched from /tmp/X{d}.lock
    const x_pid = try getXPid(display_num);

    xorg_pid = try std.os.fork();
    if (xorg_pid == 0) {
        var cmd_buffer: [1024]u8 = undefined;
        const cmd_str = std.fmt.bufPrintZ(&cmd_buffer, "{s} {s}", .{ config.x_cmd_setup, desktop_cmd }) catch std.os.exit(1);
        _ = interop.execl(shell, shell, "-c", cmd_str.ptr, @as([*c]const u8, 0));
        std.os.exit(0);
    }

    // If we receive SIGTERM, clean up by killing the xorg_pid process
    const act = std.os.Sigaction{
        .handler = .{ .handler = &xorgSignalHandler },
        .mask = std.os.empty_sigset,
        .flags = 0,
    };
    try std.os.sigaction(std.os.SIG.TERM, &act, null);

    _ = std.os.waitpid(xorg_pid, 0);
    interop.xcb.xcb_disconnect(xcb);

    status = std.c.kill(x_pid, 0);
    if (std.os.errno(status) != .SRCH) {
        _ = std.c.kill(x_pid, std.os.SIG.TERM);
        _ = std.c.waitpid(x_pid, &status, 0);
    }
}

fn executeShellCmd(shell: [*:0]const u8) void {
    _ = interop.execl(shell, shell, @as([*c]const u8, 0));
}

fn addUtmpEntry(entry: *Utmp, username: [*:0]const u8, pid: c_int) !void {
    entry.ut_type = utmp.USER_PROCESS;
    entry.ut_pid = pid;

    var buf: [4096]u8 = undefined;
    const ttyname = try std.os.getFdPath(0, &buf);

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
