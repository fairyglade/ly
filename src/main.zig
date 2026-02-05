const std = @import("std");
const build_options = @import("build_options");
const builtin = @import("builtin");
const ly_core = @import("ly-core");
const clap = @import("clap");
const ini = @import("zigini");
const auth = @import("auth.zig");
const bigclock = @import("bigclock.zig");
const enums = @import("enums.zig");
const Environment = @import("Environment.zig");
const ColorMix = @import("animations/ColorMix.zig");
const Doom = @import("animations/Doom.zig");
const Matrix = @import("animations/Matrix.zig");
const GameOfLife = @import("animations/GameOfLife.zig");
const DurFile = @import("animations/DurFile.zig");
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

const StringList = std.ArrayListUnmanaged([]const u8);
const Ini = ini.Ini;
const DisplayServer = enums.DisplayServer;
const Entry = Environment.Entry;
const interop = ly_core.interop;
const UidRange = ly_core.UidRange;
const LogFile = ly_core.LogFile;
const SharedError = ly_core.SharedError;
const IniParser = ly_core.IniParser;
const termbox = TerminalBuffer.termbox;
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

    TerminalBuffer.shutdownStatic();
    std.c.exit(i);
}

fn ttyControlTransferSignalHandler(_: c_int) callconv(.c) void {
    TerminalBuffer.shutdownStatic();
}

const UiState = struct {
    auth_fails: u64,
    update: bool,
    buffer: *TerminalBuffer,
    animation_timed_out: bool,
    animation: *?Animation,
    can_draw_battery: bool,
    info_line: *InfoLine,
    animate: bool,
    resolution_changed: bool,
    session: *Session,
    login: *UserList,
    password: *Text,
    active_input: enums.Input,
    insert_mode: bool,
    can_draw_clock: bool,
    shutdown_len: u8,
    restart_len: u8,
    sleep_len: u8,
    hibernate_len: u8,
    brightness_down_len: u8,
    brightness_up_len: u8,
    can_get_lock_state: bool,
};

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

    const allocator = gpa.allocator();

    // Allows stopping an animation after some time
    const animation_time_start = try interop.getTimeOfDay();

    // Load arguments
    const params = comptime clap.parseParamsComptime(
        \\-h, --help                Shows all commands.
        \\-v, --version             Shows the version of Ly.
        \\-c, --config <str>        Overrides the default configuration path. Example: --config /usr/share/ly
        \\--use-kmscon-vt           Use KMSCON instead of kernel VT
    );

    var diag = clap.Diagnostic{};
    var arg_parse_error: anyerror = undefined;
    var maybe_res = clap.parse(clap.Help, &params, clap.parsers.default, .{ .diagnostic = &diag, .allocator = allocator }) catch |err| parse_error: {
        arg_parse_error = err;
        diag.report(stderr, err) catch {};
        try stderr.flush();
        break :parse_error null;
    };
    defer if (maybe_res) |*res| res.deinit();

    var old_save_parser: ?IniParser(OldSave) = null;
    defer if (old_save_parser) |*str| str.deinit();

    var use_kmscon_vt = false;
    var start_cmd_exit_code: u8 = 0;

    var saved_users = SavedUsers.init();
    defer saved_users.deinit(allocator);

    var config_parent_path: []const u8 = build_options.config_directory ++ "/ly";
    if (maybe_res) |*res| {
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
        if (res.args.config) |path| config_parent_path = path;
        if (res.args.@"use-kmscon-vt" != 0) use_kmscon_vt = true;
    }

    // Load configuration file
    var save_path: []const u8 = build_options.config_directory ++ "/ly/save.txt";
    var old_save_path: []const u8 = build_options.config_directory ++ "/ly/save.ini";
    var save_path_alloc = false;
    defer if (save_path_alloc) {
        allocator.free(save_path);
        allocator.free(old_save_path);
    };

    const config_path = try std.fs.path.join(allocator, &[_][]const u8{ config_parent_path, "config.ini" });
    defer allocator.free(config_path);

    var config_parser = try IniParser(Config).init(allocator, config_path, migrator.configFieldHandler);
    defer config_parser.deinit();

    var config = config_parser.structure;

    var lang_buffer: [16]u8 = undefined;
    const lang_file = try std.fmt.bufPrint(&lang_buffer, "{s}.ini", .{config.lang});

    const lang_path = try std.fs.path.join(allocator, &[_][]const u8{ config_parent_path, "lang", lang_file });
    defer allocator.free(lang_path);

    var lang_parser = try IniParser(Lang).init(allocator, lang_path, null);
    defer lang_parser.deinit();

    const lang = lang_parser.structure;

    if (config.save) {
        save_path = try std.fs.path.join(allocator, &[_][]const u8{ config_parent_path, "save.txt" });
        old_save_path = try std.fs.path.join(allocator, &[_][]const u8{ config_parent_path, "save.ini" });
        save_path_alloc = true;
    }

    if (config_parser.maybe_load_error == null) {
        migrator.lateConfigFieldHandler(&config);
    }

    var maybe_uid_range_error: ?anyerror = null;
    var usernames = try getAllUsernames(allocator, config.login_defs_path, &maybe_uid_range_error);
    defer {
        for (usernames.items) |username| allocator.free(username);
        usernames.deinit(allocator);
    }

    if (config.save) read_save_file: {
        old_save_parser = migrator.tryMigrateIniSaveFile(allocator, old_save_path, &saved_users, usernames.items) catch break :read_save_file;

        // Don't read the new save file if the old one still exists
        if (old_save_parser != null) break :read_save_file;

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
                .username = try allocator.dupe(u8, username),
                .session_index = session_index,
                .first_run = false,
                .allocated_username = true,
            });
        }
    }

    // If no save file previously existed, fill it up with all usernames
    // TODO: Add new username with existing save file
    if (config.save and saved_users.user_list.items.len == 0) {
        for (usernames.items) |user| {
            try saved_users.user_list.append(allocator, .{
                .username = user,
                .session_index = 0,
                .first_run = true,
                .allocated_username = false,
            });
        }
    }

    var log_file_buffer: [1024]u8 = undefined;

    var log_file = try LogFile.init(config.ly_log, &log_file_buffer);
    defer log_file.deinit();

    // These strings only end up getting freed if the user quits Ly using Ctrl+C, which is fine since in the other cases
    // we end up shutting down or restarting the system
    shutdown_cmd = try temporary_allocator.dupe(u8, config.shutdown_cmd);
    restart_cmd = try temporary_allocator.dupe(u8, config.restart_cmd);
    commands_allocated = true;

    if (config.start_cmd) |start_cmd| {
        var start = std.process.Child.init(&[_][]const u8{ "/bin/sh", "-c", start_cmd }, allocator);
        start.stdout_behavior = .Ignore;
        start.stderr_behavior = .Ignore;

        handle_start_cmd: {
            const process_result = start.spawnAndWait() catch {
                break :handle_start_cmd;
            };
            start_cmd_exit_code = process_result.Exited;
        }
    }

    // Initialize terminal buffer
    try log_file.info("tui", "initializing terminal buffer", .{});
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
        .full_color = config.full_color,
        .labels_max_length = labels_max_length,
        .is_tty = true,
    };
    var buffer = try TerminalBuffer.init(buffer_options, &log_file, random);
    defer {
        log_file.info("tui", "shutting down terminal buffer", .{}) catch {};
        TerminalBuffer.shutdownStatic();
    }

    const act = std.posix.Sigaction{
        .handler = .{ .handler = &signalHandler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.TERM, &act, null);

    // Initialize components
    var info_line = InfoLine.init(allocator, &buffer);
    defer info_line.deinit();

    if (maybe_res == null) {
        var longest = diag.name.longest();
        if (longest.kind == .positional)
            longest.name = diag.arg;

        try info_line.addMessage(lang.err_args, config.error_bg, config.error_fg);
        try log_file.err("cli", "unable to parse argument '{s}{s}': {s}", .{ longest.kind.prefix(), longest.name, @errorName(arg_parse_error) });
    }

    if (maybe_uid_range_error) |err| {
        try info_line.addMessage(lang.err_uid_range, config.error_bg, config.error_fg);
        try log_file.err("sys", "failed to get uid range: {s}; falling back to default", .{@errorName(err)});
    }

    if (start_cmd_exit_code != 0) {
        try info_line.addMessage(lang.err_start, config.error_bg, config.error_fg);
        try log_file.err("sys", "failed to execute start command: exit code {d}", .{start_cmd_exit_code});
    }

    if (config_parser.maybe_load_error) |load_error| {
        // We can't localize this since the config failed to load so we'd fallback to the default language anyway
        try info_line.addMessage("unable to parse config file", config.error_bg, config.error_fg);
        try log_file.err("conf", "unable to parse config file: {s}", .{@errorName(load_error)});

        for (config_parser.errors.items) |err| {
            try log_file.err("conf", "failed to convert value '{s}' of option '{s}' to type '{s}': {s}", .{ err.value, err.key, err.type_name, err.error_name });
        }
    }

    if (!log_file.could_open_log_file) {
        try info_line.addMessage(lang.err_log, config.error_bg, config.error_fg);
        try log_file.err("sys", "failed to open log file", .{});
    }

    interop.setNumlock(config.numlock) catch |err| {
        try info_line.addMessage(lang.err_numlock, config.error_bg, config.error_fg);
        try log_file.err("sys", "failed to set numlock: {s}", .{@errorName(err)});
    };

    var login: UserList = undefined;

    var session = Session.init(allocator, &buffer, &login);
    defer session.deinit();

    login = try UserList.init(allocator, &buffer, usernames, &saved_users, &session);
    defer login.deinit();

    addOtherEnvironment(&session, lang, .shell, null) catch |err| {
        try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
        try log_file.err("sys", "failed to add shell environment: {s}", .{@errorName(err)});
    };

    if (build_options.enable_x11_support) {
        if (config.xinitrc) |xinitrc_cmd| {
            addOtherEnvironment(&session, lang, .xinitrc, xinitrc_cmd) catch |err| {
                try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
                try log_file.err("sys", "failed to add xinitrc environment: {s}", .{@errorName(err)});
            };
        }
    } else {
        try info_line.addMessage(lang.no_x11_support, config.bg, config.fg);
        try log_file.err("comp", "x11 support disabled at compile-time");
    }

    var has_crawl_error = false;

    // Crawl session directories (Wayland, X11 and custom respectively)
    var wayland_session_dirs = std.mem.splitScalar(u8, config.waylandsessions, ':');
    while (wayland_session_dirs.next()) |dir| {
        crawl(&session, lang, dir, .wayland) catch |err| {
            has_crawl_error = true;
            try log_file.err("sys", "failed to crawl wayland session directory '{s}': {s}", .{ dir, @errorName(err) });
        };
    }

    if (build_options.enable_x11_support) {
        var x_session_dirs = std.mem.splitScalar(u8, config.xsessions, ':');
        while (x_session_dirs.next()) |dir| {
            crawl(&session, lang, dir, .x11) catch |err| {
                has_crawl_error = true;
                try log_file.err("sys", "failed to crawl x11 session directory '{s}': {s}", .{ dir, @errorName(err) });
            };
        }
    }

    var custom_session_dirs = std.mem.splitScalar(u8, config.custom_sessions, ':');
    while (custom_session_dirs.next()) |dir| {
        crawl(&session, lang, dir, .custom) catch |err| {
            has_crawl_error = true;
            try log_file.err("sys", "failed to crawl custom session directory '{s}': {s}", .{ dir, @errorName(err) });
        };
    }

    if (has_crawl_error) {
        try info_line.addMessage(lang.err_crawl, config.error_bg, config.error_fg);
    }

    if (usernames.items.len == 0) {
        // If we have no usernames, simply add an error to the info line.
        // This effectively means you can't login, since there would be no local
        // accounts *and* no root account...but at this point, if that's the
        // case, you have bigger problems to deal with in the first place. :D
        try info_line.addMessage(lang.err_no_users, config.error_bg, config.error_fg);
        try log_file.err("sys", "no users found", .{});
    }

    var password = Text.init(allocator, &buffer, true, config.asterisk);
    defer password.deinit();

    var is_autologin = false;

    check_autologin: {
        const auto_user = config.auto_login_user orelse break :check_autologin;
        const auto_session = config.auto_login_session orelse break :check_autologin;

        if (!isValidUsername(auto_user, usernames)) {
            try info_line.addMessage(lang.err_pam_user_unknown, config.error_bg, config.error_fg);
            try log_file.err("auth", "autologin failed: username '{s}' not found", .{auto_user});
            break :check_autologin;
        }

        const session_index = findSessionByName(&session, auto_session) orelse {
            try log_file.err("auth", "autologin failed: session '{s}' not found", .{auto_session});
            try info_line.addMessage(lang.err_autologin_session, config.error_bg, config.error_fg);
            break :check_autologin;
        };
        try log_file.err("auth", "attempting autologin for user '{s}' with session '{s}'", .{ auto_user, auto_session });

        session.label.current = session_index;
        for (login.label.list.items, 0..) |username, i| {
            if (std.mem.eql(u8, username.name, auto_user)) {
                login.label.current = i;
                break;
            }
        }
        is_autologin = true;
    }

    var animation: ?Animation = null;
    var state = UiState{
        .auth_fails = 0,
        .update = true,
        .buffer = &buffer,
        .animation_timed_out = false,
        .animation = &animation,
        .can_draw_battery = true,
        .info_line = &info_line,
        .animate = config.animation != .none,
        .resolution_changed = false,
        .session = &session,
        .login = &login,
        .password = &password,
        .active_input = config.default_input,
        .insert_mode = !config.vi_mode or config.vi_default_mode == .insert,
        .can_draw_clock = true,
        .shutdown_len = try TerminalBuffer.strWidth(lang.shutdown),
        .restart_len = try TerminalBuffer.strWidth(lang.restart),
        .sleep_len = try TerminalBuffer.strWidth(lang.sleep),
        .hibernate_len = try TerminalBuffer.strWidth(lang.hibernate),
        .brightness_down_len = try TerminalBuffer.strWidth(lang.brightness_down),
        .brightness_up_len = try TerminalBuffer.strWidth(lang.brightness_up),
        .can_get_lock_state = true,
    };

    // Load last saved username and desktop selection, if any
    // Skip if autologin is active to prevent overriding autologin session
    if (config.save and !is_autologin) {
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

            state.active_input = .password;

            session.label.current = @min(user.session_index, session.label.list.items.len - 1);
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

        switch (state.active_input) {
            .info_line => info_line.label.handle(null, state.insert_mode),
            .session => session.label.handle(null, state.insert_mode),
            .login => login.label.handle(null, state.insert_mode),
            .password => password.handle(null, state.insert_mode) catch |err| {
                try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
                try log_file.err("tui", "failed to handle password input: {s}", .{@errorName(err)});
            },
        }
    }

    // Initialize the animation, if any
    switch (config.animation) {
        .none => {},
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
        .dur_file => {
            var dur = try DurFile.init(allocator, &buffer, &log_file, config.dur_file_path, config.dur_offset_alignment, config.dur_x_offset, config.dur_y_offset, config.full_color);
            animation = dur.animation();
        },
    }
    defer if (animation) |*a| a.deinit();

    const shutdown_key = try std.fmt.parseInt(u8, config.shutdown_key[1..], 10);
    const restart_key = try std.fmt.parseInt(u8, config.restart_key[1..], 10);
    const sleep_key = try std.fmt.parseInt(u8, config.sleep_key[1..], 10);
    const hibernate_key = try std.fmt.parseInt(u8, config.hibernate_key[1..], 10);
    const brightness_down_key = if (config.brightness_down_key) |key| try std.fmt.parseInt(u8, key[1..], 10) else null;
    const brightness_up_key = if (config.brightness_up_key) |key| try std.fmt.parseInt(u8, key[1..], 10) else null;

    var event: termbox.tb_event = undefined;
    var run = true;
    var inactivity_time_start = try interop.getTimeOfDay();
    var inactivity_cmd_ran = false;

    // Switch to selected TTY
    const active_tty = interop.getActiveTty(allocator) catch |err| no_tty_found: {
        try info_line.addMessage(lang.err_get_active_tty, config.error_bg, config.error_fg);
        try log_file.err("sys", "failed to get active tty: {s}", .{@errorName(err)});
        break :no_tty_found build_options.fallback_tty;
    };
    interop.switchTty(active_tty) catch |err| {
        try info_line.addMessage(lang.err_switch_tty, config.error_bg, config.error_fg);
        try log_file.err("sys", "failed to switch tty: {s}", .{@errorName(err)});
    };

    if (config.initial_info_text) |text| {
        try info_line.addMessage(text, config.bg, config.fg);
    } else get_host_name: {
        // Initialize information line with host name
        var name_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
        const hostname = std.posix.gethostname(&name_buf) catch |err| {
            try info_line.addMessage(lang.err_hostname, config.error_bg, config.error_fg);
            try log_file.err("sys", "failed to get hostname: {s}", .{@errorName(err)});
            break :get_host_name;
        };
        try info_line.addMessage(hostname, config.bg, config.fg);
    }

    while (run) {
        // If there's no input or there's an animation, a resolution change needs to be checked
        if (!state.update or state.animate or config.bigclock != .none or config.clock != null) {
            if (!state.update) std.Thread.sleep(std.time.ns_per_ms * 100);

            // Required to update tb_width() and tb_height()
            const new_dimensions = TerminalBuffer.presentBufferStatic();
            const width = new_dimensions.width;
            const height = new_dimensions.height;

            if (width != state.buffer.width or height != state.buffer.height) {
                // If it did change, then update the cell buffer, reallocate the current animation's buffers, and force a draw update
                try log_file.info("tui", "screen resolution updated to {d}x{d}", .{ width, height });

                state.buffer.width = width;
                state.buffer.height = height;

                if (state.animation.*) |*a| a.realloc() catch |err| {
                    try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
                    try log_file.err("tui", "failed to reallocate animation buffers: {s}", .{@errorName(err)});
                };

                state.update = true;
                state.resolution_changed = true;
            }
        }

        if (state.update) {
            if (!try drawUi(config, lang, &log_file, &state)) continue;
        }

        var timeout: i32 = -1;

        // Calculate the maximum timeout based on current animations, or the (big) clock. If there's none, we wait for the event indefinitely instead
        if (state.animate and !state.animation_timed_out) {
            timeout = config.min_refresh_delta;

            // Check how long we've been running so we can turn off the animation
            const time = try interop.getTimeOfDay();

            if (config.animation_timeout_sec > 0 and time.seconds - animation_time_start.seconds > config.animation_timeout_sec) {
                state.animation_timed_out = true;
                if (state.animation.*) |*a| a.deinit();
            }
        } else if (config.bigclock != .none and config.clock == null) {
            const time = try interop.getTimeOfDay();

            timeout = @intCast((60 - @rem(time.seconds, 60)) * 1000 - @divTrunc(time.microseconds, 1000) + 1);
        } else if (config.clock != null or (config.auth_fails > 0 and state.auth_fails >= config.auth_fails)) {
            const time = try interop.getTimeOfDay();

            timeout = @intCast(1000 - @divTrunc(time.microseconds, 1000) + 1);
        }

        if (config.inactivity_cmd) |inactivity_cmd| {
            const time = try interop.getTimeOfDay();

            if (!inactivity_cmd_ran and time.seconds - inactivity_time_start.seconds > config.inactivity_delay) {
                var inactivity = std.process.Child.init(&[_][]const u8{ "/bin/sh", "-c", inactivity_cmd }, allocator);
                inactivity.stdout_behavior = .Ignore;
                inactivity.stderr_behavior = .Ignore;

                handle_inactivity_cmd: {
                    const process_result = inactivity.spawnAndWait() catch {
                        break :handle_inactivity_cmd;
                    };
                    if (process_result.Exited != 0) {
                        try info_line.addMessage(lang.err_inactivity, config.error_bg, config.error_fg);
                        try log_file.err("sys", "failed to execute inactivity command: exit code {d}", .{process_result.Exited});
                    }
                }

                inactivity_cmd_ran = true;
            }
        }

        // Skip event polling if autologin is set, use simulated Enter key press instead
        if (is_autologin) {
            event = termbox.tb_event{
                .type = termbox.TB_EVENT_KEY,
                .key = termbox.TB_KEY_ENTER,
                .ch = 0,
                .w = 0,
                .h = 0,
                .x = 0,
                .y = 0,
                .mod = 0,
            };
        } else {
            const event_error = if (timeout == -1) termbox.tb_poll_event(&event) else termbox.tb_peek_event(&event, timeout);

            state.update = timeout != -1;

            if (event_error < 0 or event.type != termbox.TB_EVENT_KEY) continue;
        }

        // Input of some kind was detected, so reset the inactivity timer
        inactivity_time_start = try interop.getTimeOfDay();

        switch (event.key) {
            termbox.TB_KEY_ESC => {
                if (config.vi_mode and state.insert_mode) {
                    state.insert_mode = false;
                    state.update = true;
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
                                try log_file.err("sys", "failed to execute sleep command: exit code {d}", .{process_result.Exited});
                            }
                        }
                    }
                } else if (pressed_key == hibernate_key) {
                    if (config.hibernate_cmd) |hibernate_cmd| {
                        var hibernate = std.process.Child.init(&[_][]const u8{ "/bin/sh", "-c", hibernate_cmd }, allocator);
                        hibernate.stdout_behavior = .Ignore;
                        hibernate.stderr_behavior = .Ignore;

                        handle_hibernate_cmd: {
                            const process_result = hibernate.spawnAndWait() catch {
                                break :handle_hibernate_cmd;
                            };
                            if (process_result.Exited != 0) {
                                try info_line.addMessage(lang.err_hibernate, config.error_bg, config.error_fg);
                                try log_file.err("sys", "failed to execute hibernate command: exit code {d}", .{process_result.Exited});
                            }
                        }
                    }
                } else if (brightness_down_key != null and pressed_key == brightness_down_key.?) {
                    adjustBrightness(allocator, config.brightness_down_cmd) catch |err| {
                        try info_line.addMessage(lang.err_brightness_change, config.error_bg, config.error_fg);
                        try log_file.err("sys", "failed to change brightness: {s}", .{@errorName(err)});
                    };
                } else if (brightness_up_key != null and pressed_key == brightness_up_key.?) {
                    adjustBrightness(allocator, config.brightness_up_cmd) catch |err| {
                        try info_line.addMessage(lang.err_brightness_change, config.error_bg, config.error_fg);
                        try log_file.err("sys", "failed to change brightness: {s}", .{@errorName(err)});
                    };
                }
            },
            termbox.TB_KEY_CTRL_C => run = false,
            termbox.TB_KEY_CTRL_U => if (state.active_input == .password) {
                password.clear();
                state.update = true;
            },
            termbox.TB_KEY_CTRL_K, termbox.TB_KEY_ARROW_UP => {
                state.active_input.move(true, false);
                state.update = true;
            },
            termbox.TB_KEY_CTRL_J, termbox.TB_KEY_ARROW_DOWN => {
                state.active_input.move(false, false);
                state.update = true;
            },
            termbox.TB_KEY_TAB => {
                state.active_input.move(false, true);
                state.update = true;
            },
            termbox.TB_KEY_BACK_TAB => {
                state.active_input.move(true, true);
                state.update = true;
            },
            termbox.TB_KEY_ENTER => authenticate: {
                try log_file.info("auth", "starting authentication", .{});

                if (!config.allow_empty_password and password.text.items.len == 0) {
                    // Let's not log this message for security reasons
                    try info_line.addMessage(lang.err_empty_password, config.error_bg, config.error_fg);
                    InfoLine.clearRendered(allocator, buffer) catch |err| {
                        try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
                        try log_file.err("tui", "failed to clear info line: {s}", .{@errorName(err)});
                    };
                    info_line.label.draw();
                    _ = TerminalBuffer.presentBufferStatic();
                    break :authenticate;
                }

                try info_line.addMessage(lang.authenticating, config.bg, config.fg);
                InfoLine.clearRendered(allocator, buffer) catch |err| {
                    try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
                    try log_file.err("tui", "failed to clear info line: {s}", .{@errorName(err)});
                };
                info_line.label.draw();
                _ = TerminalBuffer.presentBufferStatic();

                if (config.save) save_last_settings: {
                    // It isn't worth cluttering the code with precise error
                    // handling, so let's just report a generic error message,
                    // that should be good enough for debugging anyway.
                    errdefer log_file.err("conf", "failed to save current user data", .{}) catch {};

                    var file = std.fs.cwd().createFile(save_path, .{}) catch |err| {
                        log_file.err("sys", "failed to create save file: {s}", .{@errorName(err)}) catch break :save_last_settings;
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
                    } else if (old_save_parser != null) {
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

                        // Use auto_login_service for autologin, otherwise use configured service
                        const service_name = if (is_autologin) config.auto_login_service else config.service_name;
                        const password_text = if (is_autologin) "" else password.text.items;

                        const auth_options = auth.AuthOptions{
                            .tty = active_tty,
                            .service_name = service_name,
                            .path = config.path,
                            .session_log = config.session_log,
                            .xauth_cmd = config.xauth_cmd,
                            .setup_cmd = config.setup_cmd,
                            .login_cmd = config.login_cmd,
                            .x_cmd = config.x_cmd,
                            .x_vt = config.x_vt,
                            .session_pid = session_pid,
                            .use_kmscon_vt = use_kmscon_vt,
                        };

                        // Signal action to give up control on the TTY
                        const tty_control_transfer_act = std.posix.Sigaction{
                            .handler = .{ .handler = &ttyControlTransferSignalHandler },
                            .mask = std.posix.sigemptyset(),
                            .flags = 0,
                        };
                        std.posix.sigaction(std.posix.SIG.CHLD, &tty_control_transfer_act, null);

                        try log_file.reinit();

                        auth.authenticate(allocator, &log_file, auth_options, current_environment, login.getCurrentUsername(), password_text) catch |err| {
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

                try buffer.reclaim();

                const auth_err = shared_err.readError();
                if (auth_err) |err| {
                    state.auth_fails += 1;
                    state.active_input = .password;

                    try info_line.addMessage(getAuthErrorMsg(err, lang), config.error_bg, config.error_fg);
                    try log_file.err("auth", "failed to authenticate: {s}", .{@errorName(err)});

                    if (config.clear_password or err != error.PamAuthError) password.clear();
                } else {
                    if (config.logout_cmd) |logout_cmd| {
                        var logout_process = std.process.Child.init(&[_][]const u8{ "/bin/sh", "-c", logout_cmd }, allocator);
                        _ = logout_process.spawnAndWait() catch .{};
                    }

                    password.clear();
                    is_autologin = false;
                    try info_line.addMessage(lang.logout, config.bg, config.fg);
                    try log_file.info("auth", "logged out", .{});
                }

                if (config.auth_fails == 0 or state.auth_fails < config.auth_fails) {
                    try TerminalBuffer.clearScreenStatic(true);
                    state.update = true;
                }

                // Restore the cursor
                TerminalBuffer.setCursorStatic(0, 0);
                _ = TerminalBuffer.presentBufferStatic();
            },
            else => {
                if (!state.insert_mode) {
                    switch (event.ch) {
                        'k' => {
                            state.active_input.move(true, false);
                            state.update = true;
                            continue;
                        },
                        'j' => {
                            state.active_input.move(false, false);
                            state.update = true;
                            continue;
                        },
                        'i' => {
                            state.insert_mode = true;
                            state.update = true;
                            continue;
                        },
                        else => {},
                    }
                }

                switch (state.active_input) {
                    .info_line => info_line.label.handle(&event, state.insert_mode),
                    .session => session.label.handle(&event, state.insert_mode),
                    .login => login.label.handle(&event, state.insert_mode),
                    .password => password.handle(&event, state.insert_mode) catch {
                        try info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
                    },
                }

                state.update = true;
            },
        }
    }
}

fn drawUi(config: Config, lang: Lang, log_file: *LogFile, state: *UiState) !bool {
    // If the user entered a wrong password 10 times in a row, play a cascade animation, else update normally
    if (config.auth_fails > 0 and state.auth_fails >= config.auth_fails) {
        std.Thread.sleep(std.time.ns_per_ms * 10);
        state.update = state.buffer.cascade();

        if (!state.update) {
            std.Thread.sleep(std.time.ns_per_s * 7);
            state.auth_fails = 0;
        }

        _ = TerminalBuffer.presentBufferStatic();
        return false;
    }

    try TerminalBuffer.clearScreenStatic(false);

    var length: usize = config.edge_margin;

    if (!state.animation_timed_out) if (state.animation.*) |*a| a.draw();

    if (!config.hide_version_string) {
        state.buffer.drawLabel(ly_version_str, config.edge_margin, state.buffer.height - 1 - config.edge_margin);
    }

    if (config.battery_id) |id| draw_battery: {
        if (!state.can_draw_battery) break :draw_battery;

        const battery_percentage = getBatteryPercentage(id) catch |err| {
            try log_file.err("sys", "failed to get battery percentage: {s}", .{@errorName(err)});
            try state.info_line.addMessage(lang.err_battery, config.error_bg, config.error_fg);
            state.can_draw_battery = false;
            break :draw_battery;
        };

        var battery_buf: [16:0]u8 = undefined;
        const battery_str = std.fmt.bufPrintZ(&battery_buf, "BAT: {d}%", .{battery_percentage}) catch break :draw_battery;

        var battery_y: usize = config.edge_margin;
        if (!config.hide_key_hints) {
            battery_y += 1;
        }
        state.buffer.drawLabel(battery_str, config.edge_margin, battery_y);
        state.can_draw_battery = true;
    }

    if (config.bigclock != .none and state.buffer.box_height + (bigclock.HEIGHT + 2) * 2 < state.buffer.height) {
        var format_buf: [16:0]u8 = undefined;
        var clock_buf: [32:0]u8 = undefined;
        // We need the slice/c-string returned by `bufPrintZ`.
        const format = try std.fmt.bufPrintZ(&format_buf, "{s}{s}{s}{s}", .{
            if (config.bigclock_12hr) "%I" else "%H",
            ":%M",
            if (config.bigclock_seconds) ":%S" else "",
            if (config.bigclock_12hr) "%P" else "",
        });
        const xo = state.buffer.width / 2 - @min(state.buffer.width, (format.len * (bigclock.WIDTH + 1))) / 2;
        const yo = (state.buffer.height - state.buffer.box_height) / 2 - bigclock.HEIGHT - 2;

        const clock_str = interop.timeAsString(&clock_buf, format);

        for (clock_str, 0..) |c, i| {
            // TODO: Show error
            const clock_cell = try bigclock.clockCell(state.animate, c, state.buffer.fg, state.buffer.bg, config.bigclock);
            bigclock.alphaBlit(xo + i * (bigclock.WIDTH + 1), yo, state.buffer.width, state.buffer.height, clock_cell);
        }
    }

    state.buffer.drawBoxCenter(!config.hide_borders, config.blank_box);

    if (state.resolution_changed) {
        const coordinates = state.buffer.calculateComponentCoordinates();
        state.info_line.label.position(coordinates.start_x, coordinates.y, coordinates.full_visible_length, null);
        state.session.label.position(coordinates.x, coordinates.y + 2, coordinates.visible_length, config.text_in_center);
        state.login.label.position(coordinates.x, coordinates.y + 4, coordinates.visible_length, config.text_in_center);
        state.password.position(coordinates.x, coordinates.y + 6, coordinates.visible_length);

        state.resolution_changed = false;
    }

    switch (state.active_input) {
        .info_line => state.info_line.label.handle(null, state.insert_mode),
        .session => state.session.label.handle(null, state.insert_mode),
        .login => state.login.label.handle(null, state.insert_mode),
        .password => state.password.handle(null, state.insert_mode) catch |err| {
            try state.info_line.addMessage(lang.err_alloc, config.error_bg, config.error_fg);
            try log_file.err("tui", "failed to handle password input: {s}", .{@errorName(err)});
        },
    }

    if (config.clock) |clock| draw_clock: {
        if (!state.can_draw_clock) break :draw_clock;

        var clock_buf: [64:0]u8 = undefined;
        const clock_str = interop.timeAsString(&clock_buf, clock);

        if (clock_str.len == 0) {
            try state.info_line.addMessage(lang.err_clock_too_long, config.error_bg, config.error_fg);
            state.can_draw_clock = false;
            try log_file.err("tui", "clock string too long", .{});
            break :draw_clock;
        }

        state.buffer.drawLabel(clock_str, state.buffer.width - @min(state.buffer.width, clock_str.len) - config.edge_margin, config.edge_margin);
    }

    const label_x = state.buffer.box_x + state.buffer.margin_box_h;
    const label_y = state.buffer.box_y + state.buffer.margin_box_v;

    state.buffer.drawLabel(lang.login, label_x, label_y + 4);
    state.buffer.drawLabel(lang.password, label_x, label_y + 6);

    state.info_line.label.draw();

    if (!config.hide_key_hints) {
        state.buffer.drawLabel(config.shutdown_key, length, config.edge_margin);
        length += config.shutdown_key.len + 1;
        state.buffer.drawLabel(" ", length - 1, config.edge_margin);

        state.buffer.drawLabel(lang.shutdown, length, config.edge_margin);
        length += state.shutdown_len + 1;

        state.buffer.drawLabel(config.restart_key, length, config.edge_margin);
        length += config.restart_key.len + 1;
        state.buffer.drawLabel(" ", length - 1, config.edge_margin);

        state.buffer.drawLabel(lang.restart, length, config.edge_margin);
        length += state.restart_len + 1;

        if (config.sleep_cmd != null) {
            state.buffer.drawLabel(config.sleep_key, length, config.edge_margin);
            length += config.sleep_key.len + 1;
            state.buffer.drawLabel(" ", length - 1, config.edge_margin);

            state.buffer.drawLabel(lang.sleep, length, config.edge_margin);
            length += state.sleep_len + 1;
        }

        if (config.hibernate_cmd != null) {
            state.buffer.drawLabel(config.hibernate_key, length, config.edge_margin);
            length += config.hibernate_key.len + 1;
            state.buffer.drawLabel(" ", length - 1, config.edge_margin);

            state.buffer.drawLabel(lang.hibernate, length, config.edge_margin);
            length += state.hibernate_len + 1;
        }

        if (config.brightness_down_key) |key| {
            state.buffer.drawLabel(key, length, config.edge_margin);
            length += key.len + 1;
            state.buffer.drawLabel(" ", length - 1, config.edge_margin);

            state.buffer.drawLabel(lang.brightness_down, length, config.edge_margin);
            length += state.brightness_down_len + 1;
        }

        if (config.brightness_up_key) |key| {
            state.buffer.drawLabel(key, length, config.edge_margin);
            length += key.len + 1;
            state.buffer.drawLabel(" ", length - 1, config.edge_margin);

            state.buffer.drawLabel(lang.brightness_up, length, config.edge_margin);
            length += state.brightness_up_len + 1;
        }
    }

    if (config.box_title) |title| {
        state.buffer.drawConfinedLabel(title, state.buffer.box_x, state.buffer.box_y - 1, state.buffer.box_width);
    }

    if (config.vi_mode) {
        const label_txt = if (state.insert_mode) lang.insert else lang.normal;
        state.buffer.drawLabel(label_txt, state.buffer.box_x, state.buffer.box_y + state.buffer.box_height);
    }

    if (!config.hide_keyboard_locks and state.can_get_lock_state) draw_lock_state: {
        const lock_state = interop.getLockState() catch |err| {
            try state.info_line.addMessage(lang.err_lock_state, config.error_bg, config.error_fg);
            state.can_get_lock_state = false;
            try log_file.err("sys", "failed to get lock state: {s}", .{@errorName(err)});
            break :draw_lock_state;
        };

        var lock_state_x = state.buffer.width - @min(state.buffer.width, lang.numlock.len) - config.edge_margin;
        var lock_state_y: usize = config.edge_margin;

        if (config.clock != null) lock_state_y += 1;

        if (lock_state.numlock) state.buffer.drawLabel(lang.numlock, lock_state_x, lock_state_y);

        if (lock_state_x >= lang.capslock.len + 1) {
            lock_state_x -= lang.capslock.len + 1;
            if (lock_state.capslock) state.buffer.drawLabel(lang.capslock, lock_state_x, lock_state_y);
        }
    }

    state.session.label.draw();
    state.login.label.draw();
    state.password.draw();

    _ = TerminalBuffer.presentBufferStatic();
    return true;
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
    if (!std.fs.path.isAbsolute(path)) return error.PathNotAbsolute;

    var iterable_directory = try std.fs.openDirAbsolute(path, .{ .iterate = true });
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

        const file_name = try session.label.allocator.dupe(u8, std.fs.path.stem(item.name));
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
            if (file_name.len > 0) maybe_xdg_session_desktop = file_name;
        }

        try session.addEnvironment(.{
            .entry_ini = entry_ini,
            .file_name = file_name,
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

fn isValidUsername(username: []const u8, usernames: StringList) bool {
    for (usernames.items) |valid_username| {
        if (std.mem.eql(u8, username, valid_username)) return true;
    }
    return false;
}

fn findSessionByName(session: *Session, name: []const u8) ?usize {
    for (session.label.list.items, 0..) |env, i| {
        if (std.ascii.eqlIgnoreCase(env.environment.file_name, name)) return i;
        if (std.ascii.eqlIgnoreCase(env.environment.name, name)) return i;
        if (env.environment.xdg_session_desktop) |session_desktop| {
            if (session_desktop.len > 0 and std.ascii.eqlIgnoreCase(session_desktop, name)) return i;
        }
        if (env.environment.xdg_desktop_names) |session_desktop_name| {
            if (std.ascii.eqlIgnoreCase(session_desktop_name, name)) return i;
        }
    }
    return null;
}

fn getAllUsernames(allocator: std.mem.Allocator, login_defs_path: []const u8, uid_range_error: *?anyerror) !StringList {
    const uid_range = interop.getUserIdRange(allocator, login_defs_path) catch |err| no_uid_range: {
        uid_range_error.* = err;
        break :no_uid_range UidRange{
            .uid_min = build_options.fallback_uid_min,
            .uid_max = build_options.fallback_uid_max,
        };
    };

    // There's no reliable (and clean) way to check for systemd support, so
    // let's just define a range and check if a user is within it
    const SYSTEMD_HOMED_UID_MIN = 60001;
    const SYSTEMD_HOMED_UID_MAX = 60513;
    const homed_uid_range = UidRange{
        .uid_min = SYSTEMD_HOMED_UID_MIN,
        .uid_max = SYSTEMD_HOMED_UID_MAX,
    };

    var usernames: StringList = .empty;
    var maybe_entry = interop.getNextUsernameEntry();

    while (maybe_entry) |entry| {
        // We check if the UID is equal to 0 because we always want to add root
        // as a username (even if you can't log into it)
        const is_within_range =
            entry.uid >= uid_range.uid_min and
            entry.uid <= uid_range.uid_max;
        const is_within_homed_range =
            builtin.os.tag == .linux and
            entry.uid >= homed_uid_range.uid_min and
            entry.uid <= homed_uid_range.uid_max;
        const is_root =
            entry.uid == 0 and
            entry.username != null;

        if (is_within_range or is_within_homed_range or is_root) {
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
