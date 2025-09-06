const std = @import("std");
const build_options = @import("build_options");
const builtin = @import("builtin");
const clap = @import("clap");
const ini = @import("zigini");
const auth = @import("auth.zig");
const bigclock = @import("bigclock.zig");
const enums = @import("enums.zig");
const Environment = @import("Environment.zig");
const interop = @import("interop.zig");
const ColorMix = @import("animations/ColorMix.zig");
const Doom = @import("animations/Doom.zig");
const Metaballs = @import("animations/Metaballs.zig");
const Dummy = @import("animations/Dummy.zig");
const Matrix = @import("animations/Matrix.zig");
const GameOfLife = @import("animations/GameOfLife.zig");
const Animation = @import("tui/Animation.zig");
const TerminalBuffer = @import("tui/TerminalBuffer.zig");
const Session = @import("tui/components/Session.zig");
const Text = @import("tui/components/Text.zig");
const InfoLine = @import("tui/components/InfoLine.zig");
const UserList = @import("tui/components/UserList.zig");
const Config = @import("config/Config.zig");
const Lang = @import("config/Lang.zig");
const Save = @import("config/Save.zig");
const migrator = @import("config/migrator.zig");
const SharedError = @import("SharedError.zig");
const UidRange = @import("UidRange.zig");

const StringList = std.ArrayListUnmanaged([]const u8);
const Ini = ini.Ini;
const DisplayServer = enums.DisplayServer;
const Entry = Environment.Entry;
const termbox = interop.termbox;
const unistd = interop.unistd;
const temporary_allocator = std.heap.page_allocator;
const ly_top_str = "Ly version " ++ build_options.version;

var session_pid: std.posix.pid_t = -1;
fn signalHandler(i: c_int) callconv(.C) void {
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

fn ttyControlTransferSignalHandler(_: c_int) callconv(.C) void {
    _ = termbox.tb_shutdown();
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
            stderr.print("error: couldn't shutdown: {s}\n", .{@errorName(shutdown_error)}) catch std.process.exit(1);
        } else if (restart) {
            const restart_error = std.process.execv(temporary_allocator, &[_][]const u8{ "/bin/sh", "-c", restart_cmd });
            stderr.print("error: couldn't restart: {s}\n", .{@errorName(restart_error)}) catch std.process.exit(1);
        } else {
            // The user has quit Ly using Ctrl+C
            temporary_allocator.free(shutdown_cmd);
            temporary_allocator.free(restart_cmd);
        }
    }

    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();

    // Allows stopping an animation after some time
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
    var can_get_lock_state = true;
    var can_draw_clock = true;

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

        config = config_ini.readFileToStruct(config_path, .{
            .fieldHandler = migrator.configFieldHandler,
            .comment_characters = comment_characters,
        }) catch _config: {
            config_load_failed = true;
            break :_config Config{};
        };

        const lang_path = try std.fmt.allocPrint(allocator, "{s}{s}lang/{s}.ini", .{ s, trailing_slash, config.lang });
        defer allocator.free(lang_path);

        lang = lang_ini.readFileToStruct(lang_path, .{
            .fieldHandler = null,
            .comment_characters = comment_characters,
        }) catch Lang{};

        if (config.load) {
            save_path = try std.fmt.allocPrint(allocator, "{s}{s}save.ini", .{ s, trailing_slash });
            save_path_alloc = true;

            var user_buf: [32]u8 = undefined;
            save = save_ini.readFileToStruct(save_path, .{
                .fieldHandler = null,
                .comment_characters = comment_characters,
            }) catch migrator.tryMigrateSaveFile(&user_buf);
        }

        if (!config_load_failed) {
            migrator.lateConfigFieldHandler(&config);
        }
    } else {
        const config_path = build_options.config_directory ++ "/ly/config.ini";

        config = config_ini.readFileToStruct(config_path, .{
            .fieldHandler = migrator.configFieldHandler,
            .comment_characters = comment_characters,
        }) catch _config: {
            config_load_failed = true;
            break :_config Config{};
        };

        const lang_path = try std.fmt.allocPrint(allocator, "{s}/ly/lang/{s}.ini", .{ build_options.config_directory, config.lang });
        defer allocator.free(lang_path);

        lang = lang_ini.readFileToStruct(lang_path, .{
            .fieldHandler = null,
            .comment_characters = comment_characters,
        }) catch Lang{};

        if (config.load) {
            var user_buf: [32]u8 = undefined;
            save = save_ini.readFileToStruct(save_path, .{
                .fieldHandler = null,
                .comment_characters = comment_characters,
            }) catch migrator.tryMigrateSaveFile(&user_buf);
        }

        if (!config_load_failed) {
            migrator.lateConfigFieldHandler(&config);
        }
    }

    var log_file: std.fs.File = undefined;
    defer log_file.close();

    var could_open_log_file = true;
    open_log_file: {
        log_file = std.fs.cwd().openFile(config.ly_log, .{ .mode = .write_only }) catch std.fs.cwd().createFile(config.ly_log, .{ .mode = 0o666 }) catch {
            // If we could neither open an existing log file nor create a new
            // one, abort.
            could_open_log_file = false;
            break :open_log_file;
        };
    }

    if (!could_open_log_file) {
        log_file = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    }

    const log_writer = log_file.writer();

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
    try log_writer.writeAll("initializing termbox2\n");
    _ = termbox.tb_init();
    defer {
        log_writer.writeAll("shutting down termbox2\n") catch {};
        _ = termbox.tb_shutdown();
    }

    const act = std.posix.Sigaction{
        .handler = .{ .handler = &signalHandler },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.TERM, &act, null);

    if (config.full_color) {
        _ = termbox.tb_set_output_mode(termbox.TB_OUTPUT_TRUECOLOR);
        try log_writer.writeAll("termbox2 set to 24-bit color output mode\n");
    } else {
        try log_writer.writeAll("termbox2 set to eight-color output mode\n");
    }

    _ = termbox.tb_clear();

    // Let's take some precautions here and clear the back buffer as well
    try ttyClearScreen();

    // Needed to reset termbox after auth
    const tb_termios = try std.posix.tcgetattr(std.posix.STDIN_FILENO);

    // Initialize terminal buffer
    const labels_max_length = @max(lang.login.len, lang.password.len);

    var seed: u64 = undefined;
    std.crypto.random.bytes(std.mem.asBytes(&seed)); // Get a random seed for the PRNG (used by animations)

    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    const buffer_options = TerminalBuffer.InitOptions{
        .fg = config.fg,
        .bg = config.bg,
        .border_fg = config.border_fg,
        .margin_box_h = config.margin_box_h,
        .margin_box_v = config.margin_box_v,
        .input_len = config.input_len,
    };
    var buffer = TerminalBuffer.init(buffer_options, labels_max_length, random);

    try log_writer.print("screen resolution is {d}x{d}\n", .{ buffer.width, buffer.height });

    // Initialize components
    var info_line = InfoLine.init(allocator, &buffer);
    defer info_line.deinit();

    if (config_load_failed) {
        // We can't localize this since the config failed to load so we'd fallback to the default language anyway
        try info_line.addMessage("unable to parse config file", config.error_bg, config.error_fg);
        try log_writer.writeAll("unable to parse config file\n");
    }

    if (!could_open_log_file) {
        try info_line.addMessage(lang.err_log, config.error_bg, config.error_fg);
        try log_writer.writeAll("failed to open log file\n");
    }

    interop.setNumlock(config.numlock) catch |err| {
        try info_line.addMessage(lang.err_numlock, config.error_bg, config.error_fg);
        try log_writer.print("failed to set numlock: {s}\n", .{@errorName(err)});
    };

    var session = Session.init(allocator, &buffer);
    defer session.deinit();

    addOtherEnvironment(&session, lang, .shell, null) catch |err| {
        try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
        try log_writer.print("failed to add shell environment: {s}\n", .{@errorName(err)});
    };

    if (build_options.enable_x11_support) {
        if (config.xinitrc) |xinitrc_cmd| {
            addOtherEnvironment(&session, lang, .xinitrc, xinitrc_cmd) catch |err| {
                try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
                try log_writer.print("failed to add xinitrc environment: {s}\n", .{@errorName(err)});
            };
        }
    } else {
        try info_line.addMessage(lang.no_x11_support, config.bg, config.fg);
        try log_writer.writeAll("x11 support disabled at compile-time\n");
    }

    if (config.initial_info_text) |text| {
        try info_line.addMessage(text, config.bg, config.fg);
    } else get_host_name: {
        // Initialize information line with host name
        var name_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
        const hostname = std.posix.gethostname(&name_buf) catch |err| {
            try info_line.addMessage(lang.err_hostname, config.error_bg, config.error_fg);
            try log_writer.print("failed to get hostname: {s}\n", .{@errorName(err)});
            break :get_host_name;
        };
        try info_line.addMessage(hostname, config.bg, config.fg);
    }

    // Crawl session directories (Wayland, X11 and custom respectively)
    var wayland_session_dirs = std.mem.splitScalar(u8, config.waylandsessions, ':');
    while (wayland_session_dirs.next()) |dir| {
        try crawl(&session, lang, dir, .wayland);
    }

    if (build_options.enable_x11_support) {
        var x_session_dirs = std.mem.splitScalar(u8, config.xsessions, ':');
        while (x_session_dirs.next()) |dir| {
            try crawl(&session, lang, dir, .x11);
        }
    }

    var custom_session_dirs = std.mem.splitScalar(u8, config.custom_sessions, ':');
    while (custom_session_dirs.next()) |dir| {
        try crawl(&session, lang, dir, .custom);
    }

    var usernames = try getAllUsernames(allocator, config.login_defs_path);
    defer {
        for (usernames.items) |username| allocator.free(username);
        usernames.deinit(allocator);
    }

    if (usernames.items.len == 0) {
        // If we have no usernames, simply add an error to the info line.
        // This effectively means you can't login, since there would be no local
        // accounts *and* no root account...but at this point, if that's the
        // case, you have bigger problems to deal with in the first place. :D
        try info_line.addMessage(lang.err_no_users, config.error_bg, config.error_fg);
        try log_writer.writeAll("no users found\n");
    }

    var login = try UserList.init(allocator, &buffer, usernames);
    defer login.deinit();

    var password = Text.init(allocator, &buffer, true, config.asterisk);
    defer password.deinit();

    var active_input = config.default_input;
    var insert_mode = !config.vi_mode or config.vi_default_mode == .insert;

    // Load last saved username and desktop selection, if any
    if (config.load) {
        if (save.user) |user| {
            // Find user with saved name, and switch over to it
            // If it doesn't exist (anymore), we don't change the value
            // Note that we could instead save the username index, but migrating
            // from the raw username to an index is non-trivial and I'm lazy :P
            for (usernames.items, 0..) |username, i| {
                if (std.mem.eql(u8, username, user)) {
                    login.label.current = i;
                    break;
                }
            }

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
        login.label.position(coordinates.x, coordinates.y + 4, coordinates.visible_length, config.text_in_center);
        password.position(coordinates.x, coordinates.y + 6, coordinates.visible_length);

        switch (active_input) {
            .info_line => info_line.label.handle(null, insert_mode),
            .session => session.label.handle(null, insert_mode),
            .login => login.label.handle(null, insert_mode),
            .password => password.handle(null, insert_mode) catch |err| {
                try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
                try log_writer.print("failed to handle password input: {s}\n", .{@errorName(err)});
            },
        }
    }

    // Initialize the animation, if any
    var animation: Animation = undefined;

    switch (config.animation) {
        .none => {
            var dummy = Dummy{};
            animation = dummy.animation();
        },
        .doom => {
            var doom = try Doom.init(allocator, &buffer, config.doom_top_color, config.doom_middle_color, config.doom_bottom_color, config.doom_fire_height, config.doom_fire_spread);
            animation = doom.animation();
        },
        .matrix => {
            var matrix = try Matrix.init(allocator, &buffer, config.cmatrix_fg, config.cmatrix_head_col, config.cmatrix_min_codepoint, config.cmatrix_max_codepoint);
            animation = matrix.animation();
        },
        .colormix => {
            var color_mix = ColorMix.init(&buffer, config.colormix_col1, config.colormix_col2, config.colormix_col3);
            animation = color_mix.animation();
        },
        .gameoflife => {
            var game_of_life = try GameOfLife.init(allocator, &buffer, config.gameoflife_fg, config.gameoflife_entropy_interval, config.gameoflife_frame_delay, config.gameoflife_initial_density);
            animation = game_of_life.animation();
        },
        .metaballs => {
            var metaballs = try Metaballs.init(allocator, &buffer);
            animation = metaballs.animation();
        },
    }
    defer animation.deinit();

    const animate = config.animation != .none;
    const shutdown_key = try std.fmt.parseInt(u8, config.shutdown_key[1..], 10);
    const shutdown_len = try TerminalBuffer.strWidth(lang.shutdown);
    const restart_key = try std.fmt.parseInt(u8, config.restart_key[1..], 10);
    const restart_len = try TerminalBuffer.strWidth(lang.restart);
    const sleep_key = try std.fmt.parseInt(u8, config.sleep_key[1..], 10);
    const sleep_len = try TerminalBuffer.strWidth(lang.sleep);
    const brightness_down_key = if (config.brightness_down_key) |key| try std.fmt.parseInt(u8, key[1..], 10) else null;
    const brightness_down_len = try TerminalBuffer.strWidth(lang.brightness_down);
    const brightness_up_key = if (config.brightness_up_key) |key| try std.fmt.parseInt(u8, key[1..], 10) else null;
    const brightness_up_len = try TerminalBuffer.strWidth(lang.brightness_up);

    var event: termbox.tb_event = undefined;
    var run = true;
    var update = true;
    var resolution_changed = false;
    var auth_fails: u64 = 0;

    // Switch to selected TTY
    interop.switchTty(config.tty) catch |err| {
        try info_line.addMessage(lang.err_switch_tty, config.error_bg, config.error_fg);
        try log_writer.print("failed to switch tty: {s}\n", .{@errorName(err)});
    };

    while (run) {
        // If there's no input or there's an animation, a resolution change needs to be checked
        if (!update or animate) {
            if (!update) std.Thread.sleep(std.time.ns_per_ms * 100);

            _ = termbox.tb_present(); // Required to update tb_width() and tb_height()

            const width: usize = @intCast(termbox.tb_width());
            const height: usize = @intCast(termbox.tb_height());

            if (width != buffer.width or height != buffer.height) {
                // If it did change, then update the cell buffer, reallocate the current animation's buffers, and force a draw update
                try log_writer.print("screen resolution updated to {d}x{d}\n", .{ width, height });

                buffer.width = width;
                buffer.height = height;

                animation.realloc() catch |err| {
                    try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
                    try log_writer.print("failed to reallocate animation buffers: {s}\n", .{@errorName(err)});
                };

                update = true;
                resolution_changed = true;
            }
        }

        if (update) {
            // If the user entered a wrong password 10 times in a row, play a cascade animation, else update normally
            if (auth_fails >= config.auth_fails) {
                std.Thread.sleep(std.time.ns_per_ms * 10);
                update = buffer.cascade();

                if (!update) {
                    std.Thread.sleep(std.time.ns_per_s * 7);
                    auth_fails = 0;
                }

                _ = termbox.tb_present();
                continue;
            }

            _ = termbox.tb_clear();

            var length: usize = 0;

            if (!animation_timed_out) animation.draw();

            if (!config.hide_version_string) {
                buffer.drawLabel(ly_top_str, length, 0);
                length += ly_top_str.len + 1;
            }

            if (config.bigclock != .none and buffer.box_height + (bigclock.HEIGHT + 2) * 2 < buffer.height) {
                var format_buf: [16:0]u8 = undefined;
                var clock_buf: [32:0]u8 = undefined;
                // We need the slice/c-string returned by `bufPrintZ`.
                const format: [:0]const u8 = try std.fmt.bufPrintZ(&format_buf, "{s}{s}{s}{s}", .{
                    if (config.bigclock_12hr) "%I" else "%H",
                    ":%M",
                    if (config.bigclock_seconds) ":%S" else "",
                    if (config.bigclock_12hr) "%P" else "",
                });
                const xo = buffer.width / 2 - @min(buffer.width, (format.len * (bigclock.WIDTH + 1))) / 2;
                const yo = (buffer.height - buffer.box_height) / 2 - bigclock.HEIGHT - 2;

                const clock_str = interop.timeAsString(&clock_buf, format);

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
                login.label.position(coordinates.x, coordinates.y + 4, coordinates.visible_length, config.text_in_center);
                password.position(coordinates.x, coordinates.y + 6, coordinates.visible_length);

                resolution_changed = false;
            }

            switch (active_input) {
                .info_line => info_line.label.handle(null, insert_mode),
                .session => session.label.handle(null, insert_mode),
                .login => login.label.handle(null, insert_mode),
                .password => password.handle(null, insert_mode) catch |err| {
                    try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
                    try log_writer.print("failed to handle password input: {s}\n", .{@errorName(err)});
                },
            }

            if (config.clock) |clock| draw_clock: {
                if (!can_draw_clock) break :draw_clock;

                var clock_buf: [64:0]u8 = undefined;
                const clock_str = interop.timeAsString(&clock_buf, clock);

                if (clock_str.len == 0) {
                    try info_line.addMessage(lang.err_clock_too_long, config.error_bg, config.error_fg);
                    can_draw_clock = false;
                    try log_writer.writeAll("clock string too long\n");
                    break :draw_clock;
                }

                buffer.drawLabel(clock_str, buffer.width - @min(buffer.width, clock_str.len), 0);
            }

            const label_x = buffer.box_x + buffer.margin_box_h;
            const label_y = buffer.box_y + buffer.margin_box_v;

            buffer.drawLabel(lang.login, label_x, label_y + 4);
            buffer.drawLabel(lang.password, label_x, label_y + 6);

            info_line.label.draw();

            if (!config.hide_key_hints) {
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

                if (config.brightness_down_key) |key| {
                    buffer.drawLabel(key, length, 0);
                    length += key.len + 1;
                    buffer.drawLabel(" ", length - 1, 0);

                    buffer.drawLabel(lang.brightness_down, length, 0);
                    length += brightness_down_len + 1;
                }

                if (config.brightness_up_key) |key| {
                    buffer.drawLabel(key, length, 0);
                    length += key.len + 1;
                    buffer.drawLabel(" ", length - 1, 0);

                    buffer.drawLabel(lang.brightness_up, length, 0);
                    length += brightness_up_len + 1;
                }
            }

            if (config.box_title) |title| {
                buffer.drawConfinedLabel(title, buffer.box_x, buffer.box_y - 1, buffer.box_width);
            }

            if (config.vi_mode) {
                const label_txt = if (insert_mode) lang.insert else lang.normal;
                buffer.drawLabel(label_txt, buffer.box_x, buffer.box_y + buffer.box_height);
            }

            if (can_get_lock_state) draw_lock_state: {
                const lock_state = interop.getLockState() catch |err| {
                    try info_line.addMessage(lang.err_lock_state, config.error_bg, config.error_fg);
                    can_get_lock_state = false;
                    try log_writer.print("failed to get lock state: {s}\n", .{@errorName(err)});
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
            login.label.draw();
            password.draw();

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
                animation.deinit();
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
                                try log_writer.print("failed to execute sleep command: exit code {d}\n", .{process_result.Exited});
                            }
                        }
                    }
                } else if (brightness_down_key != null and pressed_key == brightness_down_key.?) {
                    adjustBrightness(allocator, config.brightness_down_cmd) catch |err| {
                        try info_line.addMessage(lang.err_brightness_change, config.error_bg, config.error_fg);
                        try log_writer.print("failed to change brightness: {s}\n", .{@errorName(err)});
                    };
                } else if (brightness_up_key != null and pressed_key == brightness_up_key.?) {
                    adjustBrightness(allocator, config.brightness_up_cmd) catch |err| {
                        try info_line.addMessage(lang.err_brightness_change, config.error_bg, config.error_fg);
                        try log_writer.print("failed to change brightness: {s}\n", .{@errorName(err)});
                    };
                }
            },
            termbox.TB_KEY_CTRL_C => run = false,
            termbox.TB_KEY_CTRL_U => if (active_input == .password) {
                password.clear();
                update = true;
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
            termbox.TB_KEY_ENTER => authenticate: {
                try log_writer.writeAll("authenticating...");

                if (!config.allow_empty_password and password.text.items.len == 0) {
                    // Let's not log this message for security reasons
                    try info_line.addMessage(lang.err_empty_password, config.error_bg, config.error_fg);
                    InfoLine.clearRendered(allocator, buffer) catch |err| {
                        try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
                        try log_writer.print("failed to clear info line: {s}\n", .{@errorName(err)});
                    };
                    info_line.label.draw();
                    _ = termbox.tb_present();
                    break :authenticate;
                }

                try info_line.addMessage(lang.authenticating, config.bg, config.fg);
                InfoLine.clearRendered(allocator, buffer) catch |err| {
                    try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
                    try log_writer.print("failed to clear info line: {s}\n", .{@errorName(err)});
                };
                info_line.label.draw();
                _ = termbox.tb_present();

                if (config.save) save_last_settings: {
                    var file = std.fs.cwd().createFile(save_path, .{}) catch break :save_last_settings;
                    defer file.close();

                    const save_data = Save{
                        .user = login.getCurrentUser(),
                        .session_index = session.label.current,
                    };
                    ini.writeFromStruct(save_data, file.writer(), null, .{}) catch break :save_last_settings;

                    // Delete previous save file if it exists
                    if (migrator.maybe_save_file) |path| std.fs.cwd().deleteFile(path) catch {};
                }

                var shared_err = try SharedError.init();
                defer shared_err.deinit();

                {
                    const login_text = try allocator.dupeZ(u8, login.getCurrentUser());
                    defer allocator.free(login_text);
                    const password_text = try allocator.dupeZ(u8, password.text.items);
                    defer allocator.free(password_text);

                    session_pid = try std.posix.fork();
                    if (session_pid == 0) {
                        const current_environment = session.label.list.items[session.label.current];
                        const auth_options = auth.AuthOptions{
                            .tty = config.tty,
                            .service_name = config.service_name,
                            .path = config.path,
                            .session_log = config.session_log,
                            .xauth_cmd = config.xauth_cmd,
                            .setup_cmd = config.setup_cmd,
                            .login_cmd = config.login_cmd,
                            .x_cmd = config.x_cmd,
                            .session_pid = session_pid,
                        };

                        // Signal action to give up control on the TTY
                        const tty_control_transfer_act = std.posix.Sigaction{
                            .handler = .{ .handler = &ttyControlTransferSignalHandler },
                            .mask = std.posix.empty_sigset,
                            .flags = 0,
                        };
                        std.posix.sigaction(std.posix.SIG.CHLD, &tty_control_transfer_act, null);

                        auth.authenticate(auth_options, current_environment, login_text, password_text) catch |err| {
                            shared_err.writeError(err);
                            std.process.exit(1);
                        };
                        std.process.exit(0);
                    }

                    _ = std.posix.waitpid(session_pid, 0);
                    // HACK: It seems like the session process is not exiting immediately after the waitpid call.
                    // This is a workaround to ensure the session process has exited before re-initializing the TTY.
                    std.Thread.sleep(std.time.ns_per_s * 1);
                    session_pid = -1;
                }

                // Take back control of the TTY
                _ = termbox.tb_init();

                if (config.full_color) {
                    _ = termbox.tb_set_output_mode(termbox.TB_OUTPUT_TRUECOLOR);
                }

                const auth_err = shared_err.readError();
                if (auth_err) |err| {
                    auth_fails += 1;
                    active_input = .password;

                    try info_line.addMessage(getAuthErrorMsg(err, lang), config.error_bg, config.error_fg);
                    try log_writer.print("failed to authenticate: {s}\n", .{@errorName(err)});

                    if (config.clear_password or err != error.PamAuthError) password.clear();
                } else {
                    if (config.logout_cmd) |logout_cmd| {
                        var logout_process = std.process.Child.init(&[_][]const u8{ "/bin/sh", "-c", logout_cmd }, allocator);
                        _ = logout_process.spawnAndWait() catch .{};
                    }

                    password.clear();
                    try info_line.addMessage(lang.logout, config.bg, config.fg);
                    try log_writer.writeAll("logged out");
                }

                try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, tb_termios);

                if (auth_fails < config.auth_fails) {
                    _ = termbox.tb_clear();
                    try ttyClearScreen();

                    update = true;
                }

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
                    .login => login.label.handle(&event, insert_mode),
                    .password => password.handle(&event, insert_mode) catch {
                        try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
                    },
                }
                update = true;
            },
        }
    }
}

fn ttyClearScreen() !void {
    // Clear the TTY because termbox2 doesn't seem to do it properly
    const capability = termbox.global.caps[termbox.TB_CAP_CLEAR_SCREEN];
    const capability_slice = capability[0..std.mem.len(capability)];
    _ = try std.posix.write(termbox.global.ttyfd, capability_slice);
}

fn addOtherEnvironment(session: *Session, lang: Lang, display_server: DisplayServer, exec: ?[]const u8) !void {
    const name = switch (display_server) {
        .shell => lang.shell,
        .xinitrc => lang.xinitrc,
        else => unreachable,
    };

    try session.addEnvironment(.{
        .entry_ini = null,
        .name = name,
        .xdg_session_desktop = null,
        .xdg_desktop_names = null,
        .cmd = exec orelse "",
        .specifier = lang.other,
        .display_server = display_server,
    });
}

fn crawl(session: *Session, lang: Lang, path: []const u8, display_server: DisplayServer) !void {
    var iterable_directory = std.fs.openDirAbsolute(path, .{ .iterate = true }) catch return;
    defer iterable_directory.close();

    var iterator = iterable_directory.iterate();
    while (try iterator.next()) |item| {
        if (!std.mem.eql(u8, std.fs.path.extension(item.name), ".desktop")) continue;

        const entry_path = try std.fmt.allocPrint(session.label.allocator, "{s}/{s}", .{ path, item.name });
        defer session.label.allocator.free(entry_path);
        var entry_ini = Ini(Entry).init(session.label.allocator);
        _ = try entry_ini.readFileToStruct(entry_path, .{
            .fieldHandler = null,
            .comment_characters = "#",
        });
        errdefer entry_ini.deinit();

        var maybe_xdg_session_desktop: ?[]const u8 = null;
        const maybe_desktop_names = entry_ini.data.@"Desktop Entry".DesktopNames;
        if (maybe_desktop_names) |desktop_names| {
            maybe_xdg_session_desktop = std.mem.sliceTo(desktop_names, ';');
        } else if (display_server != .custom) {
            // If DesktopNames is empty, and this isn't a custom session entry,
            // we'll take the name of the session file
            maybe_xdg_session_desktop = std.fs.path.stem(item.name);
        }

        // Prepare the XDG_CURRENT_DESKTOP environment variable here
        const entry = entry_ini.data.@"Desktop Entry";
        var maybe_xdg_desktop_names: ?[:0]const u8 = null;
        if (entry.DesktopNames) |desktop_names| {
            for (desktop_names) |*c| {
                if (c.* == ';') c.* = ':';
            }
            maybe_xdg_desktop_names = desktop_names;
        }

        const maybe_session_desktop = if (maybe_xdg_session_desktop) |xdg_session_desktop| try session.label.allocator.dupeZ(u8, xdg_session_desktop) else null;
        errdefer if (maybe_session_desktop) |session_desktop| session.label.allocator.free(session_desktop);

        try session.addEnvironment(.{
            .entry_ini = entry_ini,
            .name = entry.Name,
            .xdg_session_desktop = maybe_session_desktop,
            .xdg_desktop_names = maybe_xdg_desktop_names,
            .cmd = entry.Exec,
            .specifier = switch (display_server) {
                .wayland => lang.wayland,
                .x11 => lang.x11,
                .custom => lang.custom,
                else => lang.other,
            },
            .display_server = display_server,
            .is_terminal = entry.Terminal orelse false,
        });
    }
}

fn getAllUsernames(allocator: std.mem.Allocator, login_defs_path: []const u8) !StringList {
    const uid_range = try getUserIdRange(allocator, login_defs_path);

    var usernames: StringList = .empty;
    var maybe_entry = interop.pwd.getpwent();

    while (maybe_entry != null) {
        const entry = maybe_entry.*;

        // We check if the UID is equal to 0 because we always want to add root
        // as a username (even if you can't log into it)
        if (entry.pw_uid >= uid_range.uid_min and entry.pw_uid <= uid_range.uid_max or entry.pw_uid == 0) {
            const pw_name_slice = entry.pw_name[0..std.mem.len(entry.pw_name)];
            const username = try allocator.dupe(u8, pw_name_slice);

            try usernames.append(allocator, username);
        }

        maybe_entry = interop.pwd.getpwent();
    }

    interop.pwd.endpwent();
    return usernames;
}

// This is very bad parsing, but we only need to get 2 values... and the format
// of the file doesn't seem to be standard? So this should be fine...
fn getUserIdRange(allocator: std.mem.Allocator, login_defs_path: []const u8) !UidRange {
    const login_defs_file = try std.fs.cwd().openFile(login_defs_path, .{});
    defer login_defs_file.close();

    const login_defs_buffer = try login_defs_file.readToEndAlloc(allocator, std.math.maxInt(u16));
    defer allocator.free(login_defs_buffer);

    var iterator = std.mem.splitScalar(u8, login_defs_buffer, '\n');
    var uid_range = UidRange{};

    while (iterator.next()) |line| {
        const trimmed_line = std.mem.trim(u8, line, " \n\r\t");

        if (std.mem.startsWith(u8, trimmed_line, "UID_MIN")) {
            uid_range.uid_min = try parseValue(std.c.uid_t, "UID_MIN", trimmed_line);
        } else if (std.mem.startsWith(u8, trimmed_line, "UID_MAX")) {
            uid_range.uid_max = try parseValue(std.c.uid_t, "UID_MAX", trimmed_line);
        }
    }

    return uid_range;
}

fn parseValue(comptime T: type, name: []const u8, buffer: []const u8) !T {
    var iterator = std.mem.splitAny(u8, buffer, " \t");
    var maybe_value: ?T = null;

    while (iterator.next()) |slice| {
        // Skip the slice if it's empty (whitespace) or is the name of the
        // property (e.g. UID_MIN or UID_MAX)
        if (slice.len == 0 or std.mem.eql(u8, slice, name)) continue;
        maybe_value = std.fmt.parseInt(T, slice, 10) catch continue;
    }

    return maybe_value orelse error.ValueNotFound;
}

fn adjustBrightness(allocator: std.mem.Allocator, cmd: []const u8) !void {
    var brightness = std.process.Child.init(&[_][]const u8{ "/bin/sh", "-c", cmd }, allocator);
    brightness.stdout_behavior = .Ignore;
    brightness.stderr_behavior = .Ignore;

    handle_brightness_cmd: {
        const process_result = brightness.spawnAndWait() catch {
            break :handle_brightness_cmd;
        };
        if (process_result.Exited != 0) {
            return error.BrightnessChangeFailed;
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
        error.TtyControlTransferFailed => lang.err_tty_ctrl,
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
        else => @errorName(err),
    };
}
