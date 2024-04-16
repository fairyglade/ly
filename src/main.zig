const std = @import("std");
const build_options = @import("build_options");
const builtin = @import("builtin");
const clap = @import("clap");
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
const ini = @import("zigini");
const Lang = @import("config/Lang.zig");
const Save = @import("config/Save.zig");
const ViMode = @import("enums.zig").ViMode;
const SharedError = @import("SharedError.zig");
const utils = @import("tui/utils.zig");

const Ini = ini.Ini;
const termbox = interop.termbox;

pub fn signalHandler(i: c_int) callconv(.C) void {
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
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{ .diagnostic = &diag }) catch |err| {
        diag.report(stderr, err) catch {};
        return err;
    };
    defer res.deinit();

    var config: Config = undefined;
    var lang: Lang = undefined;
    var info_line = InfoLine{};

    if (res.args.help != 0) {
        try clap.help(stderr, clap.Help, &params, .{});

        _ = try stderr.write("Note: if you want to configure Ly, please check the config file, which is usually located at /etc/ly/config.ini.\n");
        std.os.exit(0);
    }
    if (res.args.version != 0) {
        _ = try stderr.write("Ly version " ++ build_options.version ++ "\n");
        std.os.exit(0);
    }

    // Load configuration file
    var config_ini = Ini(Config).init(allocator);
    defer config_ini.deinit();
    var lang_ini = Ini(Lang).init(allocator);
    defer lang_ini.deinit();

    if (res.args.config) |s| {
        const trailing_slash = if (s[s.len - 1] != '/') "/" else "";

        const config_path = try std.fmt.allocPrint(allocator, "{s}{s}config.ini", .{ s, trailing_slash });
        defer allocator.free(config_path);

        config = config_ini.readToStruct(config_path) catch Config{};

        const lang_path = try std.fmt.allocPrint(allocator, "{s}{s}lang/{s}.ini", .{ s, trailing_slash, config.lang });
        defer allocator.free(lang_path);

        lang = lang_ini.readToStruct(lang_path) catch Lang{};
    } else {
        config = config_ini.readToStruct(build_options.data_directory ++ "/config.ini") catch Config{};

        const lang_path = try std.fmt.allocPrint(allocator, "{s}/lang/{s}.ini", .{ build_options.data_directory, config.lang });
        defer allocator.free(lang_path);

        lang = lang_ini.readToStruct(lang_path) catch Lang{};
    }

    // Initialize information line with host name
    var got_host_name = false;
    var host_name_buffer: []u8 = undefined;

    get_host_name: {
        const host_name_struct = interop.getHostName(allocator) catch |err| {
            if (err == error.CannotGetHostName) {
                try info_line.setText(lang.err_hostname);
            } else {
                try info_line.setText(lang.err_alloc);
            }
            break :get_host_name;
        };

        got_host_name = true;
        host_name_buffer = host_name_struct.buffer;
        try info_line.setText(host_name_struct.slice);
    }

    defer {
        if (got_host_name) allocator.free(host_name_buffer);
    }

    // Initialize termbox
    _ = termbox.tb_init();
    defer termbox.tb_shutdown();

    const act = std.os.Sigaction{
        .handler = .{ .handler = &signalHandler },
        .mask = std.os.empty_sigset,
        .flags = 0,
    };
    try std.os.sigaction(std.os.SIG.TERM, &act, null);

    _ = termbox.tb_select_output_mode(termbox.TB_OUTPUT_NORMAL);
    termbox.tb_clear();

    // we need this to reset it after auth.
    const tb_termios = try std.os.tcgetattr(std.os.STDIN_FILENO);

    // Initialize terminal buffer
    const labels_max_length = @max(lang.login.len, lang.password.len);

    var buffer = TerminalBuffer.init(config, labels_max_length);

    // Initialize components
    var desktop = try Desktop.init(allocator, &buffer, config.max_desktop_len, lang);
    defer desktop.deinit();

    desktop.addEnvironment(lang.shell, "", .shell) catch {
        try info_line.setText(lang.err_alloc);
    };
    if (config.xinitrc) |xinitrc| {
        desktop.addEnvironment(lang.xinitrc, xinitrc, .xinitrc) catch {
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
        var save_ini = Ini(Save).init(allocator);
        defer save_ini.deinit();
        const save = save_ini.readToStruct(config.save_file) catch Save{};

        if (save.user) |user| {
            try login.text.appendSlice(user);
            login.end = user.len;
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

    // Switch to selected TTY if possible
    open_console_dev: {
        const console_dev_z = allocator.dupeZ(u8, config.console_dev) catch {
            try info_line.setText(lang.err_alloc);
            break :open_console_dev;
        };
        defer allocator.free(console_dev_z);

        const fd = std.c.open(console_dev_z, interop.O_WRONLY);
        defer _ = std.c.close(fd);

        if (fd < 0) {
            try info_line.setText(lang.err_console_dev);
            break :open_console_dev;
        }

        _ = std.c.ioctl(fd, interop.VT_ACTIVATE, config.tty);
        _ = std.c.ioctl(fd, interop.VT_WAITACTIVE, config.tty);
    }

    while (run) {
        // If there's no input or there's an animation, a resolution change needs to be checked
        if (!update or config.animation != .none) {
            if (!update) std.time.sleep(100_000_000);

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
                switch (active_input) {
                    .session => desktop.handle(null, insert_mode),
                    .login => login.handle(null, insert_mode) catch {
                        try info_line.setText(lang.err_alloc);
                    },
                    .password => password.handle(null, insert_mode) catch {
                        try info_line.setText(lang.err_alloc);
                    },
                }

                termbox.tb_clear();

                switch (config.animation) {
                    .none => {},
                    .doom => doom.draw(),
                    .matrix => matrix.draw(),
                }

                if (config.bigclock and buffer.box_height + (bigclock.HEIGHT + 2) * 2 < buffer.height) draw_big_clock: {
                    const format = "%H:%M";
                    const xo = buffer.width / 2 - (format.len * (bigclock.WIDTH + 1)) / 2;
                    const yo = (buffer.height - buffer.box_height) / 2 - bigclock.HEIGHT - 2;

                    const clock_str = interop.timeAsString(allocator, format, format.len + 1) catch {
                        try info_line.setText(lang.err_alloc);
                        break :draw_big_clock;
                    };
                    defer allocator.free(clock_str);

                    for (0..format.len) |i| {
                        const clock_cell = bigclock.clockCell(animate, clock_str[i], buffer.fg, buffer.bg);
                        bigclock.alphaBlit(buffer.buffer, xo + i * (bigclock.WIDTH + 1), yo, buffer.width, buffer.height, clock_cell);
                    }
                }

                buffer.drawBoxCenter(!config.hide_borders, config.blank_box);

                if (config.clock) |clock| draw_clock: {
                    const clock_buffer = interop.timeAsString(allocator, clock, 32) catch {
                        try info_line.setText(lang.err_alloc);
                        break :draw_clock;
                    };
                    defer allocator.free(clock_buffer);

                    var clock_str_length: u64 = 0;
                    for (clock_buffer, 0..) |char, i| {
                        if (char == 0) {
                            clock_str_length = i;
                            break;
                        }
                    }

                    if (clock_str_length == 0) return error.FormattedTimeEmpty;

                    buffer.drawLabel(clock_buffer[0..clock_str_length], buffer.width - clock_str_length, 0);
                }

                const label_x = buffer.box_x + buffer.margin_box_h;
                const label_y = buffer.box_y + buffer.margin_box_v;

                buffer.drawLabel(lang.login, label_x, label_y + 4);
                buffer.drawLabel(lang.password, label_x, label_y + 6);

                if (info_line.width > 0 and buffer.box_width > info_line.width) {
                    const x = buffer.box_x + ((buffer.box_width - info_line.width) / 2);
                    buffer.drawLabel(info_line.text, x, label_y);
                }

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
                    const lock_state = interop.getLockState(config.console_dev) catch |err| {
                        if (err == error.CannotOpenConsoleDev) {
                            try info_line.setText(lang.err_console_dev);
                        } else {
                            try info_line.setText(lang.err_alloc);
                        }
                        break :draw_lock_state;
                    };

                    var lock_state_x = buffer.width - lang.numlock.len;
                    const lock_state_y: u64 = if (config.clock != null) 1 else 0;

                    if (lock_state.numlock) buffer.drawLabel(lang.numlock, lock_state_x, lock_state_y);
                    lock_state_x -= lang.capslock.len + 1;
                    if (lock_state.capslock) buffer.drawLabel(lang.capslock, lock_state_x, lock_state_y);
                }

                if (resolution_changed) {
                    const coordinates = buffer.calculateComponentCoordinates();
                    desktop.position(coordinates.x, coordinates.y + 2, coordinates.visible_length);
                    login.position(coordinates.x, coordinates.y + 4, coordinates.visible_length);
                    password.position(coordinates.x, coordinates.y + 6, coordinates.visible_length);

                    resolution_changed = false;
                }

                desktop.draw();
                login.draw();
                password.drawMasked(config.asterisk);

                update = animate;
            } else {
                std.time.sleep(10_000_000);
                update = buffer.cascade();

                if (!update) {
                    std.time.sleep(7_000_000_000);
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
                        const pid = try std.os.fork();
                        if (pid == 0) {
                            std.process.execv(allocator, &[_][]const u8{ "/bin/sh", "-c", sleep_cmd }) catch std.os.exit(1);
                            std.os.exit(0);
                        }
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
                    var file = std.fs.createFileAbsolute(config.save_file, .{}) catch break :save_last_settings;
                    defer file.close();

                    const save_data = Save{
                        .user = login.text.items,
                        .session_index = desktop.current,
                    };
                    ini.writeFromStruct(save_data, file.writer(), null) catch break :save_last_settings;
                }

                var shared_err = try SharedError.init();
                defer shared_err.deinit();

                const session_pid = try std.os.fork();
                if (session_pid == 0) {
                    auth.authenticate(allocator, config, desktop, login, &password) catch |err| {
                        shared_err.writeError(err);
                        std.os.exit(1);
                    };
                    std.os.exit(0);
                }

                _ = std.os.waitpid(session_pid, 0);

                var auth_err = shared_err.readError();
                if (auth_err) |err| {
                    auth_fails += 1;
                    active_input = .password;
                    try info_line.setText(getAuthErrorMsg(err, lang));
                    if (config.clear_password or err != error.PamAuthError) password.clear();
                } else {
                    password.clear();
                    try info_line.setText(lang.logout);
                }

                try std.os.tcsetattr(std.os.STDIN_FILENO, .FLUSH, tb_termios);
                termbox.tb_clear();
                termbox.tb_present();

                update = true;

                const pid = try std.os.fork();
                if (pid == 0) {
                    std.process.execv(allocator, &[_][]const u8{ "/bin/sh", "-c", config.term_restore_cursor_cmd }) catch std.os.exit(1);
                    std.os.exit(0);
                }
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
        else => "An unknown error occurred",
    };
}
