const std = @import("std");
const build_options = @import("build_options");
const builtin = @import("builtin");
const clap = @import("clap");
const ini = @import("zigini");
const auth = @import("auth.zig");
const bigclock = @import("bigclock.zig");
const interop = @import("interop.zig");
const Doom = @import("animations/Doom.zig");
const Matrix = @import("animations/Matrix.zig");
const TerminalBuffer = @import("tui/TerminalBuffer.zig");
const Desktop = @import("tui/components/Desktop.zig");
const Text = @import("tui/components/Text.zig");
const InfoLine = @import("tui/components/InfoLine.zig");
const Config = @import("config/Config.zig");
const Lang = @import("config/Lang.zig");
const Save = @import("config/Save.zig");
const migrator = @import("config/migrator.zig");
const SharedError = @import("SharedError.zig");
const utils = @import("tui/utils.zig");

const Ini = ini.Ini;
const termbox = interop.termbox;

var session_pid: std.posix.pid_t = -1;
pub fn signalHandler(i: c_int) callconv(.C) void {
    if (session_pid == 0) return;

    // Forward signal to session to clean up
    if (session_pid > 0) {
        _ = std.c.kill(session_pid, i);
        var status: c_int = 0;
        _ = std.c.waitpid(session_pid, &status, 0);
    }

    termbox.tb_shutdown();
    std.c.exit(i);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const stderr = std.io.getStdErr().writer();

    // Load arguments
    const params = comptime clap.parseParamsComptime(
        \\-h, --help                Shows all commands.
        \\-v, --version             Shows the version of Ly.
        \\-c, --config <str>        Overrides the default configuration path. Example: --config /usr/share/ly
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{ .diagnostic = &diag, .allocator = allocator }) catch |err| {
        diag.report(stderr, err) catch {};
        return err;
    };
    defer res.deinit();

    var config: Config = undefined;
    var lang: Lang = undefined;
    var save: Save = undefined;
    var info_line = InfoLine{};

    if (res.args.help != 0) {
        try clap.help(stderr, clap.Help, &params, .{});

        _ = try stderr.write("Note: if you want to configure Ly, please check the config file, which is usually located at /etc/ly/config.ini.\n");
        std.process.exit(0);
    }
    if (res.args.version != 0) {
        _ = try stderr.write("Ly version " ++ build_options.version ++ "\n");
        std.process.exit(0);
    }

    // Load configuration file
    var config_ini = Ini(Config).init(allocator);
    defer config_ini.deinit();

    var lang_ini = Ini(Lang).init(allocator);
    defer lang_ini.deinit();

    var save_ini = Ini(Save).init(allocator);
    defer save_ini.deinit();

    var save_path: []const u8 = build_options.data_directory ++ "/save.ini";
    var save_path_alloc = false;
    defer {
        if (save_path_alloc) allocator.free(save_path);
    }

    // Compatibility with v0.6.0
    const mapped_config_fields = .{.{ "blank_password", "clear_password" }};

    if (res.args.config) |s| {
        const trailing_slash = if (s[s.len - 1] != '/') "/" else "";

        const config_path = try std.fmt.allocPrint(allocator, "{s}{s}config.ini", .{ s, trailing_slash });
        defer allocator.free(config_path);

        config = config_ini.readFileToStructWithMap(config_path, mapped_config_fields) catch Config{};

        const lang_path = try std.fmt.allocPrint(allocator, "{s}{s}lang/{s}.ini", .{ s, trailing_slash, config.lang });
        defer allocator.free(lang_path);

        lang = lang_ini.readFileToStruct(lang_path) catch Lang{};

        if (config.load) {
            save_path = try std.fmt.allocPrint(allocator, "{s}{s}save.ini", .{ s, trailing_slash });
            save_path_alloc = true;

            var user_buf: [32]u8 = undefined;
            save = save_ini.readFileToStruct(save_path) catch migrator.tryMigrateSaveFile(&user_buf, config.save_file);
        }
    } else {
        config = config_ini.readFileToStructWithMap(build_options.data_directory ++ "/config.ini", mapped_config_fields) catch Config{};

        const lang_path = try std.fmt.allocPrint(allocator, "{s}/lang/{s}.ini", .{ build_options.data_directory, config.lang });
        defer allocator.free(lang_path);

        lang = lang_ini.readFileToStruct(lang_path) catch Lang{};

        if (config.load) {
            var user_buf: [32]u8 = undefined;
            save = save_ini.readFileToStruct(save_path) catch migrator.tryMigrateSaveFile(&user_buf, config.save_file);
        }
    }

    interop.setNumlock(config.console_dev, config.numlock) catch {};

    // Initialize information line with host name
    get_host_name: {
        var name_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
        const hostname = std.posix.gethostname(&name_buf) catch {
            try info_line.setText(lang.err_hostname);
            break :get_host_name;
        };
        try info_line.setText(hostname);
    }

    // Initialize termbox
    _ = termbox.tb_init();
    defer termbox.tb_shutdown();

    const act = std.posix.Sigaction{
        .handler = .{ .handler = &signalHandler },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    try std.posix.sigaction(std.posix.SIG.TERM, &act, null);

    _ = termbox.tb_select_output_mode(termbox.TB_OUTPUT_NORMAL);
    termbox.tb_clear();

    // Needed to reset termbox after auth
    const tb_termios = try std.posix.tcgetattr(std.posix.STDIN_FILENO);

    // Initialize terminal buffer
    const labels_max_length = @max(lang.login.len, lang.password.len);

    var buffer = TerminalBuffer.init(config, labels_max_length);

    // Initialize components
    var desktop = try Desktop.init(allocator, &buffer, config.max_desktop_len, lang);
    defer desktop.deinit();

    desktop.addEnvironment(.{ .Name = lang.shell }, "", .shell) catch {
        try info_line.setText(lang.err_alloc);
    };
    if (config.xinitrc) |xinitrc| {
        desktop.addEnvironment(.{ .Name = lang.xinitrc, .Exec = xinitrc }, "", .xinitrc) catch {
            try info_line.setText(lang.err_alloc);
        };
    }

    try desktop.crawl(config.waylandsessions, .wayland);
    try desktop.crawl(config.xsessions, .x11);

    var login = try Text.init(allocator, &buffer, config.max_login_len);
    defer login.deinit();

    var password = try Text.init(allocator, &buffer, config.max_password_len);
    defer password.deinit();

    var active_input = config.default_input;
    var insert_mode = !config.vi_mode;

    // Load last saved username and desktop selection, if any
    if (config.load) {
        if (save.user) |user| {
            try login.text.appendSlice(user);
            login.end = user.len;
            login.cursor = login.end;
            active_input = .password;
        }

        if (save.session_index) |session_index| {
            if (session_index < desktop.environments.items.len) desktop.current = session_index;
        }
    }

    // Place components on the screen
    {
        buffer.drawBoxCenter(!config.hide_borders, config.blank_box);

        const coordinates = buffer.calculateComponentCoordinates();
        desktop.position(coordinates.x, coordinates.y + 2, coordinates.visible_length);
        login.position(coordinates.x, coordinates.y + 4, coordinates.visible_length);
        password.position(coordinates.x, coordinates.y + 6, coordinates.visible_length);

        switch (active_input) {
            .session => desktop.handle(null, insert_mode),
            .login => login.handle(null, insert_mode) catch {
                try info_line.setText(lang.err_alloc);
            },
            .password => password.handle(null, insert_mode) catch {
                try info_line.setText(lang.err_alloc);
            },
        }
    }

    // Initialize the animation, if any
    var doom: Doom = undefined;
    var matrix: Matrix = undefined;

    switch (config.animation) {
        .none => {},
        .doom => doom = try Doom.init(allocator, &buffer),
        .matrix => matrix = try Matrix.init(allocator, &buffer),
    }
    defer {
        switch (config.animation) {
            .none => {},
            .doom => doom.deinit(),
            .matrix => matrix.deinit(),
        }
    }

    const animate = config.animation != .none;
    const shutdown_key = try std.fmt.parseInt(u8, config.shutdown_key[1..], 10);
    const shutdown_len = try utils.strWidth(lang.shutdown);
    const restart_key = try std.fmt.parseInt(u8, config.restart_key[1..], 10);
    const restart_len = try utils.strWidth(lang.restart);
    const sleep_key = try std.fmt.parseInt(u8, config.sleep_key[1..], 10);

    var event: termbox.tb_event = undefined;
    var run = true;
    var update = true;
    var resolution_changed = false;
    var shutdown = false;
    var restart = false;
    var auth_fails: u64 = 0;

    open_console_dev: {
        const fd = std.posix.open(config.console_dev, .{ .ACCMODE = .WRONLY }, 0) catch {
            try info_line.setText(lang.err_console_dev);
            break :open_console_dev;
        };
        defer std.posix.close(fd);

        // Switch to selected TTY if possible
        _ = std.c.ioctl(fd, interop.VT_ACTIVATE, config.tty);
        _ = std.c.ioctl(fd, interop.VT_WAITACTIVE, config.tty);
    }

    while (run) {
        // If there's no input or there's an animation, a resolution change needs to be checked
        if (!update or config.animation != .none) {
            if (!update) std.time.sleep(std.time.ns_per_ms * 100);

            termbox.tb_present(); // Required to update tb_width(), tb_height() and tb_cell_buffer()

            const width: u64 = @intCast(termbox.tb_width());
            const height: u64 = @intCast(termbox.tb_height());

            if (width != buffer.width) {
                buffer.width = width;
                resolution_changed = true;
            }

            if (height != buffer.height) {
                buffer.height = height;
                resolution_changed = true;
            }

            // If it did change, then update the cell buffer, reallocate the current animation's buffers, and force a draw update
            if (resolution_changed) {
                buffer.buffer = termbox.tb_cell_buffer();

                switch (config.animation) {
                    .none => {},
                    .doom => doom.realloc() catch {
                        try info_line.setText(lang.err_alloc);
                    },
                    .matrix => matrix.realloc() catch {
                        try info_line.setText(lang.err_alloc);
                    },
                }

                update = true;
            }
        }

        if (update) {
            // If the user entered a wrong password 10 times in a row, play a cascade animation, else update normally
            if (auth_fails < 10) {
                termbox.tb_clear();

                switch (config.animation) {
                    .none => {},
                    .doom => doom.draw(),
                    .matrix => matrix.draw(),
                }

                if (config.bigclock and buffer.box_height + (bigclock.HEIGHT + 2) * 2 < buffer.height) draw_big_clock: {
                    const format = "%H:%M";
                    const xo = buffer.width / 2 - @min(buffer.width, (format.len * (bigclock.WIDTH + 1))) / 2;
                    const yo = (buffer.height - buffer.box_height) / 2 - bigclock.HEIGHT - 2;

                    var clock_buf: [format.len + 1:0]u8 = undefined;
                    const clock_str = interop.timeAsString(&clock_buf, format) catch {
                        break :draw_big_clock;
                    };

                    for (clock_str, 0..) |c, i| {
                        const clock_cell = bigclock.clockCell(animate, c, buffer.fg, buffer.bg);
                        bigclock.alphaBlit(buffer.buffer, xo + i * (bigclock.WIDTH + 1), yo, buffer.width, buffer.height, clock_cell);
                    }
                }

                buffer.drawBoxCenter(!config.hide_borders, config.blank_box);

                if (resolution_changed) {
                    const coordinates = buffer.calculateComponentCoordinates();
                    desktop.position(coordinates.x, coordinates.y + 2, coordinates.visible_length);
                    login.position(coordinates.x, coordinates.y + 4, coordinates.visible_length);
                    password.position(coordinates.x, coordinates.y + 6, coordinates.visible_length);

                    resolution_changed = false;
                }

                switch (active_input) {
                    .session => desktop.handle(null, insert_mode),
                    .login => login.handle(null, insert_mode) catch {
                        try info_line.setText(lang.err_alloc);
                    },
                    .password => password.handle(null, insert_mode) catch {
                        try info_line.setText(lang.err_alloc);
                    },
                }

                if (config.clock) |clock| draw_clock: {
                    var clock_buf: [32:0]u8 = undefined;
                    const clock_str = interop.timeAsString(&clock_buf, clock) catch {
                        break :draw_clock;
                    };

                    if (clock_str.len == 0) return error.FormattedTimeEmpty;

                    buffer.drawLabel(clock_str, buffer.width - @min(buffer.width, clock_str.len), 0);
                }

                const label_x = buffer.box_x + buffer.margin_box_h;
                const label_y = buffer.box_y + buffer.margin_box_v;

                buffer.drawLabel(lang.login, label_x, label_y + 4);
                buffer.drawLabel(lang.password, label_x, label_y + 6);

                info_line.draw(buffer);

                if (!config.hide_key_hints) {
                    var length: u64 = 0;

                    buffer.drawLabel(config.shutdown_key, length, 0);
                    length += config.shutdown_key.len + 1;
                    buffer.drawLabel(" ", length - 1, 0);

                    buffer.drawLabel(lang.shutdown, length, 0);
                    length += shutdown_len + 1;

                    buffer.drawLabel(config.restart_key, length, 0);
                    length += config.restart_key.len + 1;
                    buffer.drawLabel(" ", length - 1, 0);

                    buffer.drawLabel(lang.restart, length, 0);
                    length += restart_len + 1;

                    if (config.sleep_cmd != null) {
                        buffer.drawLabel(config.sleep_key, length, 0);
                        length += config.sleep_key.len + 1;
                        buffer.drawLabel(" ", length - 1, 0);

                        buffer.drawLabel(lang.sleep, length, 0);
                    }
                }

                if (config.vi_mode) {
                    const label_txt = if (insert_mode) lang.insert else lang.normal;
                    buffer.drawLabel(label_txt, buffer.box_x, buffer.box_y - 1);
                }

                draw_lock_state: {
                    const lock_state = interop.getLockState(config.console_dev) catch {
                        try info_line.setText(lang.err_console_dev);
                        break :draw_lock_state;
                    };

                    var lock_state_x = buffer.width - lang.numlock.len;
                    const lock_state_y: u64 = if (config.clock != null) 1 else 0;

                    if (lock_state.numlock) buffer.drawLabel(lang.numlock, lock_state_x, lock_state_y);
                    lock_state_x -= lang.capslock.len + 1;
                    if (lock_state.capslock) buffer.drawLabel(lang.capslock, lock_state_x, lock_state_y);
                }

                desktop.draw();
                login.draw();
                password.drawMasked(config.asterisk);

                update = animate;
            } else {
                std.time.sleep(std.time.ns_per_ms * 10);
                update = buffer.cascade();

                if (!update) {
                    std.time.sleep(std.time.ns_per_s * 7);
                    auth_fails = 0;
                }
            }

            termbox.tb_present();
        }

        var timeout: i32 = -1;

        // Calculate the maximum timeout based on current animations, or the (big) clock. If there's none, we wait for the event indefinitely instead
        if (animate) {
            timeout = config.min_refresh_delta;
        } else if (config.bigclock and config.clock == null) {
            var tv: std.c.timeval = undefined;
            _ = std.c.gettimeofday(&tv, null);

            timeout = @intCast((60 - @rem(tv.tv_sec, 60)) * 1000 - @divTrunc(tv.tv_usec, 1000) + 1);
        } else if (config.clock != null or auth_fails >= 10) {
            var tv: std.c.timeval = undefined;
            _ = std.c.gettimeofday(&tv, null);

            timeout = @intCast(1000 - @divTrunc(tv.tv_usec, 1000) + 1);
        }

        const event_error = if (timeout == -1) termbox.tb_poll_event(&event) else termbox.tb_peek_event(&event, timeout);

        if (event_error < 0 or event.type != termbox.TB_EVENT_KEY) continue;

        switch (event.key) {
            termbox.TB_KEY_ESC => {
                if (config.vi_mode and insert_mode) {
                    insert_mode = false;
                    update = true;
                }
            },
            termbox.TB_KEY_F12...termbox.TB_KEY_F1 => {
                const pressed_key = 0xFFFF - event.key + 1;
                if (pressed_key == shutdown_key) {
                    shutdown = true;
                    run = false;
                } else if (pressed_key == restart_key) {
                    restart = true;
                    run = false;
                } else if (pressed_key == sleep_key) {
                    if (config.sleep_cmd) |sleep_cmd| {
                        var sleep = std.ChildProcess.init(&[_][]const u8{ "/bin/sh", "-c", sleep_cmd }, allocator);
                        _ = sleep.spawnAndWait() catch .{};
                    }
                }
            },
            termbox.TB_KEY_CTRL_C => run = false,
            termbox.TB_KEY_CTRL_U => {
                if (active_input == .login) {
                    login.clear();
                    update = true;
                } else if (active_input == .password) {
                    password.clear();
                    update = true;
                }
            },
            termbox.TB_KEY_CTRL_K, termbox.TB_KEY_ARROW_UP => {
                active_input = switch (active_input) {
                    .session, .login => .session,
                    .password => .login,
                };
                update = true;
            },
            termbox.TB_KEY_CTRL_J, termbox.TB_KEY_ARROW_DOWN => {
                active_input = switch (active_input) {
                    .session => .login,
                    .login, .password => .password,
                };
                update = true;
            },
            termbox.TB_KEY_TAB => {
                active_input = switch (active_input) {
                    .session => .login,
                    .login => .password,
                    .password => .session,
                };
                update = true;
            },
            termbox.TB_KEY_ENTER => {
                if (config.save) save_last_settings: {
                    var file = std.fs.createFileAbsolute(save_path, .{}) catch break :save_last_settings;
                    defer file.close();

                    const save_data = Save{
                        .user = login.text.items,
                        .session_index = desktop.current,
                    };
                    ini.writeFromStruct(save_data, file.writer(), null) catch break :save_last_settings;
                }

                var shared_err = try SharedError.init();
                defer shared_err.deinit();

                {
                    const login_text = try allocator.dupeZ(u8, login.text.items);
                    defer allocator.free(login_text);
                    const password_text = try allocator.dupeZ(u8, password.text.items);
                    defer allocator.free(password_text);

                    try info_line.setText(lang.authenticating);
                    InfoLine.clearRendered(allocator, buffer) catch {};
                    info_line.draw(buffer);
                    _ = termbox.tb_present();

                    session_pid = try std.posix.fork();
                    if (session_pid == 0) {
                        const current_environment = desktop.environments.items[desktop.current];
                        auth.authenticate(config, current_environment, login_text, password_text) catch |err| {
                            shared_err.writeError(err);
                            std.process.exit(1);
                        };
                        std.process.exit(0);
                    }

                    _ = std.posix.waitpid(session_pid, 0);
                    session_pid = -1;
                }

                const auth_err = shared_err.readError();
                if (auth_err) |err| {
                    auth_fails += 1;
                    active_input = .password;
                    try info_line.setText(getAuthErrorMsg(err, lang));
                    if (config.clear_password or err != error.PamAuthError) password.clear();
                } else {
                    password.clear();
                    try info_line.setText(lang.logout);
                }

                try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, tb_termios);
                if (auth_fails < 10) {
                    termbox.tb_clear();
                    termbox.tb_present();
                }

                update = true;

                var restore_cursor = std.ChildProcess.init(&[_][]const u8{ "/bin/sh", "-c", config.term_restore_cursor_cmd }, allocator);
                _ = restore_cursor.spawnAndWait() catch .{};
            },
            else => {
                if (!insert_mode) {
                    switch (event.ch) {
                        'k' => {
                            active_input = switch (active_input) {
                                .session, .login => .session,
                                .password => .login,
                            };
                            update = true;
                            continue;
                        },
                        'j' => {
                            active_input = switch (active_input) {
                                .session => .login,
                                .login, .password => .password,
                            };
                            update = true;
                            continue;
                        },
                        'i' => {
                            insert_mode = true;
                            update = true;
                            continue;
                        },
                        else => {},
                    }
                }

                switch (active_input) {
                    .session => desktop.handle(&event, insert_mode),
                    .login => login.handle(&event, insert_mode) catch {
                        try info_line.setText(lang.err_alloc);
                    },
                    .password => password.handle(&event, insert_mode) catch {
                        try info_line.setText(lang.err_alloc);
                    },
                }
                update = true;
            },
        }
    }

    if (shutdown) {
        return std.process.execv(allocator, &[_][]const u8{ "/bin/sh", "-c", config.shutdown_cmd });
    } else if (restart) {
        return std.process.execv(allocator, &[_][]const u8{ "/bin/sh", "-c", config.restart_cmd });
    }
}

fn getAuthErrorMsg(err: anyerror, lang: Lang) []const u8 {
    return switch (err) {
        error.GetPasswordNameFailed => lang.err_pwnam,
        error.GroupInitializationFailed => lang.err_user_init,
        error.SetUserGidFailed => lang.err_user_gid,
        error.SetUserUidFailed => lang.err_user_uid,
        error.ChangeDirectoryFailed => lang.err_perm_dir,
        error.SetPathFailed => lang.err_path,
        error.PamAccountExpired => lang.err_pam_acct_expired,
        error.PamAuthError => lang.err_pam_auth,
        error.PamAuthInfoUnavailable => lang.err_pam_authinfo_unavail,
        error.PamBufferError => lang.err_pam_buf,
        error.PamCredentialsError => lang.err_pam_cred_err,
        error.PamCredentialsExpired => lang.err_pam_cred_expired,
        error.PamCredentialsInsufficient => lang.err_pam_cred_insufficient,
        error.PamCredentialsUnavailable => lang.err_pam_cred_unavail,
        error.PamMaximumTries => lang.err_pam_maxtries,
        error.PamNewAuthTokenRequired => lang.err_pam_authok_reqd,
        error.PamPermissionDenied => lang.err_pam_perm_denied,
        error.PamSessionError => lang.err_pam_session,
        error.PamSystemError => lang.err_pam_sys,
        error.PamUserUnknown => lang.err_pam_user_unknown,
        error.PamAbort => lang.err_pam_abort,
        else => lang.err_unknown,
    };
}
