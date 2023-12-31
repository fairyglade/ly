const std = @import("std");
const enums = @import("enums.zig");
const interop = @import("interop.zig");
const TerminalBuffer = @import("tui/TerminalBuffer.zig");
const Desktop = @import("tui/components/Desktop.zig");
const Text = @import("tui/components/Text.zig");
const Allocator = std.mem.Allocator;

var login_conv_allocator: Allocator = undefined;

pub fn authenticate(
    allocator: Allocator,
    tty: u8,
    desktop: Desktop,
    login: Text,
    password: *Text,
    service_name: []const u8,
    path: []const u8,
    term_reset_cmd: []const u8,
    wayland_cmd: []const u8,
) !void {
    login_conv_allocator = allocator;

    const uid = interop.getuid();

    var tty_buffer = std.mem.zeroes([@sizeOf(u8) + 1]u8);
    var uid_buffer = std.mem.zeroes([10 + @sizeOf(u32) + 1]u8);

    const tty_str = try std.fmt.bufPrintZ(&tty_buffer, "{d}", .{tty});
    const uid_str = try std.fmt.bufPrintZ(&uid_buffer, "/run/user/{d}", .{uid});
    const current_environment = desktop.environments.items[desktop.current];

    // Set the XDG environment variables
    setXdgSessionEnv(current_environment.display_server);
    try setXdgEnv(allocator, tty_str, uid_str, current_environment.xdg_name);

    // Open the PAM session
    const login_text_z = try allocator.dupeZ(u8, login.text.items);
    defer allocator.free(login_text_z);

    const password_text_z = try allocator.dupeZ(u8, password.text.items);
    defer allocator.free(password_text_z);

    var credentials: [*c][*c]const u8 = undefined;
    credentials[0] = login_text_z.ptr;
    credentials[1] = password_text_z.ptr;
    credentials[2] = 0;

    const conv = interop.pam.pam_conv{
        .conv = loginConv,
        .appdata_ptr = @ptrCast(&credentials),
    };
    var handle: ?*interop.pam.pam_handle = undefined;

    const service_name_z = try allocator.dupeZ(u8, service_name);
    defer allocator.free(service_name_z);

    var status = interop.pam.pam_start(service_name_z.ptr, null, &conv, &handle);
    defer status = interop.pam.pam_end(handle, status);

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

    // Clear the password
    password.clear();

    // Get password structure from username
    const maybe_pwd = interop.getpwnam(login_text_z.ptr);
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

    // Restore the previous terminal mode
    interop.termbox.tb_clear();
    interop.termbox.tb_present();
    interop.termbox.tb_shutdown();

    const pid = std.c.fork();

    if (pid == 0) {
        // Set the user information
        status = interop.initgroups(pwd.pw_name, pwd.pw_gid);
        if (status != 0) return error.GroupInitializationFailed;

        status = std.c.setgid(pwd.pw_gid);
        if (status != 0) return error.SetUserGidFailed;

        status = std.c.setuid(pwd.pw_uid);
        if (status != 0) return error.SetUserUidFailed;

        // Set up the environment (this clears the currently set one)
        try initEnv(allocator, pwd, path);

        // Reset the XDG environment variables from before
        setXdgSessionEnv(current_environment.display_server);
        try setXdgEnv(allocator, tty_str, uid_str, current_environment.xdg_name);

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
        if (status != 0) return error.ChangeDirectoryFailed;

        try resetTerminal(allocator, pwd.pw_shell, term_reset_cmd);

        switch (current_environment.display_server) {
            .wayland => try executeWaylandCmd(pwd.pw_shell, wayland_cmd, current_environment.cmd),
            .shell => executeShellCmd(pwd.pw_shell),
            .xinitrc, .x11 => {
                // TODO
            },
        }

        std.os.exit(0);
    }

    // TODO: Add UTMP entry

    // Wait for the session to stop
    _ = std.c.waitpid(pid, &status, 0);
    // TODO: Remove UTMP entry

    try resetTerminal(allocator, pwd.pw_shell, term_reset_cmd);

    // Re-initialize termbox
    _ = interop.termbox.tb_init();
    _ = interop.termbox.tb_select_output_mode(interop.termbox.TB_OUTPUT_NORMAL);

    // TODO: Reload the DE list on log out

    // Close the PAM session
    status = interop.pam.pam_close_session(handle, 0);
    if (status != 0) return pamDiagnose(status);

    status = interop.pam.pam_setcred(handle, 0);
    if (status != 0) return pamDiagnose(status);
}

fn initEnv(allocator: Allocator, pwd: *interop.passwd, path: []const u8) !void {
    const term = interop.getenv("TERM");
    const lang = interop.getenv("LANG");

    if (term[0] == 0) _ = interop.setenv("TERM", "linux", 1);
    if (lang[0] == 0) _ = interop.setenv("LANG", "C", 1);
    _ = interop.setenv("HOME", pwd.pw_dir, 1);
    _ = interop.setenv("PWD", pwd.pw_dir, 1);
    _ = interop.setenv("SHELL", pwd.pw_shell, 1);
    _ = interop.setenv("USER", pwd.pw_name, 1);
    _ = interop.setenv("LOGNAME", pwd.pw_name, 1);

    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    const status = interop.setenv("PATH", path_z, 1);
    if (status != 0) return error.SetPathFailed;
}

fn setXdgSessionEnv(display_server: enums.DisplayServer) void {
    _ = interop.setenv("XDG_SESSION_TYPE", switch (display_server) {
        .wayland => "wayland",
        .shell => "tty",
        .xinitrc, .x11 => "x11",
    }, 0);
}

fn setXdgEnv(allocator: Allocator, tty_str: [:0]u8, uid_str: [:0]u8, desktop_name: []const u8) !void {
    const desktop_name_z = try allocator.dupeZ(u8, desktop_name);
    defer allocator.free(desktop_name_z);

    _ = interop.setenv("XDG_RUNTIME_DIR", uid_str.ptr, 0);
    _ = interop.setenv("XDG_SESSION_CLASS", "user", 0);
    _ = interop.setenv("XDG_SESSION_ID", "1", 0);
    _ = interop.setenv("XDG_SESSION_DESKTOP", desktop_name_z.ptr, 0);
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

    const response = login_conv_allocator.alloc(interop.pam.pam_response, message_count) catch return interop.pam.PAM_BUF_ERR;
    defer login_conv_allocator.free(response);

    var status: c_int = undefined;

    for (0..message_count) |i| set_credentials: {
        switch (messages[i].?.msg_style) {
            // TODO: Potentially cast appdata pointer before so we only do it once
            // TODO: Verify if we need to do string duplication here
            interop.pam.PAM_PROMPT_ECHO_ON => {
                const appdata: ?*align(8) anyopaque = @alignCast(appdata_ptr);
                const data: [*][:0]u8 = @ptrCast(appdata.?);
                const username = data[0];

                response[i].resp = username;
            },
            interop.pam.PAM_PROMPT_ECHO_OFF => {
                const appdata: ?*align(8) anyopaque = @alignCast(appdata_ptr);
                const data: [*][:0]u8 = @ptrCast(appdata.?);
                const password = data[1];

                response[i].resp = password;
            },
            interop.pam.PAM_ERROR_MSG => {
                status = interop.pam.PAM_CONV_ERR;
                break :set_credentials;
            },
            else => {},
        }
    }

    if (status == interop.pam.PAM_SUCCESS) resp.?.* = response.ptr;

    return status;
}

fn resetTerminal(allocator: Allocator, shell: [*:0]const u8, term_reset_cmd: []const u8) !void {
    const term_reset_cmd_z = try allocator.dupeZ(u8, term_reset_cmd);
    defer allocator.free(term_reset_cmd_z);

    const pid = std.c.fork();

    if (pid == 0) {
        _ = interop.execl(shell, shell, "-c\x00".ptr, term_reset_cmd_z.ptr, @as([*c]const u8, 0));
        std.os.exit(0);
    }

    var status: c_int = undefined;
    _ = std.c.waitpid(pid, &status, 0);
}

fn executeWaylandCmd(shell: [*:0]const u8, wayland_cmd: []const u8, desktop_cmd: []const u8) !void {
    var cmd_buffer = std.mem.zeroes([1024]u8);

    const cmd_str = try std.fmt.bufPrintZ(&cmd_buffer, "{s} {s}", .{ wayland_cmd, desktop_cmd });
    _ = interop.execl(shell, shell, "-c", cmd_str.ptr, @as([*c]const u8, 0));
}

fn executeShellCmd(shell: [*:0]const u8) void {
    _ = interop.execl(shell, shell, @as([*c]const u8, 0));
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
