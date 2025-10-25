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
const OldSave = @import("config/OldSave.zig");
const SavedUsers = @import("config/SavedUsers.zig");
const migrator = @import("config/migrator.zig");
const SharedError = @import("SharedError.zig");
const LogFile = @import("LogFile.zig");

const StringList = std.ArrayListUnmanaged([]const u8);
const Ini = ini.Ini;
const DisplayServer = enums.DisplayServer;
const Entry = Environment.Entry;
const termbox = interop.termbox;
const temporary_allocator = std.heap.page_allocator;
const ly_version_str = "Ly version " ++ build_options.version;

var session_pid: std.posix.pid_t = -1;
fn signalHandler(i: c_int) callconv(.c) void {
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

fn ttyControlTransferSignalHandler(_: c_int) callconv(.c) void {
    _ = termbox.tb_shutdown();
}

const ConfigError = struct {
    type_name: []const u8,
    key: []const u8,
    value: []const u8,
    error_name: []const u8,
};
var config_errors: std.ArrayList(ConfigError) = .empty;

pub fn main() !void {
    var shutdown = false;
    var restart = false;
    var shutdown_cmd: []const u8 = undefined;
    var restart_cmd: []const u8 = undefined;
    var commands_allocated = false;

    var stderr_buffer: [128]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    var stderr = &stderr_writer.interface;

    defer {
        // If we can't shutdown or restart due to an error, we print it to standard error. If that fails, just bail out
        if (shutdown) {
            const shutdown_error = std.process.execv(temporary_allocator, &[_][]const u8{ "/bin/sh", "-c", shutdown_cmd });
            stderr.print("error: couldn't shutdown: {s}\n", .{@errorName(shutdown_error)}) catch std.process.exit(1);
            stderr.flush() catch std.process.exit(1);
        } else if (restart) {
            const restart_error = std.process.execv(temporary_allocator, &[_][]const u8{ "/bin/sh", "-c", restart_cmd });
            stderr.print("error: couldn't restart: {s}\n", .{@errorName(restart_error)}) catch std.process.exit(1);
            stderr.flush() catch std.process.exit(1);
        } else {
            // The user has quit Ly using Ctrl+C
            if (commands_allocated) {
                // Necessary if we error out before allocating
                temporary_allocator.free(shutdown_cmd);
                temporary_allocator.free(restart_cmd);
            }
        }
    }

    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();

    // Allows stopping an animation after some time
    const time_start = try interop.getTimeOfDay();
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
        try stderr.flush();
        return err;
    };
    defer res.deinit();

    var config: Config = undefined;
    var lang: Lang = undefined;
    var old_save_file_exists = false;
    var maybe_config_load_error: ?anyerror = null;
    var can_get_lock_state = true;
    var can_draw_clock = true;
    var can_draw_battery = true;

    var saved_users = SavedUsers.init();
    defer saved_users.deinit(allocator);

    if (res.args.help != 0) {
        try clap.help(stderr, clap.Help, &params, .{});

        _ = try stderr.write("Note: if you want to configure Ly, please check the config file, which is located at " ++ build_options.config_directory ++ "/ly/config.ini.\n");
        try stderr.flush();
        std.process.exit(0);
    }
    if (res.args.version != 0) {
        _ = try stderr.write("Ly version " ++ build_options.version ++ "\n");
        try stderr.flush();
        std.process.exit(0);
    }

    // Load configuration file
    var config_ini = Ini(Config).init(allocator);
    defer config_ini.deinit();

    var lang_ini = Ini(Lang).init(allocator);
    defer lang_ini.deinit();

    var old_save_ini = ini.Ini(OldSave).init(allocator);
    defer old_save_ini.deinit();

    var save_path: []const u8 = build_options.config_directory ++ "/ly/save.txt";
    var old_save_path: []const u8 = build_options.config_directory ++ "/ly/save.ini";
    var save_path_alloc = false;
    defer {
        if (save_path_alloc) allocator.free(save_path);
        if (save_path_alloc) allocator.free(old_save_path);
    }

    const comment_characters = "#";

    if (res.args.config) |s| {
        const trailing_slash = if (s[s.len - 1] != '/') "/" else "";

        const config_path = try std.fmt.allocPrint(allocator, "{s}{s}config.ini", .{ s, trailing_slash });
        defer allocator.free(config_path);

        config = config_ini.readFileToStruct(config_path, .{
            .fieldHandler = migrator.configFieldHandler,
            .errorHandler = configErrorHandler,
            .comment_characters = comment_characters,
        }) catch |err| load_error: {
            maybe_config_load_error = err;
            break :load_error Config{};
        };

        const lang_path = try std.fmt.allocPrint(allocator, "{s}{s}lang/{s}.ini", .{ s, trailing_slash, config.lang });
        defer allocator.free(lang_path);

        lang = lang_ini.readFileToStruct(lang_path, .{
            .fieldHandler = null,
            .comment_characters = comment_characters,
        }) catch Lang{};

        if (config.save) {
            save_path = try std.fmt.allocPrint(allocator, "{s}{s}save.txt", .{ s, trailing_slash });
            old_save_path = try std.fmt.allocPrint(allocator, "{s}{s}save.ini", .{ s, trailing_slash });
            save_path_alloc = true;
        }
    } else {
        const config_path = build_options.config_directory ++ "/ly/config.ini";

        config = config_ini.readFileToStruct(config_path, .{
            .fieldHandler = migrator.configFieldHandler,
            .errorHandler = configErrorHandler,
            .comment_characters = comment_characters,
        }) catch |err| load_error: {
            maybe_config_load_error = err;
            break :load_error Config{};
        };

        const lang_path = try std.fmt.allocPrint(allocator, "{s}/ly/lang/{s}.ini", .{ build_options.config_directory, config.lang });
        defer allocator.free(lang_path);

        lang = lang_ini.readFileToStruct(lang_path, .{
            .fieldHandler = null,
            .comment_characters = comment_characters,
        }) catch Lang{};
    }

    if (maybe_config_load_error == null) {
        migrator.lateConfigFieldHandler(&config);
    }

    var usernames = try getAllUsernames(allocator, config.login_defs_path);
    defer {
        for (usernames.items) |username| allocator.free(username);
        usernames.deinit(allocator);
    }

    if (config.save) read_save_file: {
        old_save_file_exists = migrator.tryMigrateIniSaveFile(allocator, &old_save_ini, old_save_path, &saved_users, usernames.items) catch break :read_save_file;

        // Don't read the new save file if the old one still exists
        if (old_save_file_exists) break :read_save_file;

        var save_file = std.fs.cwd().openFile(save_path, .{}) catch break :read_save_file;
        defer save_file.close();

        var file_buffer: [256]u8 = undefined;
        var file_reader = save_file.reader(&file_buffer);
        var reader = &file_reader.interface;

        const last_username_index_str = reader.takeDelimiterInclusive('\n') catch break :read_save_file;
        saved_users.last_username_index = std.fmt.parseInt(usize, last_username_index_str[0..(last_username_index_str.len - 1)], 10) catch break :read_save_file;

        while (reader.seek < reader.buffer.len) {
            const line = reader.takeDelimiterInclusive('\n') catch break;

            var user = std.mem.splitScalar(u8, line[0..(line.len - 1)], ':');
            const username = user.next() orelse continue;
            const session_index_str = user.next() orelse continue;

            const session_index = std.fmt.parseInt(usize, session_index_str, 10) catch continue;

            try saved_users.user_list.append(allocator, .{
                .username = username,
                .session_index = session_index,
            });
        }

        // If no save file previously existed, fill it up with all usernames
        if (saved_users.user_list.items.len > 0) break :read_save_file;

        for (usernames.items) |user| {
            try saved_users.user_list.append(allocator, .{
                .username = user,
                .session_index = 0,
            });
        }
    }

    var log_file_buffer: [1024]u8 = undefined;

    var log_file = try LogFile.init(config.ly_log, &log_file_buffer);
    defer log_file.deinit();

    var log_writer = &log_file.file_writer.interface;

    // These strings only end up getting freed if the user quits Ly using Ctrl+C, which is fine since in the other cases
    // we end up shutting down or restarting the system
    shutdown_cmd = try temporary_allocator.dupe(u8, config.shutdown_cmd);
    restart_cmd = try temporary_allocator.dupe(u8, config.restart_cmd);
    commands_allocated = true;

    // Initialize termbox
    try log_writer.writeAll("initializing termbox2\n");
    _ = termbox.tb_init();
    defer {
        log_writer.writeAll("shutting down termbox2\n") catch {};
        _ = termbox.tb_shutdown();
    }

    const act = std.posix.Sigaction{
        .handler = .{ .handler = &signalHandler },
        .mask = std.posix.sigemptyset(),
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

    if (maybe_config_load_error) |err| {
        // We can't localize this since the config failed to load so we'd fallback to the default language anyway
        try info_line.addMessage("unable to parse config file", config.error_bg, config.error_fg);
        try log_writer.print("unable to parse config file: {s}\n", .{@errorName(err)});

        defer config_errors.deinit(temporary_allocator);

        for (0..config_errors.items.len) |i| {
            const config_error = config_errors.items[i];
            defer {
                temporary_allocator.free(config_error.type_name);
                temporary_allocator.free(config_error.key);
                temporary_allocator.free(config_error.value);
            }

            try log_writer.print("failed to convert value '{s}' of option '{s}' to type '{s}': {s}\n", .{ config_error.value, config_error.key, config_error.type_name, config_error.error_name });

            // Flush immediately so we can free the allocated memory afterwards
            try log_writer.flush();
        }
    }

    if (!log_file.could_open_log_file) {
        try info_line.addMessage(lang.err_log, config.error_bg, config.error_fg);
        try log_writer.writeAll("failed to open log file\n");
    }

    interop.setNumlock(config.numlock) catch |err| {
        try info_line.addMessage(lang.err_numlock, config.error_bg, config.error_fg);
        try log_writer.print("failed to set numlock: {s}\n", .{@errorName(err)});
    };

    var login: UserList = undefined;

    var session = Session.init(allocator, &buffer, &login);
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

    if (usernames.items.len == 0) {
        // If we have no usernames, simply add an error to the info line.
        // This effectively means you can't login, since there would be no local
        // accounts *and* no root account...but at this point, if that's the
        // case, you have bigger problems to deal with in the first place. :D
        try info_line.addMessage(lang.err_no_users, config.error_bg, config.error_fg);
        try log_writer.writeAll("no users found\n");
    }

    login = try UserList.init(allocator, &buffer, usernames, &saved_users, &session);
    defer login.deinit();

    var password = Text.init(allocator, &buffer, true, config.asterisk);
    defer password.deinit();

    var active_input = config.default_input;
    var insert_mode = !config.vi_mode or config.vi_default_mode == .insert;

    // Load last saved username and desktop selection, if any
    if (config.save) {
        if (saved_users.last_username_index) |index| load_last_user: {
            // If the saved index isn't valid, bail out
            if (index >= saved_users.user_list.items.len) break :load_last_user;

            const user = saved_users.user_list.items[index];

            // Find user with saved name, and switch over to it
            // If it doesn't exist (anymore), we don't change the value
            for (usernames.items, 0..) |username, i| {
                if (std.mem.eql(u8, username, user.username)) {
                    login.label.current = i;
                    break;
                }
            }

            active_input = .password;

            if (user.session_index < session.label.list.items.len) session.label.current = user.session_index;
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
    const active_tty = interop.getActiveTty(allocator) catch |err| no_tty_found: {
        try info_line.addMessage(lang.err_get_active_tty, config.error_bg, config.error_fg);
        try log_writer.print("failed to get active tty: {s}\n", .{@errorName(err)});
        break :no_tty_found build_options.fallback_tty;
    };
    interop.switchTty(active_tty) catch |err| {
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

            var length: usize = config.edge_margin;

            if (!animation_timed_out) animation.draw();

            if (!config.hide_version_string) {
                buffer.drawLabel(ly_version_str, config.edge_margin, buffer.height - 1 - config.edge_margin);
            }

            if (config.battery_id) |id| draw_battery: {
                if (!can_draw_battery) break :draw_battery;

                const battery_percentage = getBatteryPercentage(id) catch |err| {
                    try log_writer.print("failed to get battery percentage: {s}\n", .{@errorName(err)});
                    try info_line.addMessage(lang.err_battery, config.error_bg, config.error_fg);
                    can_draw_battery = false;
                    break :draw_battery;
                };

                var battery_buf: [16:0]u8 = undefined;
                const battery_str = std.fmt.bufPrintZ(&battery_buf, "BAT: {d}%", .{battery_percentage}) catch break :draw_battery;

                var battery_y: usize = config.edge_margin;
                if (!config.hide_key_hints) {
                    battery_y += 1;
                }
                buffer.drawLabel(battery_str, config.edge_margin, battery_y);
                can_draw_battery = true;
            }

            if (config.bigclock != .none and buffer.box_height + (bigclock.HEIGHT + 2) * 2 < buffer.height) {
                var format_buf: [16:0]u8 = undefined;
                var clock_buf: [32:0]u8 = undefined;
                // We need the slice/c-string returned by `bufPrintZ`.
                const format = try std.fmt.bufPrintZ(&format_buf, "{s}{s}{s}{s}", .{
                    if (config.bigclock_12hr) "%I" else "%H",
                    ":%M",
                    if (config.bigclock_seconds) ":%S" else "",
                    if (config.bigclock_12hr) "%P" else "",
                });
                const xo = buffer.width / 2 - @min(buffer.width, (format.len * (bigclock.WIDTH + 1))) / 2;
                const yo = (buffer.height - buffer.box_height) / 2 - bigclock.HEIGHT - 2;

                const clock_str = interop.timeAsString(&clock_buf, format);

                for (clock_str, 0..) |c, i| {
                    // TODO: Show error
                    const clock_cell = try bigclock.clockCell(animate, c, buffer.fg, buffer.bg, config.bigclock);
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

                buffer.drawLabel(clock_str, buffer.width - @min(buffer.width, clock_str.len) - config.edge_margin, config.edge_margin);
            }

            const label_x = buffer.box_x + buffer.margin_box_h;
            const label_y = buffer.box_y + buffer.margin_box_v;

            buffer.drawLabel(lang.login, label_x, label_y + 4);
            buffer.drawLabel(lang.password, label_x, label_y + 6);

            info_line.label.draw();

            if (!config.hide_key_hints) {
                buffer.drawLabel(config.shutdown_key, length, config.edge_margin);
                length += config.shutdown_key.len + 1;
                buffer.drawLabel(" ", length - 1, config.edge_margin);

                buffer.drawLabel(lang.shutdown, length, config.edge_margin);
                length += shutdown_len + 1;

                buffer.drawLabel(config.restart_key, length, config.edge_margin);
                length += config.restart_key.len + 1;
                buffer.drawLabel(" ", length - 1, config.edge_margin);

                buffer.drawLabel(lang.restart, length, config.edge_margin);
                length += restart_len + 1;

                if (config.sleep_cmd != null) {
                    buffer.drawLabel(config.sleep_key, length, config.edge_margin);
                    length += config.sleep_key.len + 1;
                    buffer.drawLabel(" ", length - 1, config.edge_margin);

                    buffer.drawLabel(lang.sleep, length, config.edge_margin);
                    length += sleep_len + 1;
                }

                if (config.brightness_down_key) |key| {
                    buffer.drawLabel(key, length, config.edge_margin);
                    length += key.len + 1;
                    buffer.drawLabel(" ", length - 1, config.edge_margin);

                    buffer.drawLabel(lang.brightness_down, length, config.edge_margin);
                    length += brightness_down_len + 1;
                }

                if (config.brightness_up_key) |key| {
                    buffer.drawLabel(key, length, config.edge_margin);
                    length += key.len + 1;
                    buffer.drawLabel(" ", length - 1, config.edge_margin);

                    buffer.drawLabel(lang.brightness_up, length, config.edge_margin);
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

                var lock_state_x = buffer.width - @min(buffer.width, lang.numlock.len) - config.edge_margin;
                var lock_state_y: usize = config.edge_margin;

                if (config.clock != null) lock_state_y += 1;

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

            // Check how long we've been running so we can turn off the animation
            const time = try interop.getTimeOfDay();

            if (config.animation_timeout_sec > 0 and time.seconds - time_start.seconds > config.animation_timeout_sec) {
                animation_timed_out = true;
                animation.deinit();
            }
        } else if (config.bigclock != .none and config.clock == null) {
            const time = try interop.getTimeOfDay();

            timeout = @intCast((60 - @rem(time.seconds, 60)) * 1000 - @divTrunc(time.microseconds, 1000) + 1);
        } else if (config.clock != null or auth_fails >= config.auth_fails) {
            const time = try interop.getTimeOfDay();

            timeout = @intCast(1000 - @divTrunc(time.microseconds, 1000) + 1);
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
                try log_writer.writeAll("authenticating...\n");

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
                    // It isn't worth cluttering the code with precise error
                    // handling, so let's just report a generic error message,
                    // that should be good enough for debugging anyway.
                    errdefer log_writer.writeAll("failed to save current user data\n") catch {};

                    var file = std.fs.cwd().createFile(save_path, .{}) catch |err| {
                        log_writer.print("failed to create save file: {s}\n", .{@errorName(err)}) catch break :save_last_settings;
                        break :save_last_settings;
                    };
                    defer file.close();

                    var file_buffer: [256]u8 = undefined;
                    var file_writer = file.writer(&file_buffer);
                    var writer = &file_writer.interface;

                    try writer.print("{d}\n", .{login.label.current});
                    for (saved_users.user_list.items) |user| {
                        try writer.print("{s}:{d}\n", .{ user.username, user.session_index });
                    }
                    try writer.flush();

                    // Delete previous save file if it exists
                    if (migrator.maybe_save_file) |path| {
                        std.fs.cwd().deleteFile(path) catch {};
                    } else if (old_save_file_exists) {
                        std.fs.cwd().deleteFile(old_save_path) catch {};
                    }
                }

                var shared_err = try SharedError.init();
                defer shared_err.deinit();

                {
                    log_file.deinit();

                    session_pid = try std.posix.fork();
                    if (session_pid == 0) {
                        const current_environment = session.label.list.items[session.label.current].environment;
                        const auth_options = auth.AuthOptions{
                            .tty = active_tty,
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
                            .mask = std.posix.sigemptyset(),
                            .flags = 0,
                        };
                        std.posix.sigaction(std.posix.SIG.CHLD, &tty_control_transfer_act, null);

                        try log_file.reinit();

                        auth.authenticate(allocator, &log_file, auth_options, current_environment, login.getCurrentUsername(), password.text.items) catch |err| {
                            shared_err.writeError(err);

                            log_file.deinit();
                            std.process.exit(1);
                        };

                        log_file.deinit();
                        std.process.exit(0);
                    }

                    _ = std.posix.waitpid(session_pid, 0);
                    // HACK: It seems like the session process is not exiting immediately after the waitpid call.
                    // This is a workaround to ensure the session process has exited before re-initializing the TTY.
                    std.Thread.sleep(std.time.ns_per_s * 1);
                    session_pid = -1;

                    try log_file.reinit();
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
                    try log_writer.writeAll("logged out\n");
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

        try log_writer.flush();
    }
}

fn configErrorHandler(type_name: []const u8, key: []const u8, value: []const u8, err: anyerror) void {
    config_errors.append(temporary_allocator, .{
        .type_name = temporary_allocator.dupe(u8, type_name) catch return,
        .key = temporary_allocator.dupe(u8, key) catch return,
        .value = temporary_allocator.dupe(u8, value) catch return,
        .error_name = @errorName(err),
    }) catch return;
}

fn ttyClearScreen() !void {
    // Clear the TTY because termbox2 doesn't seem to do it properly
    const capability = termbox.global.caps[termbox.TB_CAP_CLEAR_SCREEN];
    const capability_slice = std.mem.span(capability);
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
        .cmd = exec,
        .specifier = lang.other,
        .display_server = display_server,
        .is_terminal = display_server == .shell,
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

        const entry = entry_ini.data.@"Desktop Entry";
        var maybe_xdg_session_desktop: ?[]const u8 = null;
        var maybe_xdg_desktop_names: ?[]const u8 = null;

        // Prepare the XDG_SESSION_DESKTOP and XDG_CURRENT_DESKTOP environment
        // variables here
        if (entry.DesktopNames) |desktop_names| {
            maybe_xdg_session_desktop = std.mem.sliceTo(desktop_names, ';');

            for (desktop_names) |*c| {
                if (c.* == ';') c.* = ':';
            }
            maybe_xdg_desktop_names = desktop_names;
        } else if (display_server != .custom) {
            // If DesktopNames is empty, and this isn't a custom session entry,
            // we'll take the name of the session file
            maybe_xdg_session_desktop = std.fs.path.stem(item.name);
        }

        try session.addEnvironment(.{
            .entry_ini = entry_ini,
            .name = entry.Name,
            .xdg_session_desktop = maybe_xdg_session_desktop,
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
    const uid_range = try interop.getUserIdRange(allocator, login_defs_path);

    var usernames: StringList = .empty;
    var maybe_entry = interop.getNextUsernameEntry();

    while (maybe_entry) |entry| {
        // We check if the UID is equal to 0 because we always want to add root
        // as a username (even if you can't log into it)
        if (entry.uid >= uid_range.uid_min and entry.uid <= uid_range.uid_max or entry.uid == 0 and entry.username != null) {
            const username = try allocator.dupe(u8, entry.username.?);
            try usernames.append(allocator, username);
        }

        maybe_entry = interop.getNextUsernameEntry();
    }

    interop.closePasswordDatabase();
    return usernames;
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

fn getBatteryPercentage(battery_id: []const u8) !u8 {
    const path = try std.fmt.allocPrint(temporary_allocator, "/sys/class/power_supply/{s}/capacity", .{battery_id});
    defer temporary_allocator.free(path);

    const battery_file = try std.fs.cwd().openFile(path, .{});
    defer battery_file.close();

    var buffer: [8]u8 = undefined;
    const bytes_read = try battery_file.read(&buffer);
    const capacity_str = buffer[0..bytes_read];

    const trimmed = std.mem.trimRight(u8, capacity_str, "\n\r");

    return try std.fmt.parseInt(u8, trimmed, 10);
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
