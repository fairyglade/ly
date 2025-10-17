const std = @import("std");
const build_options = @import("build_options");
const builtin = @import("builtin");
const enums = @import("enums.zig");
const Environment = @import("Environment.zig");
const interop = @import("interop.zig");
const SharedError = @import("SharedError.zig");

const Md5 = std.crypto.hash.Md5;
const utmp = interop.utmp;
const Utmp = utmp.utmpx;

pub const AuthOptions = struct {
    tty: u8,
    service_name: [:0]const u8,
    path: ?[]const u8,
    session_log: ?[]const u8,
    xauth_cmd: []const u8,
    setup_cmd: []const u8,
    login_cmd: ?[]const u8,
    x_cmd: []const u8,
    session_pid: std.posix.pid_t,
};

var xorg_pid: std.posix.pid_t = 0;
pub fn xorgSignalHandler(i: c_int) callconv(.c) void {
    if (xorg_pid > 0) _ = std.c.kill(xorg_pid, i);
}

var child_pid: std.posix.pid_t = 0;
pub fn sessionSignalHandler(i: c_int) callconv(.c) void {
    if (child_pid > 0) _ = std.c.kill(child_pid, i);
}

pub fn authenticate(allocator: std.mem.Allocator, log_writer: *std.Io.Writer, options: AuthOptions, current_environment: Environment, login: []const u8, password: []const u8) !void {
    var tty_buffer: [3]u8 = undefined;
    const tty_str = try std.fmt.bufPrint(&tty_buffer, "{d}", .{options.tty});

    var pam_tty_buffer: [6]u8 = undefined;
    const pam_tty_str = try std.fmt.bufPrintZ(&pam_tty_buffer, "tty{d}", .{options.tty});

    // Set the XDG environment variables
    try setXdgEnv(allocator, tty_str, current_environment);

    // Open the PAM session
    const login_z = try allocator.dupeZ(u8, login);
    defer allocator.free(login_z);

    const password_z = try allocator.dupeZ(u8, password);
    defer allocator.free(password_z);

    var credentials = [_:null]?[*:0]const u8{ login_z, password_z };

    const conv = interop.pam.pam_conv{
        .conv = loginConv,
        .appdata_ptr = @ptrCast(&credentials),
    };
    var handle: ?*interop.pam.pam_handle = undefined;

    var status = interop.pam.pam_start(options.service_name, null, &conv, &handle);
    if (status != interop.pam.PAM_SUCCESS) return pamDiagnose(status);
    defer _ = interop.pam.pam_end(handle, status);

    // Set PAM_TTY as the current TTY. This is required in case it isn't being set by another PAM module
    status = interop.pam.pam_set_item(handle, interop.pam.PAM_TTY, pam_tty_str.ptr);
    if (status != interop.pam.PAM_SUCCESS) return pamDiagnose(status);

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

    var user_entry: interop.UsernameEntry = undefined;
    {
        defer interop.closePasswordDatabase();

        // Get password structure from username
        user_entry = interop.getUsernameEntry(login_z) orelse return error.GetPasswordNameFailed;
    }

    // Set user shell if it hasn't already been set
    if (user_entry.shell == null) interop.setUserShell(&user_entry);

    var shared_err = try SharedError.init();
    defer shared_err.deinit();

    child_pid = try std.posix.fork();
    if (child_pid == 0) {
        try log_writer.writeAll("starting session\n");
        try log_writer.flush();

        startSession(log_writer, allocator, options, tty_str, user_entry, handle, current_environment) catch |e| {
            shared_err.writeError(e);
            std.process.exit(1);
        };
        std.process.exit(0);
    }

    var entry = std.mem.zeroes(Utmp);

    {
        // If an error occurs here, we can send SIGTERM to the session
        errdefer cleanup: {
            std.posix.kill(child_pid, std.posix.SIG.TERM) catch break :cleanup;
            _ = std.posix.waitpid(child_pid, 0);
        }

        // If we receive SIGTERM, forward it to child_pid
        const act = std.posix.Sigaction{
            .handler = .{ .handler = &sessionSignalHandler },
            .mask = std.posix.sigemptyset(),
            .flags = 0,
        };
        std.posix.sigaction(std.posix.SIG.TERM, &act, null);

        try addUtmpEntry(&entry, user_entry.username.?, child_pid);
    }
    // Wait for the session to stop
    _ = std.posix.waitpid(child_pid, 0);

    removeUtmpEntry(&entry);

    if (shared_err.readError()) |err| return err;
}

fn startSession(
    log_writer: *std.Io.Writer,
    allocator: std.mem.Allocator,
    options: AuthOptions,
    tty_str: []u8,
    user_entry: interop.UsernameEntry,
    handle: ?*interop.pam.pam_handle,
    current_environment: Environment,
) !void {
    // Set the user's GID & PID
    try interop.setUserContext(allocator, user_entry);

    // Set up the environment
    try initEnv(allocator, user_entry, options.path);

    // Reset the XDG environment variables
    try setXdgEnv(allocator, tty_str, current_environment);

    // Set the PAM variables
    const pam_env_vars: ?[*:null]?[*:0]u8 = interop.pam.pam_getenvlist(handle);
    if (pam_env_vars == null) return error.GetEnvListFailed;

    const env_list = std.mem.span(pam_env_vars.?);
    for (env_list) |env_var| try interop.putEnvironmentVariable(env_var);

    // Change to the user's home directory
    std.posix.chdir(user_entry.home.?) catch return error.ChangeDirectoryFailed;

    // Signal to the session process to give up control on the TTY
    std.posix.kill(options.session_pid, std.posix.SIG.CHLD) catch return error.TtyControlTransferFailed;

    // Execute what the user requested
    switch (current_environment.display_server) {
        .wayland, .shell, .custom => try executeCmd(log_writer, allocator, user_entry.shell.?, options, current_environment.is_terminal, current_environment.cmd),
        .xinitrc, .x11 => if (build_options.enable_x11_support) {
            var vt_buf: [5]u8 = undefined;
            const vt = try std.fmt.bufPrint(&vt_buf, "vt{d}", .{options.tty});
            try executeX11Cmd(log_writer, allocator, user_entry.shell.?, user_entry.home.?, options, current_environment.cmd orelse "", vt);
        },
    }
}

fn initEnv(allocator: std.mem.Allocator, entry: interop.UsernameEntry, path_env: ?[]const u8) !void {
    if (entry.home) |home| {
        try interop.setEnvironmentVariable(allocator, "HOME", home, true);
        try interop.setEnvironmentVariable(allocator, "PWD", home, true);
    } else return error.NoHomeDirectory;

    try interop.setEnvironmentVariable(allocator, "SHELL", entry.shell.?, true);
    try interop.setEnvironmentVariable(allocator, "USER", entry.username.?, true);
    try interop.setEnvironmentVariable(allocator, "LOGNAME", entry.username.?, true);

    if (path_env) |path| {
        interop.setEnvironmentVariable(allocator, "PATH", path, true) catch return error.SetPathFailed;
    }
}

fn setXdgEnv(allocator: std.mem.Allocator, tty_str: []u8, environment: Environment) !void {
    try interop.setEnvironmentVariable(allocator, "XDG_SESSION_TYPE", switch (environment.display_server) {
        .wayland => "wayland",
        .shell => "tty",
        .xinitrc, .x11 => "x11",
        .custom => if (environment.is_terminal) "tty" else "unspecified",
    }, false);

    // The "/run/user/%d" directory is not available on FreeBSD. It is much
    // better to stick to the defaults and let applications using
    // XDG_RUNTIME_DIR to fall back to directories inside user's home
    // directory.
    if (builtin.os.tag != .freebsd) {
        const uid = std.posix.getuid();
        var uid_buffer: [32]u8 = undefined; // No UID can be larger than this
        const uid_str = try std.fmt.bufPrint(&uid_buffer, "/run/user/{d}", .{uid});

        try interop.setEnvironmentVariable(allocator, "XDG_RUNTIME_DIR", uid_str, false);
    }

    if (environment.xdg_desktop_names) |xdg_desktop_names| try interop.setEnvironmentVariable(allocator, "XDG_CURRENT_DESKTOP", xdg_desktop_names, false);
    try interop.setEnvironmentVariable(allocator, "XDG_SESSION_CLASS", "user", false);
    try interop.setEnvironmentVariable(allocator, "XDG_SESSION_ID", "1", false);
    if (environment.xdg_session_desktop) |desktop_name| try interop.setEnvironmentVariable(allocator, "XDG_SESSION_DESKTOP", desktop_name, false);
    try interop.setEnvironmentVariable(allocator, "XDG_SEAT", "seat0", false);
    try interop.setEnvironmentVariable(allocator, "XDG_VTNR", tty_str, false);
}

fn loginConv(
    num_msg: c_int,
    msg: ?[*]?*const interop.pam.pam_message,
    resp: ?*?[*]interop.pam.pam_response,
    appdata_ptr: ?*anyopaque,
) callconv(.c) c_int {
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
                response[i].resp = username.?;
            },
            interop.pam.PAM_PROMPT_ECHO_OFF => {
                const data: [*][*:0]u8 = @ptrCast(@alignCast(appdata_ptr));
                password = allocator.dupeZ(u8, std.mem.span(data[1])) catch {
                    status = interop.pam.PAM_BUF_ERR;
                    break :set_credentials;
                };
                response[i].resp = password.?;
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
        if (username) |str| allocator.free(str);
        if (password) |str| allocator.free(str);
    } else {
        resp.?.* = response.ptr;
    }

    return status;
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

    var file_buffer: [32]u8 = undefined;
    var file_reader = file.reader(&file_buffer);
    var reader = &file_reader.interface;

    var buffer: [20]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);

    const written = try reader.streamDelimiter(&writer, '\n');
    return std.fmt.parseInt(i32, std.mem.trim(u8, buffer[0..written], " "), 10);
}

fn createXauthFile(pwd: []const u8) ![]const u8 {
    var xauth_buf: [100]u8 = undefined;
    var xauth_dir: []const u8 = undefined;
    const xdg_rt_dir = std.posix.getenv("XDG_RUNTIME_DIR");
    var xauth_file: []const u8 = "lyxauth";

    if (xdg_rt_dir == null) no_rt_dir: {
        const xdg_cfg_home = std.posix.getenv("XDG_CONFIG_HOME");
        if (xdg_cfg_home == null) no_cfg_home: {
            xauth_dir = try std.fmt.bufPrint(&xauth_buf, "{s}/.config", .{pwd});

            var dir = std.fs.cwd().openDir(xauth_dir, .{}) catch {
                // xauth_dir isn't a directory
                xauth_dir = pwd;
                xauth_file = ".lyxauth";
                break :no_cfg_home;
            };
            dir.close();

            // xauth_dir is a directory, use it to store Xauthority
            xauth_dir = try std.fmt.bufPrint(&xauth_buf, "{s}/ly", .{xauth_dir});
        } else {
            xauth_dir = try std.fmt.bufPrint(&xauth_buf, "{s}/ly", .{xdg_cfg_home.?});
        }

        const file = std.fs.cwd().openFile(xauth_dir, .{}) catch break :no_rt_dir;
        file.close();

        // xauth_dir is a file, create the parent directory
        std.posix.mkdir(xauth_dir, 777) catch {
            xauth_dir = pwd;
            xauth_file = ".lyxauth";
        };
    } else {
        xauth_dir = xdg_rt_dir.?;
    }

    // Trim trailing slashes
    var i = xauth_dir.len - 1;
    while (xauth_dir[i] == '/') i -= 1;
    const trimmed_xauth_dir = xauth_dir[0 .. i + 1];

    var buf: [256]u8 = undefined;
    const xauthority: []u8 = try std.fmt.bufPrint(&buf, "{s}/{s}", .{ trimmed_xauth_dir, xauth_file });
    const file = try std.fs.createFileAbsolute(xauthority, .{});
    file.close();

    return xauthority;
}

fn mcookie() [Md5.digest_length * 2]u8 {
    var buf: [4096]u8 = undefined;
    std.crypto.random.bytes(&buf);

    var out: [Md5.digest_length]u8 = undefined;
    Md5.hash(&buf, &out, .{});

    return std.fmt.bytesToHex(&out, .lower);
}

fn xauth(log_writer: *std.Io.Writer, allocator: std.mem.Allocator, display_name: []u8, shell: [*:0]const u8, home: []const u8, options: AuthOptions) !void {
    const xauthority = try createXauthFile(home);
    try interop.setEnvironmentVariable(allocator, "XAUTHORITY", xauthority, true);
    try interop.setEnvironmentVariable(allocator, "DISPLAY", display_name, true);

    const magic_cookie = mcookie();

    const pid = try std.posix.fork();
    if (pid == 0) {
        var cmd_buffer: [1024]u8 = undefined;
        const cmd_str = std.fmt.bufPrintZ(&cmd_buffer, "{s} add {s} . {s}", .{ options.xauth_cmd, display_name, magic_cookie }) catch std.process.exit(1);

        const args = [_:null]?[*:0]const u8{ shell, "-c", cmd_str };
        std.posix.execveZ(shell, &args, std.c.environ) catch {};
        std.process.exit(1);
    }

    const status = std.posix.waitpid(pid, 0);
    if (status.status != 0) {
        try log_writer.print("xauth command failed with status {d}\n", .{status.status});
        return error.XauthFailed;
    }
}

fn executeX11Cmd(log_writer: *std.Io.Writer, allocator: std.mem.Allocator, shell: []const u8, home: []const u8, options: AuthOptions, desktop_cmd: []const u8, vt: []const u8) !void {
    try log_writer.writeAll("[x11] getting free display\n");
    try log_writer.flush();

    const display_num = try getFreeDisplay();
    var buf: [4]u8 = undefined;
    const display_name = try std.fmt.bufPrint(&buf, ":{d}", .{display_num});

    const shell_z = try allocator.dupeZ(u8, shell);
    defer allocator.free(shell_z);

    try log_writer.writeAll("[x11] creating xauth file\n");
    try log_writer.flush();

    try xauth(log_writer, allocator, display_name, shell_z, home, options);

    try log_writer.writeAll("[x11] starting x server\n");
    try log_writer.flush();

    const pid = try std.posix.fork();
    if (pid == 0) {
        var cmd_buffer: [1024]u8 = undefined;
        const cmd_str = std.fmt.bufPrintZ(&cmd_buffer, "{s} {s} {s}", .{ options.x_cmd, display_name, vt }) catch std.process.exit(1);

        const args = [_:null]?[*:0]const u8{ shell_z, "-c", cmd_str };
        std.posix.execveZ(shell_z, &args, std.c.environ) catch {};
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

    try log_writer.writeAll("[x11] getting x server pid\n");
    try log_writer.flush();

    // X Server detaches from the process.
    // PID can be fetched from /tmp/X{d}.lock
    const x_pid = try getXPid(display_num);

    try log_writer.writeAll("[x11] launching environment\n");
    try log_writer.flush();

    xorg_pid = try std.posix.fork();
    if (xorg_pid == 0) {
        var cmd_buffer: [1024]u8 = undefined;
        const cmd_str = std.fmt.bufPrintZ(&cmd_buffer, "{s} {s} {s}", .{ options.setup_cmd, options.login_cmd orelse "", desktop_cmd }) catch std.process.exit(1);

        const args = [_:null]?[*:0]const u8{ shell_z, "-c", cmd_str };
        std.posix.execveZ(shell_z, &args, std.c.environ) catch {};
        std.process.exit(1);
    }

    // If we receive SIGTERM, clean up by killing the xorg_pid process
    const act = std.posix.Sigaction{
        .handler = .{ .handler = &xorgSignalHandler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.TERM, &act, null);

    _ = std.posix.waitpid(xorg_pid, 0);
    interop.xcb.xcb_disconnect(xcb);

    // TODO: Find a more robust way to ensure that X has been terminated (pidfds?)
    std.posix.kill(x_pid, std.posix.SIG.TERM) catch {};
    std.Thread.sleep(std.time.ns_per_s * 1); // Wait 1 second before sending SIGKILL
    std.posix.kill(x_pid, std.posix.SIG.KILL) catch return;

    _ = std.posix.waitpid(x_pid, 0);
}

fn executeCmd(log_writer: *std.Io.Writer, allocator: std.mem.Allocator, shell: []const u8, options: AuthOptions, is_terminal: bool, exec_cmd: ?[]const u8) !void {
    var maybe_log_file: ?std.fs.File = null;
    if (!is_terminal) {
        // For custom desktop entries, the "Terminal" value here determines if
        // we redirect standard output & error or not. That is, we redirect only
        // if it's equal to false (so if it's not running in a TTY).
        if (options.session_log) |log_path| {
            maybe_log_file = try redirectStandardStreams(log_writer, log_path, true);
        }
    }
    defer if (maybe_log_file) |log_file| log_file.close();

    const shell_z = try allocator.dupeZ(u8, shell);
    defer allocator.free(shell_z);

    var cmd_buffer: [1024]u8 = undefined;
    const cmd_str = try std.fmt.bufPrintZ(&cmd_buffer, "{s} {s} {s}", .{ options.setup_cmd, options.login_cmd orelse "", exec_cmd orelse shell });

    const args = [_:null]?[*:0]const u8{ shell_z, "-c", cmd_str };
    return std.posix.execveZ(shell_z, &args, std.c.environ);
}

fn redirectStandardStreams(log_writer: *std.Io.Writer, session_log: []const u8, create: bool) !std.fs.File {
    const log_file = if (create) (std.fs.cwd().createFile(session_log, .{ .mode = 0o666 }) catch |err| {
        try log_writer.print("failed to create new session log file: {s}\n", .{@errorName(err)});
        return err;
    }) else (std.fs.cwd().openFile(session_log, .{ .mode = .read_write }) catch |err| {
        try log_writer.print("failed to open existing session log file: {s}\n", .{@errorName(err)});
        return err;
    });

    try std.posix.dup2(std.posix.STDOUT_FILENO, std.posix.STDERR_FILENO);
    try std.posix.dup2(log_file.handle, std.posix.STDOUT_FILENO);

    return log_file;
}

fn addUtmpEntry(entry: *Utmp, username: []const u8, pid: c_int) !void {
    entry.ut_type = utmp.USER_PROCESS;
    entry.ut_pid = pid;

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const tty_path = try std.os.getFdPath(std.posix.STDIN_FILENO, &buf);

    // Get the TTY name (i.e. without the /dev/ prefix)
    var ttyname_buf: [@sizeOf(@TypeOf(entry.ut_line))]u8 = undefined;
    const ttyname = try std.fmt.bufPrintZ(&ttyname_buf, "{s}", .{tty_path["/dev/".len..]});

    entry.ut_line = ttyname_buf;
    // Get the TTY ID (i.e. without the tty prefix) and truncate it to the size
    // of ut_id if necessary
    entry.ut_id = ttyname["tty".len..(@sizeOf(@TypeOf(entry.ut_id)) + "tty".len)].*;

    var username_buf: [@sizeOf(@TypeOf(entry.ut_user))]u8 = undefined;
    _ = try std.fmt.bufPrintZ(&username_buf, "{s}", .{username});

    entry.ut_user = username_buf;

    var host: [@sizeOf(@TypeOf(entry.ut_host))]u8 = undefined;
    host[0] = 0;
    entry.ut_host = host;

    const time = try interop.getTimeOfDay();

    entry.ut_tv = .{
        .tv_sec = @intCast(time.seconds),
        .tv_usec = @intCast(time.microseconds),
    };

    // FreeBSD doesn't have this field
    if (builtin.os.tag == .linux) {
        entry.ut_addr_v6[0] = 0;
    }

    utmp.setutxent();
    _ = utmp.pututxline(entry);
    utmp.endutxent();
}

fn removeUtmpEntry(entry: *Utmp) void {
    entry.ut_type = utmp.DEAD_PROCESS;
    entry.ut_line[0] = 0;
    entry.ut_user[0] = 0;
    utmp.setutxent();
    _ = utmp.pututxline(entry);
    utmp.endutxent();
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
