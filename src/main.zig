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
const Config = @import("config/Config.zig");
const ConfigReader = @import("config/ConfigReader.zig");
const Lang = @import("config/Lang.zig");

const termbox = interop.termbox;

const LY_VERSION = "1.0.0";

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
    var info_line: []const u8 = undefined;

    if (res.args.help != 0) {
        try clap.help(stderr, clap.Help, &params, .{});

        _ = try stderr.write("Note: if you want to configure Ly, please check the config file, which is usually located at /etc/ly/config.ini.\n");
        std.os.exit(0);
    }
    if (res.args.version != 0) {
        _ = try stderr.write("Ly version " ++ LY_VERSION ++ "\n");
        std.os.exit(0);
    }

    // Load configuration file
    var config_reader = ConfigReader.init(allocator);
    defer config_reader.deinit();

    if (res.args.config) |s| {
        const trailing_slash = if (s[s.len - 1] != '/') "/" else "";

        const config_path = try std.fmt.allocPrint(allocator, "{s}{s}config.ini", .{ s, trailing_slash });
        defer allocator.free(config_path);

        config = try config_reader.readConfig(config_path);

        const lang_path = try std.fmt.allocPrint(allocator, "{s}{s}lang/{s}.ini", .{ s, trailing_slash, config.ly.lang });
        defer allocator.free(lang_path);

        lang = try config_reader.readLang(lang_path);
    } else {
        config = try config_reader.readConfig(build_options.data_directory ++ "/config.ini");

        const lang_path = try std.fmt.allocPrint(allocator, "{s}/lang/{s}.ini", .{ build_options.data_directory, config.ly.lang });
        defer allocator.free(lang_path);

        lang = try config_reader.readLang(lang_path);
    }

    // Initialize information line with host name
    var got_host_name = false;
    var host_name_buffer: []u8 = undefined;

    get_host_name: {
        const host_name_struct = interop.getHostName(allocator) catch |err| {
            if (err == error.CannotGetHostName) {
                info_line = lang.ly.err_hostname;
            } else {
                info_line = lang.ly.err_alloc;
            }
            break :get_host_name;
        };

        got_host_name = true;
        host_name_buffer = host_name_struct.buffer;
        info_line = host_name_struct.slice;
    }

    // Initialize termbox
    _ = termbox.tb_init();
    defer termbox.tb_shutdown();

    _ = termbox.tb_select_output_mode(termbox.TB_OUTPUT_NORMAL);
    termbox.tb_clear();

    // Initialize terminal buffer
    const labels_max_length = @max(lang.ly.login.len, lang.ly.password.len);

    var buffer = TerminalBuffer.init(config.ly.margin_box_v, config.ly.margin_box_h, config.ly.input_len, labels_max_length, config.ly.fg, config.ly.bg);

    // Initialize components
    var desktop = try Desktop.init(allocator, &buffer, config.ly.max_desktop_len);
    defer desktop.deinit();

    desktop.addEnvironment(lang.ly.shell, "", .shell) catch {
        info_line = lang.ly.err_alloc;
    };
    desktop.addEnvironment(lang.ly.xinitrc, config.ly.xinitrc, .xinitrc) catch {
        info_line = lang.ly.err_alloc;
    };

    try desktop.crawl(config.ly.waylandsessions, .wayland);
    try desktop.crawl(config.ly.xsessions, .x11);

    var login = try Text.init(allocator, &buffer, config.ly.max_login_len);
    defer login.deinit();

    var password = try Text.init(allocator, &buffer, config.ly.max_password_len);
    defer password.deinit();

    // Load last saved username and desktop selection, if any
    if (config.ly.load) load_last_saved: {
        var file = std.fs.openFileAbsolute(config.ly.save_file, .{}) catch break :load_last_saved;
        defer file.close();

        const reader = file.reader();
        const username_length = try reader.readIntLittle(u64);

        const username_buffer = try allocator.alloc(u8, username_length);
        defer allocator.free(username_buffer);

        _ = try reader.read(username_buffer);

        const current_desktop = try reader.readIntLittle(u64);

        if (username_buffer.len > 0) {
            try login.text.appendSlice(username_buffer);
            login.end = username_buffer.len;
        }

        if (current_desktop < desktop.environments.items.len) desktop.current = current_desktop;
    }

    var active_input = if (config.ly.default_input == .login and login.text.items.len != login.end) .password else config.ly.default_input;

    // Place components on the screen
    {
        buffer.drawBoxCenter(!config.ly.hide_borders, config.ly.blank_box);

        const coordinates = buffer.calculateComponentCoordinates();
        desktop.position(coordinates.x, coordinates.y + 2, coordinates.visible_length);
        login.position(coordinates.x, coordinates.y + 4, coordinates.visible_length);
        password.position(coordinates.x, coordinates.y + 6, coordinates.visible_length);

        switch (active_input) {
            .session => desktop.handle(null),
            .login => login.handle(null) catch {
                info_line = lang.ly.err_alloc;
            },
            .password => password.handle(null) catch {
                info_line = lang.ly.err_alloc;
            },
        }
    }

    // Initialize the animation, if any
    var doom: Doom = undefined;
    var matrix: Matrix = undefined;

    switch (config.ly.animation) {
        .none => {},
        .doom => doom = try Doom.init(allocator, &buffer),
        .matrix => matrix = try Matrix.init(allocator, &buffer),
    }
    defer {
        switch (config.ly.animation) {
            .none => {},
            .doom => doom.deinit(),
            .matrix => matrix.deinit(),
        }
    }

    const animate = config.ly.animation != .none;
    const has_clock = config.ly.clock.len > 0;
    const shutdown_key = try std.fmt.parseInt(u8, config.ly.shutdown_key[1..], 10);
    const restart_key = try std.fmt.parseInt(u8, config.ly.restart_key[1..], 10);

    var event = std.mem.zeroes(termbox.tb_event);
    var run = true;
    var update = true;
    var resolution_changed = false;
    var shutdown = false;
    var restart = false;
    var auth_fails: u64 = 0;

    // Switch to selected TTY if possible
    open_console_dev: {
        const console_dev_z = allocator.dupeZ(u8, config.ly.console_dev) catch {
            info_line = lang.ly.err_alloc;
            break :open_console_dev;
        };
        defer allocator.free(console_dev_z);

        const fd = std.c.open(console_dev_z, interop.O_WRONLY);
        defer _ = std.c.close(fd);

        if (fd < 0) {
            info_line = lang.ly.err_console_dev;
            break :open_console_dev;
        }

        _ = std.c.ioctl(fd, interop.VT_ACTIVATE, config.ly.tty);
        _ = std.c.ioctl(fd, interop.VT_WAITACTIVE, config.ly.tty);
    }

    while (run) {
        // If there's no input or there's an animation, a resolution change needs to be checked
        if (!update or config.ly.animation != .none) {
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

                switch (config.ly.animation) {
                    .none => {},
                    .doom => doom.realloc() catch {
                        info_line = lang.ly.err_alloc;
                    },
                    .matrix => matrix.realloc() catch {
                        info_line = lang.ly.err_alloc;
                    },
                }

                update = true;
            }
        }

        if (update) {
            // If the user entered a wrong password 10 times in a row, play a cascade animation, else update normally
            if (auth_fails < 10) {
                switch (active_input) {
                    .session => desktop.handle(null),
                    .login => login.handle(null) catch {
                        info_line = lang.ly.err_alloc;
                    },
                    .password => password.handle(null) catch {
                        info_line = lang.ly.err_alloc;
                    },
                }

                termbox.tb_clear();

                switch (config.ly.animation) {
                    .none => {},
                    .doom => doom.draw(),
                    .matrix => matrix.draw(),
                }

                if (config.ly.bigclock and buffer.box_height + (bigclock.HEIGHT + 2) * 2 < buffer.height) draw_big_clock: {
                    const format = "%H:%M";
                    const xo = buffer.width / 2 - (format.len * (bigclock.WIDTH + 1)) / 2;
                    const yo = (buffer.height - buffer.box_height) / 2 - bigclock.HEIGHT - 2;

                    const clock_str = interop.timeAsString(allocator, format, format.len + 1) catch {
                        info_line = lang.ly.err_alloc;
                        break :draw_big_clock;
                    };
                    defer allocator.free(clock_str);

                    for (0..format.len) |i| {
                        const clock_cell = bigclock.clockCell(animate, clock_str[i], buffer.fg, buffer.bg);
                        bigclock.alphaBlit(buffer.buffer, xo + i * (bigclock.WIDTH + 1), yo, buffer.width, buffer.height, clock_cell);
                    }
                }

                buffer.drawBoxCenter(!config.ly.hide_borders, config.ly.blank_box);

                if (has_clock) draw_clock: {
                    const clock_buffer = interop.timeAsString(allocator, config.ly.clock, 32) catch {
                        info_line = lang.ly.err_alloc;
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

                buffer.drawLabel(lang.ly.login, label_x, label_y + 4);
                buffer.drawLabel(lang.ly.password, label_x, label_y + 6);

                if (info_line.len > 0) {
                    const x = buffer.box_x + ((buffer.box_width - info_line.len) / 2);
                    buffer.drawLabel(info_line, x, label_y);
                }

                if (!config.ly.hide_key_hints) {
                    var length: u64 = 0;

                    buffer.drawLabel(config.ly.shutdown_key, length, 0);
                    length += config.ly.shutdown_key.len + 1;

                    buffer.drawLabel(lang.ly.shutdown, length, 0);
                    length += lang.ly.shutdown.len + 1;

                    buffer.drawLabel(config.ly.restart_key, length, 0);
                    length += config.ly.restart_key.len + 1;

                    buffer.drawLabel(lang.ly.restart, length, 0);
                    length += lang.ly.restart.len + 1;
                }

                draw_lock_state: {
                    const lock_state = interop.getLockState(allocator, config.ly.console_dev) catch |err| {
                        if (err == error.CannotOpenConsoleDev) {
                            info_line = lang.ly.err_console_dev;
                        } else {
                            info_line = lang.ly.err_alloc;
                        }
                        break :draw_lock_state;
                    };

                    var lock_state_x = buffer.width - lang.ly.numlock.len;
                    const lock_state_y: u64 = if (has_clock) 1 else 0;

                    if (lock_state.numlock) buffer.drawLabel(lang.ly.numlock, lock_state_x, lock_state_y);
                    lock_state_x -= lang.ly.capslock.len + 1;
                    if (lock_state.capslock) buffer.drawLabel(lang.ly.capslock, lock_state_x, lock_state_y);
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
                password.drawMasked(config.ly.asterisk);

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
            timeout = config.ly.min_refresh_delta;
        } else if (config.ly.bigclock and config.ly.clock.len == 0) {
            var tv = std.mem.zeroes(std.c.timeval);
            _ = std.c.gettimeofday(&tv, null);

            timeout = @intCast((60 - @rem(tv.tv_sec, 60)) * 1000 - @divTrunc(tv.tv_usec, 1000) + 1);
        } else if (config.ly.clock.len > 0 or auth_fails >= 10) {
            var tv = std.mem.zeroes(std.c.timeval);
            _ = std.c.gettimeofday(&tv, null);

            timeout = @intCast(1000 - @divTrunc(tv.tv_usec, 1000) + 1);
        }

        const event_error = if (timeout == -1) termbox.tb_poll_event(&event) else termbox.tb_peek_event(&event, timeout);

        if (event_error < 0 or event.type != termbox.TB_EVENT_KEY) continue;

        switch (event.key) {
            termbox.TB_KEY_F1, termbox.TB_KEY_F2, termbox.TB_KEY_F3, termbox.TB_KEY_F4, termbox.TB_KEY_F5, termbox.TB_KEY_F6, termbox.TB_KEY_F7, termbox.TB_KEY_F8, termbox.TB_KEY_F9, termbox.TB_KEY_F10, termbox.TB_KEY_F11, termbox.TB_KEY_F12 => {
                if (0xFFFF - event.key + 1 == shutdown_key) {
                    shutdown = true;
                    run = false;
                } else if (0xFFFF - event.key + 1 == restart_key) {
                    restart = true;
                    run = false;
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
            termbox.TB_KEY_ENTER => authenticate: {
                if (config.ly.save) save_last_settings: {
                    var file = std.fs.createFileAbsolute(config.ly.save_file, .{}) catch break :save_last_settings;
                    defer file.close();

                    const writer = file.writer();
                    try writer.writeIntLittle(u64, login.end);
                    _ = try writer.write(login.text.items);
                    try writer.writeIntLittle(u64, desktop.current);
                }

                var has_error = false;

                auth.authenticate(
                    allocator,
                    config.ly.tty,
                    desktop,
                    login,
                    &password,
                    config.ly.service_name,
                    config.ly.path,
                    config.ly.term_reset_cmd,
                    config.ly.wayland_cmd,
                ) catch {
                    has_error = true;
                    auth_fails += 1;
                    active_input = .password;

                    // TODO: Errors in info_line

                    if (config.ly.blank_password) password.clear();
                };
                update = true;

                if (!has_error) info_line = lang.ly.logout;
                std.process.execv(allocator, &[_][]const u8{ "/bin/sh", "-c", config.ly.term_restore_cursor_cmd }) catch break :authenticate;
            },
            else => {
                switch (active_input) {
                    .session => desktop.handle(&event),
                    .login => login.handle(&event) catch {
                        info_line = lang.ly.err_alloc;
                    },
                    .password => password.handle(&event) catch {
                        info_line = lang.ly.err_alloc;
                    },
                }
                update = true;
            },
        }
    }

    if (got_host_name) allocator.free(host_name_buffer);

    if (shutdown) {
        return std.process.execv(allocator, &[_][]const u8{ "/bin/sh", "-c", config.ly.shutdown_cmd });
    } else if (restart) {
        return std.process.execv(allocator, &[_][]const u8{ "/bin/sh", "-c", config.ly.restart_cmd });
    }
}
