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
const Session = @import("tui/components/Session.zig");
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
const unistd = interop.unistd;
const temporary_allocator = std.heap.page_allocator;

var session_pid: std.posix.pid_t = -1;
pub fn signalHandler(i: c_int) callconv(.C) void {
    if (session_pid == 0) return;

    // Forward signal to session to clean up
    if (session_pid > 0) {
        _ = std.c.kill(session_pid, i);
        var status: c_int = 0;
        _ = std.c.waitpid(session_pid, &status, 0);
    }

    _ = termbox.tb_shutdown();
    std.c.exit(i);
}

pub fn main() !void {
    var shutdown = false;
    var restart = false;
    var shutdown_cmd: []const u8 = undefined;
    var restart_cmd: []const u8 = undefined;

    const stderr = std.io.getStdErr().writer();

    defer {
        // If we can't shutdown or restart due to an error, we print it to standard error. If that fails, just bail out
        if (shutdown) {
            const shutdown_error = std.process.execv(temporary_allocator, &[_][]const u8{ "/bin/sh", "-c", shutdown_cmd });
            stderr.print("error: couldn't shutdown: {any}\n", .{shutdown_error}) catch std.process.exit(1);
        } else if (restart) {
            const restart_error = std.process.execv(temporary_allocator, &[_][]const u8{ "/bin/sh", "-c", restart_cmd });
            stderr.print("error: couldn't restart: {any}\n", .{restart_error}) catch std.process.exit(1);
        } else {
            // The user has quit Ly using Ctrl+C
            temporary_allocator.free(shutdown_cmd);
            temporary_allocator.free(restart_cmd);
        }
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // to be able to stop the animation after some time

    var tv_zero: interop.system_time.timeval = undefined;
    _ = interop.system_time.gettimeofday(&tv_zero, null);
    var animation_timed_out: bool = false;

    const allocator = gpa.allocator();

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
    var config_load_failed = false;

    if (res.args.help != 0) {
        try clap.help(stderr, clap.Help, &params, .{});

        _ = try stderr.write("Note: if you want to configure Ly, please check the config file, which is located at " ++ build_options.config_directory ++ "/ly/config.ini.\n");
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

    var save_path: []const u8 = build_options.config_directory ++ "/ly/save.ini";
    var save_path_alloc = false;
    defer {
        if (save_path_alloc) allocator.free(save_path);
    }

    const comment_characters = "#";

    if (res.args.config) |s| {
        const trailing_slash = if (s[s.len - 1] != '/') "/" else "";

        const config_path = try std.fmt.allocPrint(allocator, "{s}{s}config.ini", .{ s, trailing_slash });
        defer allocator.free(config_path);

        config = config_ini.readFileToStruct(config_path, comment_characters, migrator.configFieldHandler) catch _config: {
            config_load_failed = true;
            break :_config Config{};
        };

        const lang_path = try std.fmt.allocPrint(allocator, "{s}{s}lang/{s}.ini", .{ s, trailing_slash, config.lang });
        defer allocator.free(lang_path);

        lang = lang_ini.readFileToStruct(lang_path, comment_characters, null) catch Lang{};

        if (config.load) {
            save_path = try std.fmt.allocPrint(allocator, "{s}{s}save.ini", .{ s, trailing_slash });
            save_path_alloc = true;

            var user_buf: [32]u8 = undefined;
            save = save_ini.readFileToStruct(save_path, comment_characters, null) catch migrator.tryMigrateSaveFile(&user_buf);
        }

        migrator.lateConfigFieldHandler(&config.animation);
    } else {
        const config_path = build_options.config_directory ++ "/ly/config.ini";

        config = config_ini.readFileToStruct(config_path, comment_characters, migrator.configFieldHandler) catch _config: {
            config_load_failed = true;
            break :_config Config{};
        };

        const lang_path = try std.fmt.allocPrint(allocator, "{s}/ly/lang/{s}.ini", .{ build_options.config_directory, config.lang });
        defer allocator.free(lang_path);

        lang = lang_ini.readFileToStruct(lang_path, comment_characters, null) catch Lang{};

        if (config.load) {
            var user_buf: [32]u8 = undefined;
            save = save_ini.readFileToStruct(save_path, comment_characters, null) catch migrator.tryMigrateSaveFile(&user_buf);
        }

        migrator.lateConfigFieldHandler(&config.animation);
    }

    // if (migrator.mapped_config_fields) save_migrated_config: {
    //     var file = try std.fs.cwd().createFile(config_path, .{});
    //     defer file.close();

    //     const writer = file.writer();
    //     ini.writeFromStruct(config, writer, null, true, .{}) catch {
    //         break :save_migrated_config;
    //     };
    // }

    // These strings only end up getting freed if the user quits Ly using Ctrl+C, which is fine since in the other cases
    // we end up shutting down or restarting the system
    shutdown_cmd = try temporary_allocator.dupe(u8, config.shutdown_cmd);
    restart_cmd = try temporary_allocator.dupe(u8, config.restart_cmd);

    // Initialize termbox
    _ = termbox.tb_init();
    defer _ = termbox.tb_shutdown();

    const act = std.posix.Sigaction{
        .handler = .{ .handler = &signalHandler },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    try std.posix.sigaction(std.posix.SIG.TERM, &act, null);

    _ = termbox.tb_set_output_mode(termbox.TB_OUTPUT_NORMAL);
    _ = termbox.tb_clear();

    // Needed to reset termbox after auth
    const tb_termios = try std.posix.tcgetattr(std.posix.STDIN_FILENO);

    // Initialize terminal buffer
    const labels_max_length = @max(lang.login.len, lang.password.len);

    var seed: u64 = undefined;
    std.crypto.random.bytes(std.mem.asBytes(&seed)); // Get a random seed for the PRNG (used by animations)

    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    var buffer = TerminalBuffer.init(config, labels_max_length, random);

    // Initialize components
    var info_line = InfoLine.init(allocator, &buffer);
    defer info_line.deinit();

    if (config_load_failed) {
        // We can't localize this since the config failed to load so we'd fallback to the default language anyway
        try info_line.addMessage("unable to parse config file", config.error_bg, config.error_fg);
    }

    interop.setNumlock(config.numlock) catch {
        try info_line.addMessage(lang.err_numlock, config.error_bg, config.error_fg);
    };

    var session = Session.init(allocator, &buffer, lang);
    defer session.deinit();

    session.addEnvironment(.{ .Name = lang.shell }, null, .shell) catch {
        try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
    };

    if (build_options.enable_x11_support) {
        if (config.xinitrc) |xinitrc| {
            session.addEnvironment(.{ .Name = lang.xinitrc, .Exec = xinitrc }, null, .xinitrc) catch {
                try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
            };
        }
    } else {
        try info_line.addMessage(lang.no_x11_support, config.bg, config.fg);
    }

    if (config.initial_info_text) |text| {
        try info_line.addMessage(text, config.bg, config.fg);
    } else get_host_name: {
        // Initialize information line with host name
        var name_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
        const hostname = std.posix.gethostname(&name_buf) catch {
            try info_line.addMessage(lang.err_hostname, config.error_bg, config.error_fg);
            break :get_host_name;
        };
        try info_line.addMessage(hostname, config.bg, config.fg);
    }

    try session.crawl(config.waylandsessions, .wayland);
    if (build_options.enable_x11_support) try session.crawl(config.xsessions, .x11);

    var login = Text.init(allocator, &buffer, false, null);
    defer login.deinit();

    var password = Text.init(allocator, &buffer, true, config.asterisk);
    defer password.deinit();

    var active_input = config.default_input;
    var insert_mode = !config.vi_mode or config.vi_default_mode == .insert;

    // Load last saved username and desktop selection, if any
    if (config.load) {
        if (save.user) |user| {
            try login.text.appendSlice(user);
            login.end = user.len;
            login.cursor = login.end;
            active_input = .password;
        }

        if (save.session_index) |session_index| {
            if (session_index < session.label.list.items.len) session.label.current = session_index;
        }
    }

    // Place components on the screen
    {
        buffer.drawBoxCenter(!config.hide_borders, config.blank_box);

        const coordinates = buffer.calculateComponentCoordinates();
        info_line.label.position(coordinates.start_x, coordinates.y, coordinates.full_visible_length, null);
        session.label.position(coordinates.x, coordinates.y + 2, coordinates.visible_length, config.text_in_center);
        login.position(coordinates.x, coordinates.y + 4, coordinates.visible_length);
        password.position(coordinates.x, coordinates.y + 6, coordinates.visible_length);

        switch (active_input) {
            .info_line => info_line.label.handle(null, insert_mode),
            .session => session.label.handle(null, insert_mode),
            .login => login.handle(null, insert_mode) catch {
                try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
            },
            .password => password.handle(null, insert_mode) catch {
                try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
            },
        }
    }

    // Initialize the animation, if any
    var doom: Doom = undefined;
    var matrix: Matrix = undefined;

    switch (config.animation) {
        .none => {},
        .doom => doom = try Doom.init(allocator, &buffer),
        .matrix => matrix = try Matrix.init(allocator, &buffer, config.cmatrix_fg),
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
    const sleep_len = try utils.strWidth(lang.sleep);
    const brightness_down_key = try std.fmt.parseInt(u8, config.brightness_down_key[1..], 10);
    const brightness_down_len = try utils.strWidth(lang.brightness_down);
    const brightness_up_key = try std.fmt.parseInt(u8, config.brightness_up_key[1..], 10);
    const brightness_up_len = try utils.strWidth(lang.brightness_up);

    var event: termbox.tb_event = undefined;
    var run = true;
    var update = true;
    var resolution_changed = false;
    var auth_fails: u64 = 0;

    // Switch to selected TTY if possible
    interop.switchTty(config.console_dev, config.tty) catch {
        try info_line.addMessage(lang.err_console_dev, config.error_bg, config.error_fg);
    };

    while (run) {
        // If there's no input or there's an animation, a resolution change needs to be checked
        if (!update or config.animation != .none) {
            if (!update) std.time.sleep(std.time.ns_per_ms * 100);

            _ = termbox.tb_present(); // Required to update tb_width(), tb_height() and tb_cell_buffer()

            const width: usize = @intCast(termbox.tb_width());
            const height: usize = @intCast(termbox.tb_height());

            if (width != buffer.width or height != buffer.height) {
                // If it did change, then update the cell buffer, reallocate the current animation's buffers, and force a draw update

                buffer.width = width;
                buffer.height = height;
                buffer.buffer = termbox.tb_cell_buffer();

                switch (config.animation) {
                    .none => {},
                    .doom => doom.realloc() catch {
                        try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
                    },
                    .matrix => matrix.realloc() catch {
                        try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
                    },
                }

                update = true;
                resolution_changed = true;
            }
        }

        if (update) {
            // If the user entered a wrong password 10 times in a row, play a cascade animation, else update normally
            if (auth_fails < config.auth_fails) {
                _ = termbox.tb_clear();

                if (!animation_timed_out) {
                    switch (config.animation) {
                        .none => {},
                        .doom => doom.draw(),
                        .matrix => matrix.draw(),
                    }
                }

                if (config.bigclock != .none and buffer.box_height + (bigclock.HEIGHT + 2) * 2 < buffer.height) draw_big_clock: {
                    const format = "%H:%M";
                    const xo = buffer.width / 2 - @min(buffer.width, (format.len * (bigclock.WIDTH + 1))) / 2;
                    const yo = (buffer.height - buffer.box_height) / 2 - bigclock.HEIGHT - 2;

                    var clock_buf: [format.len + 1:0]u8 = undefined;
                    const clock_str = interop.timeAsString(&clock_buf, format) catch {
                        break :draw_big_clock;
                    };

                    for (clock_str, 0..) |c, i| {
                        const clock_cell = bigclock.clockCell(animate, c, buffer.fg, buffer.bg, config.bigclock);
                        bigclock.alphaBlit(xo + i * (bigclock.WIDTH + 1), yo, buffer.width, buffer.height, clock_cell);
                    }
                }

                buffer.drawBoxCenter(!config.hide_borders, config.blank_box);

                if (resolution_changed) {
                    const coordinates = buffer.calculateComponentCoordinates();
                    info_line.label.position(coordinates.start_x, coordinates.y, coordinates.full_visible_length, null);
                    session.label.position(coordinates.x, coordinates.y + 2, coordinates.visible_length, config.text_in_center);
                    login.position(coordinates.x, coordinates.y + 4, coordinates.visible_length);
                    password.position(coordinates.x, coordinates.y + 6, coordinates.visible_length);

                    resolution_changed = false;
                }

                switch (active_input) {
                    .info_line => info_line.label.handle(null, insert_mode),
                    .session => session.label.handle(null, insert_mode),
                    .login => login.handle(null, insert_mode) catch {
                        try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
                    },
                    .password => password.handle(null, insert_mode) catch {
                        try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
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

                info_line.label.draw();

                if (!config.hide_key_hints) {
                    var length: usize = 0;

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
                        length += sleep_len + 1;
                    }

                    buffer.drawLabel(config.brightness_down_key, length, 0);
                    length += config.brightness_down_key.len + 1;
                    buffer.drawLabel(" ", length - 1, 0);

                    buffer.drawLabel(lang.brightness_down, length, 0);
                    length += brightness_down_len + 1;

                    buffer.drawLabel(config.brightness_up_key, length, 0);
                    length += config.brightness_up_key.len + 1;
                    buffer.drawLabel(" ", length - 1, 0);

                    buffer.drawLabel(lang.brightness_up, length, 0);
                    length += brightness_up_len + 1;
                }

                if (config.box_title) |title| {
                    buffer.drawConfinedLabel(title, buffer.box_x, buffer.box_y - 1, buffer.box_width);
                }

                if (config.vi_mode) {
                    const label_txt = if (insert_mode) lang.insert else lang.normal;
                    buffer.drawLabel(label_txt, buffer.box_x, buffer.box_y + buffer.box_height);
                }

                draw_lock_state: {
                    const lock_state = interop.getLockState(config.console_dev) catch {
                        try info_line.addMessage(lang.err_console_dev, config.error_bg, config.error_fg);
                        break :draw_lock_state;
                    };

                    var lock_state_x = buffer.width - @min(buffer.width, lang.numlock.len);
                    const lock_state_y: usize = if (config.clock != null) 1 else 0;

                    if (lock_state.numlock) buffer.drawLabel(lang.numlock, lock_state_x, lock_state_y);

                    if (lock_state_x >= lang.capslock.len + 1) {
                        lock_state_x -= lang.capslock.len + 1;
                        if (lock_state.capslock) buffer.drawLabel(lang.capslock, lock_state_x, lock_state_y);
                    }
                }

                session.label.draw();
                login.draw();
                password.draw();
            } else {
                std.time.sleep(std.time.ns_per_ms * 10);
                update = buffer.cascade();

                if (!update) {
                    std.time.sleep(std.time.ns_per_s * 7);
                    auth_fails = 0;
                }
            }

            _ = termbox.tb_present();
        }

        var timeout: i32 = -1;

        // Calculate the maximum timeout based on current animations, or the (big) clock. If there's none, we wait for the event indefinitely instead
        if (animate and !animation_timed_out) {
            timeout = config.min_refresh_delta;

            // check how long we have been running so we can turn off the animation
            var tv: interop.system_time.timeval = undefined;
            _ = interop.system_time.gettimeofday(&tv, null);

            if (config.animation_timeout_sec > 0 and tv.tv_sec - tv_zero.tv_sec > config.animation_timeout_sec) {
                animation_timed_out = true;
                switch (config.animation) {
                    .none => {},
                    .doom => doom.deinit(),
                    .matrix => matrix.deinit(),
                }
            }
        } else if (config.bigclock != .none and config.clock == null) {
            var tv: interop.system_time.timeval = undefined;
            _ = interop.system_time.gettimeofday(&tv, null);

            timeout = @intCast((60 - @rem(tv.tv_sec, 60)) * 1000 - @divTrunc(tv.tv_usec, 1000) + 1);
        } else if (config.clock != null or auth_fails >= config.auth_fails) {
            var tv: interop.system_time.timeval = undefined;
            _ = interop.system_time.gettimeofday(&tv, null);

            timeout = @intCast(1000 - @divTrunc(tv.tv_usec, 1000) + 1);
        }

        const event_error = if (timeout == -1) termbox.tb_poll_event(&event) else termbox.tb_peek_event(&event, timeout);

        update = timeout != -1;

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
                        var sleep = std.process.Child.init(&[_][]const u8{ "/bin/sh", "-c", sleep_cmd }, allocator);
                        sleep.stdout_behavior = .Ignore;
                        sleep.stderr_behavior = .Ignore;

                        handle_sleep_cmd: {
                            const process_result = sleep.spawnAndWait() catch {
                                break :handle_sleep_cmd;
                            };
                            if (process_result.Exited != 0) {
                                try info_line.addMessage(lang.err_sleep, config.error_bg, config.error_fg);
                            }
                        }
                    }
                } else if (pressed_key == brightness_down_key or pressed_key == brightness_up_key) {
                    const cmd = if (pressed_key == brightness_down_key) config.brightness_down_cmd else config.brightness_up_cmd;

                    var brightness = std.process.Child.init(&[_][]const u8{ "/bin/sh", "-c", cmd }, allocator);
                    brightness.stdout_behavior = .Ignore;
                    brightness.stderr_behavior = .Ignore;

                    handle_brightness_cmd: {
                        const process_result = brightness.spawnAndWait() catch {
                            break :handle_brightness_cmd;
                        };
                        if (process_result.Exited != 0) {
                            try info_line.addMessage(lang.err_brightness_change, config.error_bg, config.error_fg);
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
                    .session, .info_line => .info_line,
                    .login => .session,
                    .password => .login,
                };
                update = true;
            },
            termbox.TB_KEY_CTRL_J, termbox.TB_KEY_ARROW_DOWN => {
                active_input = switch (active_input) {
                    .info_line => .session,
                    .session => .login,
                    .login, .password => .password,
                };
                update = true;
            },
            termbox.TB_KEY_TAB => {
                active_input = switch (active_input) {
                    .info_line => .session,
                    .session => .login,
                    .login => .password,
                    .password => .info_line,
                };
                update = true;
            },
            termbox.TB_KEY_BACK_TAB => {
                active_input = switch (active_input) {
                    .info_line => .password,
                    .session => .info_line,
                    .login => .session,
                    .password => .login,
                };

                update = true;
            },
            termbox.TB_KEY_ENTER => {
                try info_line.addMessage(lang.authenticating, config.bg, config.fg);
                InfoLine.clearRendered(allocator, buffer) catch {
                    try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
                };
                info_line.label.draw();
                _ = termbox.tb_present();

                if (config.save) save_last_settings: {
                    var file = std.fs.cwd().createFile(save_path, .{}) catch break :save_last_settings;
                    defer file.close();

                    const save_data = Save{
                        .user = login.text.items,
                        .session_index = session.label.current,
                    };
                    ini.writeFromStruct(save_data, file.writer(), null, true, .{}) catch break :save_last_settings;

                    // Delete previous save file if it exists
                    if (migrator.maybe_save_file) |path| std.fs.cwd().deleteFile(path) catch {};
                }

                var shared_err = try SharedError.init();
                defer shared_err.deinit();

                {
                    const login_text = try allocator.dupeZ(u8, login.text.items);
                    defer allocator.free(login_text);
                    const password_text = try allocator.dupeZ(u8, password.text.items);
                    defer allocator.free(password_text);

                    // Give up control on the TTY
                    _ = termbox.tb_shutdown();

                    session_pid = try std.posix.fork();
                    if (session_pid == 0) {
                        const current_environment = session.label.list.items[session.label.current];
                        auth.authenticate(config, current_environment, login_text, password_text) catch |err| {
                            shared_err.writeError(err);
                            std.process.exit(1);
                        };
                        std.process.exit(0);
                    }

                    _ = std.posix.waitpid(session_pid, 0);
                    session_pid = -1;
                }

                // Take back control of the TTY
                _ = termbox.tb_init();
                _ = termbox.tb_set_output_mode(termbox.TB_OUTPUT_NORMAL);

                const auth_err = shared_err.readError();
                if (auth_err) |err| {
                    auth_fails += 1;
                    active_input = .password;
                    try info_line.addMessage(getAuthErrorMsg(err, lang), config.error_bg, config.error_fg);
                    if (config.clear_password or err != error.PamAuthError) password.clear();
                } else {
                    if (config.logout_cmd) |logout_cmd| {
                        var logout_process = std.process.Child.init(&[_][]const u8{ "/bin/sh", "-c", logout_cmd }, allocator);
                        _ = logout_process.spawnAndWait() catch .{};
                    }

                    password.clear();
                    try info_line.addMessage(lang.logout, config.bg, config.fg);
                }

                try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, tb_termios);
                if (auth_fails < config.auth_fails) _ = termbox.tb_clear();

                update = true;

                // Restore the cursor
                _ = termbox.tb_set_cursor(0, 0);
                _ = termbox.tb_present();
            },
            else => {
                if (!insert_mode) {
                    switch (event.ch) {
                        'k' => {
                            active_input = switch (active_input) {
                                .session, .info_line => .info_line,
                                .login => .session,
                                .password => .login,
                            };
                            update = true;
                            continue;
                        },
                        'j' => {
                            active_input = switch (active_input) {
                                .info_line => .session,
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
                    .info_line => info_line.label.handle(&event, insert_mode),
                    .session => session.label.handle(&event, insert_mode),
                    .login => login.handle(&event, insert_mode) catch {
                        try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
                    },
                    .password => password.handle(&event, insert_mode) catch {
                        try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
                    },
                }
                update = true;
            },
        }
    }
}

fn getAuthErrorMsg(err: anyerror, lang: Lang) []const u8 {
    return switch (err) {
        error.GetPasswordNameFailed => lang.err_pwnam,
        error.GetEnvListFailed => lang.err_envlist,
        error.XauthFailed => lang.err_xauth,
        error.XcbConnectionFailed => lang.err_xcb_conn,
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
