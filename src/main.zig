const std = @import("std");
const Allocator = std.mem.Allocator;
const StringList = std.ArrayListUnmanaged([]const u8);
const temporary_allocator = std.heap.page_allocator;
const builtin = @import("builtin");
const build_options = @import("build_options");

const clap = @import("clap");
const ly_ui = @import("ly-ui");
const Position = ly_ui.Position;
const BigLabel = ly_ui.BigLabel;
const Box = ly_ui.Box;
const Label = ly_ui.Label;
const Text = ly_ui.Text;
const TerminalBuffer = ly_ui.TerminalBuffer;
const Widget = ly_ui.Widget;
const ly_core = ly_ui.ly_core;
const interop = ly_core.interop;
const UidRange = ly_core.UidRange;
const LogFile = ly_core.LogFile;
const SharedError = ly_core.SharedError;
const IniParser = ly_core.IniParser;
const ini = ly_core.ini;
const Ini = ini.Ini;

const Cascade = @import("animations/Cascade.zig");
const ColorMix = @import("animations/ColorMix.zig");
const Doom = @import("animations/Doom.zig");
const DurFile = @import("animations/DurFile.zig");
const GameOfLife = @import("animations/GameOfLife.zig");
const Matrix = @import("animations/Matrix.zig");
const auth = @import("auth.zig");
const InfoLine = @import("components/InfoLine.zig");
const Session = @import("components/Session.zig");
const UserList = @import("components/UserList.zig");
const Config = @import("config/Config.zig");
const Lang = @import("config/Lang.zig");
const migrator = @import("config/migrator.zig");
const OldSave = @import("config/OldSave.zig");
const SavedUsers = @import("config/SavedUsers.zig");
const custom = @import("config/custom.zig");
const DisplayServer = @import("enums.zig").DisplayServer;
const Environment = @import("Environment.zig");
const Entry = Environment.Entry;

const ly_version_str = "Ly version " ++ build_options.version;

var session_pid: std.posix.pid_t = -1;
fn signalHandler(sig: std.posix.SIG) callconv(.c) void {
    if (session_pid == 0) return;

    // Forward signal to session to clean up
    if (session_pid > 0) {
        _ = std.c.kill(session_pid, sig);
        var status: c_int = 0;
        _ = std.c.waitpid(session_pid, &status, 0);
    }

    TerminalBuffer.shutdown();
    std.c.exit(@intCast(@intFromEnum(sig)));
}

fn ttyControlTransferSignalHandler(_: std.posix.SIG) callconv(.c) void {
    TerminalBuffer.shutdown();
}

const CustomBindLabel = struct {
    cmd: custom.CustomCommandBind,
    key: []const u8,
    lbl: Label,
    io: std.Io,
};

const CustomInfoLabel = struct {
    info: custom.CustomCommandInfo,
    lbl: Label,
};

const UiState = struct {
    allocator: Allocator,
    io: std.Io,
    auth_fails: u64,
    is_autologin: bool,
    use_kmscon_vt: bool,
    active_tty: u8,
    buffer: TerminalBuffer,
    labels_max_length: usize,
    shutdown_label: Label,
    restart_label: Label,
    sleep_label: Label,
    hibernate_label: Label,
    toggle_password_label: Label,
    brightness_down_label: Label,
    brightness_up_label: Label,
    numlock_label: Label,
    capslock_label: Label,
    battery_label: Label,
    clock_label: Label,
    tty_label: Label,
    session_specifier_label: Label,
    login_label: Label,
    password_label: Label,
    version_label: Label,
    bigclock_label: BigLabel,
    box: Box,
    info_line: InfoLine,
    animate: bool,
    session: Session,
    saved_users: SavedUsers,
    login: UserList,
    password: *Text,
    password_widget: *Widget,
    insert_mode: bool,
    edge_margin: Position,
    config: Config,
    lang: Lang,
    log_file: LogFile,
    save_path: []const u8,
    old_save_path: []const u8,
    has_old_save: bool,
    battery_buf: [16:0]u8,
    bigclock_format_buf: [16:0]u8,
    clock_buf: [64:0]u8,
    tty_buf: [8:0]u8,
    bigclock_buf: [32:0]u8,
    custom_binds: std.ArrayList(CustomBindLabel),
    custom_info: std.ArrayList(CustomInfoLabel),
};

var shutdown = false;
var restart = false;

pub fn main(init: std.process.Init) !void {
    var shutdown_cmd: []const u8 = undefined;
    var restart_cmd: []const u8 = undefined;
    var commands_allocated = false;
    var state: UiState = undefined;

    state.io = init.io;

    var stderr_buffer: [128]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(state.io, &stderr_buffer);
    var stderr = &stderr_writer.interface;

    defer {
        // If we can't shutdown or restart due to an error, we print it to standard error. If that fails, just bail out
        if (shutdown) {
            const shutdown_error = std.process.replace(state.io, .{ .argv = &[_][]const u8{ "/bin/sh", "-c", shutdown_cmd } });
            std.log.err("couldn't shutdown: {s}", .{@errorName(shutdown_error)});
        } else if (restart) {
            const restart_error = std.process.replace(state.io, .{ .argv = &[_][]const u8{ "/bin/sh", "-c", restart_cmd } });
            std.log.err("couldn't restart: {s}", .{@errorName(restart_error)});
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

    state.allocator = gpa.allocator();

    // Load arguments
    const params = comptime clap.parseParamsComptime(
        \\-h, --help                Shows all commands.
        \\-v, --version             Shows the version of Ly.
        \\-c, --config <str>        Overrides the default configuration path. Example: --config /usr/share/ly
        \\--use-kmscon-vt           Uses KMSCON instead of the kernel VT.
        \\--validate-config <str>   Validates the given configuration file.
    );

    var diag = clap.Diagnostic{};
    var arg_parse_error: anyerror = undefined;
    var maybe_res = clap.parse(clap.Help, &params, clap.parsers.default, init.minimal.args, .{ .diagnostic = &diag, .allocator = state.allocator }) catch |err| parse_error: {
        arg_parse_error = err;
        diag.report(stderr, err) catch {};
        try stderr.flush();
        break :parse_error null;
    };
    defer if (maybe_res) |*res| res.deinit();

    var old_save_parser: ?IniParser(OldSave) = null;
    defer if (old_save_parser) |*str| str.deinit();

    state.use_kmscon_vt = false;

    var start_cmd_exit_code: u8 = 0;

    state.saved_users = SavedUsers.init();
    defer state.saved_users.deinit(state.allocator);

    var config_parent_path: []const u8 = build_options.config_directory ++ "/ly";
    if (maybe_res) |*res| {
        if (res.args.help != 0) {
            try clap.help(stderr, clap.Help, &params, .{});

            std.log.info("note: if you want to configure Ly, please check the config file, which is located at " ++ build_options.config_directory ++ "/ly/config.ini.", .{});
            std.process.exit(0);
        }
        if (res.args.version != 0) {
            std.log.info("ly version " ++ build_options.version, .{});
            std.process.exit(0);
        }
        if (res.args.config) |path| config_parent_path = path;
        if (res.args.@"use-kmscon-vt" != 0) state.use_kmscon_vt = true;
        if (res.args.@"validate-config") |path| {
            var parser = try IniParser(Config).init(
                state.allocator,
                state.io,
                path,
                migrator.configFieldHandler,
            );
            defer parser.deinit();

            for (parser.errors.items) |err| {
                std.log.err(
                    "failed to convert value '{s}' of option '{s}' to type '{s}': {s}",
                    .{ err.value, err.key, err.type_name, err.error_name },
                );
            }

            if (parser.maybe_load_error) |err| {
                std.log.err("failed to load config file: {s}", .{@errorName(err)});
                std.process.exit(1);
            }

            std.log.info("no errors detected!", .{});
            std.process.exit(0);
        }
    }

    // Load configuration file
    var save_path_alloc = false;

    state.save_path = build_options.config_directory ++ "/ly/save.txt";
    state.old_save_path = build_options.config_directory ++ "/ly/save.ini";
    defer if (save_path_alloc) {
        state.allocator.free(state.save_path);
        state.allocator.free(state.old_save_path);
    };

    const config_path = try std.Io.Dir.path.join(state.allocator, &[_][]const u8{ config_parent_path, "config.ini" });
    defer state.allocator.free(config_path);

    custom.binds = .empty;
    custom.labels = .empty;
    var config_parser = try IniParser(Config).init(state.allocator, state.io, config_path, migrator.configFieldHandler);
    defer config_parser.deinit();
    defer if (!shutdown or !restart) {
        var iter = custom.binds.iterator();
        while (iter.next()) |i| {
            temporary_allocator.free(i.key_ptr.*);
            temporary_allocator.free(i.value_ptr.*.cmd);
            temporary_allocator.free(i.value_ptr.*.name);
        }
        custom.binds.deinit(temporary_allocator);
        var labelIter = custom.labels.iterator();
        while (labelIter.next()) |i| {
            temporary_allocator.free(i.key_ptr.*);
            if (i.value_ptr.cmd) |cmd|
                temporary_allocator.free(cmd);
        }
        custom.labels.deinit(temporary_allocator);
    };

    state.config = config_parser.structure;

    var lang_buffer: [16]u8 = undefined;
    const lang_file = try std.fmt.bufPrint(&lang_buffer, "{s}.ini", .{state.config.lang});

    const lang_path = try std.Io.Dir.path.join(state.allocator, &[_][]const u8{ config_parent_path, "lang", lang_file });
    defer state.allocator.free(lang_path);

    var lang_parser = try IniParser(Lang).init(state.allocator, state.io, lang_path, null);
    defer lang_parser.deinit();

    state.lang = lang_parser.structure;

    if (state.config.save) {
        state.save_path = try std.Io.Dir.path.join(state.allocator, &[_][]const u8{ config_parent_path, "save.txt" });
        state.old_save_path = try std.Io.Dir.path.join(state.allocator, &[_][]const u8{ config_parent_path, "save.ini" });
        save_path_alloc = true;
    }

    if (config_parser.maybe_load_error == null) {
        migrator.lateConfigFieldHandler(&state.config);
    }

    var maybe_uid_range_error: ?anyerror = null;
    var usernames = try getAllUsernames(state.allocator, state.io, state.config.login_defs_path, &maybe_uid_range_error);
    defer {
        for (usernames.items) |username| state.allocator.free(username);
        usernames.deinit(state.allocator);
    }

    state.has_old_save = false;

    if (state.config.save) read_save_file: {
        old_save_parser = migrator.tryMigrateIniSaveFile(state.allocator, state.io, state.old_save_path, &state.saved_users, usernames.items) catch break :read_save_file;

        // Don't read the new save file if the old one still exists
        if (old_save_parser != null) {
            state.has_old_save = true;
            break :read_save_file;
        }

        var save_file = std.Io.Dir.cwd().openFile(state.io, state.save_path, .{}) catch break :read_save_file;
        defer save_file.close(state.io);

        var file_buffer: [256]u8 = undefined;
        var file_reader = save_file.reader(state.io, &file_buffer);
        var reader = &file_reader.interface;

        const last_username_index_str = reader.takeDelimiterInclusive('\n') catch break :read_save_file;
        state.saved_users.last_username_index = std.fmt.parseInt(usize, last_username_index_str[0..(last_username_index_str.len - 1)], 10) catch break :read_save_file;

        while (reader.seek < reader.buffer.len) {
            const line = reader.takeDelimiterInclusive('\n') catch break;

            var user = std.mem.splitScalar(u8, line[0..(line.len - 1)], ':');
            const username = user.next() orelse continue;
            const session_index_str = user.next() orelse continue;

            const session_index = std.fmt.parseInt(usize, session_index_str, 10) catch continue;

            try state.saved_users.user_list.append(state.allocator, .{
                .username = try state.allocator.dupe(u8, username),
                .session_index = session_index,
                .first_run = false,
                .allocated_username = true,
            });
        }
    }

    // If no save file previously existed, fill it up with all usernames
    // TODO: Add new username with existing save file
    if (state.config.save and state.saved_users.user_list.items.len == 0) {
        for (usernames.items) |user| {
            try state.saved_users.user_list.append(state.allocator, .{
                .username = user,
                .session_index = 0,
                .first_run = true,
                .allocated_username = false,
            });
        }
    }

    var log_file_buffer: [1024]u8 = undefined;

    state.log_file = try LogFile.init(state.io, state.config.ly_log, &log_file_buffer);
    defer state.log_file.deinit(state.io);

    try state.log_file.info(state.io, "tui", "using {s} vt", .{if (state.use_kmscon_vt) "kmscon" else "default"});

    // These strings only end up getting freed if the user quits Ly using Ctrl+C, which is fine since in the other cases
    // we end up shutting down or restarting the system
    shutdown_cmd = try temporary_allocator.dupe(u8, state.config.shutdown_cmd);
    restart_cmd = try temporary_allocator.dupe(u8, state.config.restart_cmd);
    commands_allocated = true;

    if (state.config.start_cmd) |start_cmd| handle_start_cmd: {
        var process = std.process.spawn(state.io, .{
            .argv = &[_][]const u8{ "/bin/sh", "-c", start_cmd },
            .stdout = .inherit,
            .stderr = .ignore,
        }) catch {
            break :handle_start_cmd;
        };

        const process_result = process.wait(state.io) catch {
            break :handle_start_cmd;
        };
        start_cmd_exit_code = process_result.exited;
    }

    // Initialize terminal buffer
    try state.log_file.info(state.io, "tui", "initializing terminal buffer", .{});
    state.labels_max_length = @max(TerminalBuffer.strWidth(state.lang.login), TerminalBuffer.strWidth(state.lang.password));

    var seed: u64 = undefined;
    state.io.random(std.mem.asBytes(&seed)); // Get a random seed for the PRNG (used by animations)

    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    const buffer_options = TerminalBuffer.InitOptions{
        .fg = state.config.fg,
        .bg = state.config.bg,
        .border_fg = state.config.border_fg,
        .full_color = state.config.full_color,
        .is_tty = true,
    };
    state.buffer = try TerminalBuffer.init(
        state.allocator,
        state.io,
        buffer_options,
        &state.log_file,
        random,
    );
    defer {
        state.log_file.info(state.io, "tui", "shutting down terminal buffer", .{}) catch {};
        state.buffer.deinit();
    }

    const act = std.posix.Sigaction{
        .handler = .{ .handler = &signalHandler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.TERM, &act, null);

    // Initialize components
    state.shutdown_label = Label.init(
        "",
        null,
        state.buffer.fg,
        state.buffer.bg,
        null,
        null,
    );
    defer state.shutdown_label.deinit();

    state.restart_label = Label.init(
        "",
        null,
        state.buffer.fg,
        state.buffer.bg,
        null,
        null,
    );
    defer state.restart_label.deinit();

    state.sleep_label = Label.init(
        "",
        null,
        state.buffer.fg,
        state.buffer.bg,
        null,
        null,
    );
    defer state.sleep_label.deinit();

    state.hibernate_label = Label.init(
        "",
        null,
        state.buffer.fg,
        state.buffer.bg,
        null,
        null,
    );
    defer state.hibernate_label.deinit();

    state.toggle_password_label = Label.init(
        "",
        null,
        state.buffer.fg,
        state.buffer.bg,
        null,
        null,
    );
    defer state.toggle_password_label.deinit();

    state.brightness_down_label = Label.init(
        "",
        null,
        state.buffer.fg,
        state.buffer.bg,
        null,
        null,
    );
    defer state.brightness_down_label.deinit();

    state.brightness_up_label = Label.init(
        "",
        null,
        state.buffer.fg,
        state.buffer.bg,
        null,
        null,
    );
    defer state.brightness_up_label.deinit();

    if (!state.config.hide_key_hints) {
        try state.shutdown_label.setTextAlloc(
            state.allocator,
            "{s} {s}",
            .{ state.config.shutdown_key, state.lang.shutdown },
        );
        try state.restart_label.setTextAlloc(
            state.allocator,
            "{s} {s}",
            .{ state.config.restart_key, state.lang.restart },
        );
        try state.toggle_password_label.setTextAlloc(
            state.allocator,
            "{s} {s}",
            .{ state.config.show_password_key, state.lang.toggle_password },
        );
        if (state.config.sleep_cmd != null) {
            try state.sleep_label.setTextAlloc(
                state.allocator,
                "{s} {s}",
                .{ state.config.sleep_key, state.lang.sleep },
            );
        }
        if (state.config.hibernate_cmd != null) {
            try state.hibernate_label.setTextAlloc(
                state.allocator,
                "{s} {s}",
                .{ state.config.hibernate_key, state.lang.hibernate },
            );
        }
        if (state.config.brightness_down_key) |key| {
            try state.brightness_down_label.setTextAlloc(
                state.allocator,
                "{s} {s}",
                .{ key, state.lang.brightness_down },
            );
        }
        if (state.config.brightness_up_key) |key| {
            try state.brightness_up_label.setTextAlloc(
                state.allocator,
                "{s} {s}",
                .{ key, state.lang.brightness_up },
            );
        }
    }

    state.numlock_label = Label.init(
        "",
        null,
        state.buffer.fg,
        state.buffer.bg,
        &updateNumlock,
        null,
    );
    defer state.numlock_label.deinit();

    state.capslock_label = Label.init(
        "",
        null,
        state.buffer.fg,
        state.buffer.bg,
        &updateCapslock,
        null,
    );
    defer state.capslock_label.deinit();

    state.battery_label = Label.init(
        "",
        null,
        state.buffer.fg,
        state.buffer.bg,
        &updateBattery,
        null,
    );
    defer state.battery_label.deinit();

    state.clock_label = Label.init(
        "",
        null,
        state.buffer.fg,
        state.buffer.bg,
        &updateClock,
        &calculateClockTimeout,
    );
    defer state.clock_label.deinit();

    state.tty_label = Label.init(
        "",
        null,
        state.buffer.fg,
        state.buffer.bg,
        null,
        null,
    );
    defer state.tty_label.deinit();

    state.bigclock_label = BigLabel.init(
        &state.buffer,
        "",
        null,
        state.buffer.fg,
        state.buffer.bg,
        switch (state.config.bigclock) {
            .none, .en => .en,
            .fa => .fa,
        },
        &updateBigClock,
        &calculateBigClockTimeout,
    );
    defer state.bigclock_label.deinit();

    state.box = Box.init(
        &state.buffer,
        state.config.margin_box_h,
        state.config.margin_box_v,
        (2 * state.config.margin_box_h) + state.config.input_len + 1 + state.labels_max_length,
        7 + (2 * state.config.margin_box_v),
        !state.config.hide_borders,
        state.config.blank_box,
        state.config.box_title,
        null,
        state.buffer.border_fg,
        state.buffer.fg,
        state.buffer.bg,
        &updateBox,
    );

    state.info_line = try InfoLine.init(
        state.allocator,
        state.io,
        &state.buffer,
        state.box.width - 2 * state.box.horizontal_margin,
        state.buffer.fg,
        state.buffer.bg,
    );
    defer state.info_line.deinit();

    try state.buffer.registerKeybind(state.io, &state.info_line.label.keybinds, "H", &viGoLeft, &state);
    try state.buffer.registerKeybind(state.io, &state.info_line.label.keybinds, "L", &viGoRight, &state);

    if (maybe_res == null) {
        var longest = diag.name.longest();
        if (longest.kind == .positional)
            longest.name = diag.arg;

        try state.info_line.addMessage(
            state.lang.err_args,
            state.config.error_bg,
            state.config.error_fg,
        );
        try state.log_file.err(
            state.io,
            "cli",
            "unable to parse argument '{s}{s}': {s}",
            .{ longest.kind.prefix(), longest.name, @errorName(arg_parse_error) },
        );
    }

    if (maybe_uid_range_error) |err| {
        try state.info_line.addMessage(
            state.lang.err_uid_range,
            state.config.error_bg,
            state.config.error_fg,
        );
        try state.log_file.err(
            state.io,
            "sys",
            "failed to get uid range: {s}; falling back to default",
            .{@errorName(err)},
        );
    }

    if (start_cmd_exit_code != 0) {
        try state.info_line.addMessage(
            state.lang.err_start,
            state.config.error_bg,
            state.config.error_fg,
        );
        try state.log_file.err(
            state.io,
            "sys",
            "failed to execute start command: exit code {d}",
            .{start_cmd_exit_code},
        );
    }

    if (config_parser.maybe_load_error) |load_error| {
        // We can't localize this since the config failed to load so we'd fallback to the default language anyway
        try state.info_line.addMessage(
            "unable to parse config file",
            state.config.error_bg,
            state.config.error_fg,
        );
        try state.log_file.err(
            state.io,
            "conf",
            "unable to parse config file: {s}",
            .{@errorName(load_error)},
        );

        for (config_parser.errors.items) |err| {
            try state.log_file.err(
                state.io,
                "conf",
                "failed to convert value '{s}' of option '{s}' to type '{s}': {s}",
                .{ err.value, err.key, err.type_name, err.error_name },
            );
        }
    }

    if (!state.log_file.could_open_log_file) {
        try state.info_line.addMessage(
            state.lang.err_log,
            state.config.error_bg,
            state.config.error_fg,
        );
        try state.log_file.err(
            state.io,
            "sys",
            "failed to open log file",
            .{},
        );
    }

    interop.setNumlock(state.config.numlock) catch |err| {
        try state.info_line.addMessage(
            state.lang.err_numlock,
            state.config.error_bg,
            state.config.error_fg,
        );
        try state.log_file.err(
            state.io,
            "sys",
            "failed to set numlock: {s}",
            .{@errorName(err)},
        );
    };

    state.session_specifier_label = Label.init(
        "",
        null,
        state.buffer.fg,
        state.buffer.bg,
        &updateSessionSpecifier,
        null,
    );
    defer state.session_specifier_label.deinit();

    state.session = try Session.init(
        state.allocator,
        state.io,
        &state.buffer,
        &state.login,
        state.box.width - 2 * state.box.horizontal_margin - state.labels_max_length - 1,
        state.config.text_in_center,
        state.buffer.fg,
        state.buffer.bg,
    );
    defer state.session.deinit();

    try state.buffer.registerKeybind(state.io, &state.session.label.keybinds, "H", &viGoLeft, &state);
    try state.buffer.registerKeybind(state.io, &state.session.label.keybinds, "L", &viGoRight, &state);

    state.login_label = Label.init(
        state.lang.login,
        null,
        state.buffer.fg,
        state.buffer.bg,
        null,
        null,
    );
    defer state.login_label.deinit();

    state.login = try UserList.init(
        state.allocator,
        state.io,
        &state.buffer,
        usernames,
        &state.saved_users,
        &state.session,
        state.box.width - 2 * state.box.horizontal_margin - state.labels_max_length - 1,
        state.config.text_in_center,
        state.buffer.fg,
        state.buffer.bg,
    );
    defer state.login.deinit();

    try state.buffer.registerKeybind(state.io, &state.login.label.keybinds, "H", &viGoLeft, &state);
    try state.buffer.registerKeybind(state.io, &state.login.label.keybinds, "L", &viGoRight, &state);

    if (state.config.shell) {
        addOtherEnvironment(&state.session, state.lang, .shell, null) catch |err| {
            try state.info_line.addMessage(
                state.lang.err_alloc,
                state.config.error_bg,
                state.config.error_fg,
            );
            try state.log_file.err(
                state.io,
                "sys",
                "failed to add shell environment: {s}",
                .{@errorName(err)},
            );
        };
    }

    if (build_options.enable_x11_support) {
        if (state.config.xinitrc) |xinitrc_cmd| {
            addOtherEnvironment(&state.session, state.lang, .xinitrc, xinitrc_cmd) catch |err| {
                try state.info_line.addMessage(
                    state.lang.err_alloc,
                    state.config.error_bg,
                    state.config.error_fg,
                );
                try state.log_file.err(
                    state.io,
                    "sys",
                    "failed to add xinitrc environment: {s}",
                    .{@errorName(err)},
                );
            };
        }
    } else {
        try state.info_line.addMessage(
            state.lang.no_x11_support,
            state.config.bg,
            state.config.fg,
        );
        try state.log_file.info(
            state.io,
            "comp",
            "x11 support disabled at compile-time",
            .{},
        );
    }

    var has_crawl_error = false;

    // Crawl session directories (Wayland, X11 and custom respectively)
    if (state.config.waylandsessions) |waylandsessions| {
        var wayland_session_dirs = std.mem.splitScalar(u8, waylandsessions, ':');
        while (wayland_session_dirs.next()) |dir| {
            crawl(&state.session, state.io, state.lang, dir, .wayland) catch |err| {
                has_crawl_error = true;
                try state.log_file.err(
                    state.io,
                    "sys",
                    "failed to crawl wayland session directory '{s}': {s}",
                    .{ dir, @errorName(err) },
                );
            };
        }
    }

    if (build_options.enable_x11_support) {
        if (state.config.xsessions) |xsessions| {
            var x_session_dirs = std.mem.splitScalar(u8, xsessions, ':');
            while (x_session_dirs.next()) |dir| {
                crawl(&state.session, state.io, state.lang, dir, .x11) catch |err| {
                    has_crawl_error = true;
                    try state.log_file.err(
                        state.io,
                        "sys",
                        "failed to crawl x11 session directory '{s}': {s}",
                        .{ dir, @errorName(err) },
                    );
                };
            }
        }
    }

    var custom_session_dirs = std.mem.splitScalar(u8, state.config.custom_sessions, ':');
    while (custom_session_dirs.next()) |dir| {
        crawl(&state.session, state.io, state.lang, dir, .custom) catch |err| {
            has_crawl_error = true;
            try state.log_file.err(
                state.io,
                "sys",
                "failed to crawl custom session directory '{s}': {s}",
                .{ dir, @errorName(err) },
            );
        };
    }

    if (has_crawl_error) {
        try state.info_line.addMessage(
            state.lang.err_crawl,
            state.config.error_bg,
            state.config.error_fg,
        );
    }

    if (usernames.items.len == 0) {
        // If we have no usernames, simply add an error to the info line.
        // This effectively means you can't login, since there would be no local
        // accounts *and* no root account...but at this point, if that's the
        // case, you have bigger problems to deal with in the first place. :D
        try state.info_line.addMessage(state.lang.err_no_users, state.config.error_bg, state.config.error_fg);
        try state.log_file.err(state.io, "sys", "no users found", .{});
    }

    state.password_label = Label.init(
        state.lang.password,
        null,
        state.buffer.fg,
        state.buffer.bg,
        null,
        null,
    );
    defer state.password_label.deinit();

    state.insert_mode = !state.config.vi_mode or state.config.vi_default_mode == .insert;

    state.password = try Text.init(
        state.allocator,
        state.io,
        &state.buffer,
        state.insert_mode,
        true,
        state.config.asterisk,
        state.box.width - 2 * state.box.horizontal_margin - state.labels_max_length - 1,
        state.buffer.fg,
        state.buffer.bg,
    );
    defer state.password.deinit();

    try state.buffer.registerKeybind(state.io, &state.password.keybinds, "H", &viGoLeft, &state);
    try state.buffer.registerKeybind(state.io, &state.password.keybinds, "L", &viGoRight, &state);

    state.password_widget = state.password.widget();

    state.version_label = Label.init(
        ly_version_str,
        null,
        state.buffer.fg,
        state.buffer.bg,
        null,
        null,
    );
    defer state.version_label.deinit();

    state.is_autologin = false;

    check_autologin: {
        const auto_user = state.config.auto_login_user orelse break :check_autologin;
        const auto_session = state.config.auto_login_session orelse break :check_autologin;

        if (!isValidUsername(auto_user, usernames)) {
            try state.info_line.addMessage(
                state.lang.err_pam_user_unknown,
                state.config.error_bg,
                state.config.error_fg,
            );
            try state.log_file.err(
                state.io,
                "auth",
                "autologin failed: username '{s}' not found",
                .{auto_user},
            );
            break :check_autologin;
        }

        const session_index = findSessionByName(&state.session, auto_session) orelse {
            try state.log_file.err(
                state.io,
                "auth",
                "autologin failed: session '{s}' not found",
                .{auto_session},
            );
            try state.info_line.addMessage(
                state.lang.err_autologin_session,
                state.config.error_bg,
                state.config.error_fg,
            );
            break :check_autologin;
        };
        try state.log_file.info(
            state.io,
            "auth",
            "attempting autologin for user '{s}' with session '{s}'",
            .{ auto_user, auto_session },
        );

        state.session.label.current = session_index;
        for (state.login.label.list.items, 0..) |username, i| {
            if (std.mem.eql(u8, username.name, auto_user)) {
                state.login.label.current = i;
                break;
            }
        }
        state.is_autologin = true;
    }

    // Switch to selected TTY
    state.active_tty = interop.getActiveTty(state.allocator, state.io, state.use_kmscon_vt) catch |err| no_tty_found: {
        try state.info_line.addMessage(
            state.lang.err_get_active_tty,
            state.config.error_bg,
            state.config.error_fg,
        );
        try state.log_file.err(
            state.io,
            "sys",
            "failed to get active tty: {s}",
            .{@errorName(err)},
        );
        break :no_tty_found build_options.fallback_tty;
    };
    if (!state.use_kmscon_vt) {
        interop.switchTty(state.active_tty) catch |err| {
            try state.info_line.addMessage(
                state.lang.err_switch_tty,
                state.config.error_bg,
                state.config.error_fg,
            );
            try state.log_file.err(
                state.io,
                "sys",
                "failed to switch to tty {d}: {s}",
                .{ state.active_tty, @errorName(err) },
            );
        };
    }

    if (state.config.show_tty) {
        try state.tty_label.setTextBuf(&state.tty_buf, "tty{d}", .{state.active_tty});
    }

    // Initialize the animation, if any
    var animation: ?*Widget = null;
    switch (state.config.animation) {
        .none => {},
        .doom => {
            var doom = try Doom.init(
                state.allocator,
                &state.buffer,
                state.config.doom_top_color,
                state.config.doom_middle_color,
                state.config.doom_bottom_color,
                state.config.doom_fire_height,
                state.config.doom_fire_spread,
                &state.animate,
                state.config.animation_timeout_sec,
                state.config.animation_frame_delay,
            );
            animation = doom.widget();
        },
        .matrix => {
            var matrix = try Matrix.init(
                state.allocator,
                &state.buffer,
                state.config.cmatrix_fg,
                state.config.cmatrix_head_col,
                state.config.cmatrix_min_codepoint,
                state.config.cmatrix_max_codepoint,
                &state.animate,
                state.config.animation_timeout_sec,
                state.config.animation_frame_delay,
            );
            animation = matrix.widget();
        },
        .colormix => {
            var color_mix = try ColorMix.init(
                &state.buffer,
                state.config.colormix_col1,
                state.config.colormix_col2,
                state.config.colormix_col3,
                &state.animate,
                state.config.animation_timeout_sec,
                state.config.animation_frame_delay,
            );
            animation = color_mix.widget();
        },
        .gameoflife => {
            var game_of_life = try GameOfLife.init(
                state.allocator,
                &state.buffer,
                state.config.gameoflife_fg,
                state.config.gameoflife_entropy_interval,
                state.config.gameoflife_frame_delay,
                state.config.gameoflife_initial_density,
                &state.animate,
                state.config.animation_timeout_sec,
                state.config.animation_frame_delay,
            );
            animation = game_of_life.widget();
        },
        .dur_file => {
            var dur = try DurFile.init(
                state.allocator,
                state.io,
                &state.buffer,
                &state.log_file,
                state.config.dur_file_path,
                state.config.dur_offset_alignment,
                state.config.dur_x_offset,
                state.config.dur_y_offset,
                state.config.full_color,
                &state.animate,
                state.config.animation_timeout_sec,
                state.config.animation_frame_delay,
            );
            animation = dur.widget();
        },
    }
    defer if (animation) |a| a.deinit();

    var cascade = Cascade.init(
        state.io,
        &state.buffer,
        &state.auth_fails,
        state.config.auth_fails,
    );

    state.auth_fails = 0;
    state.animate = state.config.animation != .none;
    state.edge_margin = Position.init(
        state.config.edge_margin,
        state.config.edge_margin,
    );

    // Load last saved username and desktop selection, if any
    // Skip if autologin is active to prevent overriding autologin session
    var default_input = state.config.default_input;

    if (state.config.save and !state.is_autologin) {
        if (state.saved_users.last_username_index) |index| load_last_user: {
            // If the saved index isn't valid, bail out
            if (index >= state.saved_users.user_list.items.len) break :load_last_user;

            const user = state.saved_users.user_list.items[index];

            // Find user with saved name, and switch over to it
            // If it doesn't exist (anymore), we don't change the value
            for (usernames.items, 0..) |username, i| {
                if (std.mem.eql(u8, username, user.username)) {
                    state.login.label.current = i;
                    break;
                }
            }

            default_input = .password;

            state.session.label.current = @min(user.session_index, state.session.label.list.items.len - 1);
        }
    }

    const info_line_widget = state.info_line.widget();
    const session_widget = state.session.widget();
    const login_widget = state.login.widget();

    var widgets: std.ArrayList([]*Widget) = .empty;
    defer widgets.deinit(state.allocator);

    // Layer 1
    if (animation) |a| {
        var layer1 = [_]*Widget{a};
        try widgets.append(state.allocator, &layer1);
    }

    // Layer 2
    var layer2: std.ArrayList(*Widget) = .empty;
    defer layer2.deinit(state.allocator);

    state.custom_binds = .empty;
    defer state.custom_binds.deinit(state.allocator);

    state.custom_info = .empty;
    defer state.custom_info.deinit(state.allocator);

    var lblIter = custom.labels.iterator();
    // NOTE: Because widgets have a pointer to the underlying Label, we have to ensure
    // that the ArrayList doesn't allocate more memory than what we ensured. Otherwise
    // the pointer to the Label becomes invalid.
    try state.custom_info.ensureTotalCapacity(state.allocator, @intCast(custom.labels.count()));
    while (lblIter.next()) |i| {
        try state.custom_info.append(state.allocator, .{
            .info = i.value_ptr.*,
            .lbl = .init("", null, state.buffer.fg, state.buffer.bg, updateCustomInfo, null),
        });
        var latest = &state.custom_info.items[state.custom_info.items.len - 1];
        latest.info.id = latest.lbl.widget().id;
        latest.info.counter = 1;
    }
    defer for (state.custom_info.items) |*item| {
        item.lbl.deinit();
    };

    var iter = custom.binds.iterator();
    defer for (state.custom_binds.items) |*i| {
        i.lbl.deinit();
    };

    if (!state.config.hide_key_hints) {
        while (iter.next()) |i| {
            var concat = try std.mem.concat(state.allocator, u8, &[_][]const u8{ i.key_ptr.*, " ", i.value_ptr.name });
            inline for (@typeInfo(Lang).@"struct".fields) |lang_key| {
                const new = try std.mem.replaceOwned(u8, state.allocator, concat, "$" ++ lang_key.name, @field(state.lang, lang_key.name));
                state.allocator.free(concat);
                concat = new;
            }
            try state.custom_binds.append(state.allocator, .{
                .lbl = .init(
                    concat,
                    null,
                    state.buffer.fg,
                    state.buffer.bg,
                    null,
                    null,
                ),
                .cmd = i.value_ptr.*,
                .key = i.key_ptr.*,
                .io = state.io,
            });
            state.custom_binds.items[state.custom_binds.items.len - 1].lbl.allocator = state.allocator;
        }
        try layer2.append(state.allocator, state.shutdown_label.widget());
        try layer2.append(state.allocator, state.restart_label.widget());
        if (state.config.sleep_cmd != null) {
            try layer2.append(state.allocator, state.sleep_label.widget());
        }
        if (state.config.hibernate_cmd != null) {
            try layer2.append(state.allocator, state.hibernate_label.widget());
        }
        try layer2.append(state.allocator, state.toggle_password_label.widget());
        if (state.config.brightness_down_key != null) {
            try layer2.append(state.allocator, state.brightness_down_label.widget());
        }
        if (state.config.brightness_up_key != null) {
            try layer2.append(state.allocator, state.brightness_up_label.widget());
        }
    }
    if (state.config.battery_id != null) {
        try layer2.append(state.allocator, state.battery_label.widget());
    }
    if (state.config.clock != null) {
        try layer2.append(state.allocator, state.clock_label.widget());
    }
    if (state.config.show_tty) {
        try layer2.append(state.allocator, state.tty_label.widget());
    }
    if (state.config.bigclock != .none) {
        try layer2.append(state.allocator, state.bigclock_label.widget());
    }
    if (!state.config.hide_keyboard_locks) {
        try layer2.append(state.allocator, state.numlock_label.widget());
        try layer2.append(state.allocator, state.capslock_label.widget());
    }
    try layer2.append(state.allocator, state.box.widget());
    try layer2.append(state.allocator, info_line_widget);
    try layer2.append(state.allocator, state.session_specifier_label.widget());
    try layer2.append(state.allocator, session_widget);
    try layer2.append(state.allocator, state.login_label.widget());
    try layer2.append(state.allocator, login_widget);
    try layer2.append(state.allocator, state.password_label.widget());
    try layer2.append(state.allocator, state.password_widget);
    if (!state.config.hide_version_string) {
        try layer2.append(state.allocator, state.version_label.widget());
    }

    for (state.custom_binds.items) |*item| {
        try layer2.append(state.allocator, item.lbl.widget());
    }
    for (state.custom_info.items) |*item| {
        try layer2.append(state.allocator, item.lbl.widget());
    }

    try widgets.append(state.allocator, layer2.items);

    // Layer 3
    if (state.config.auth_fails > 0) {
        var layer3 = [_]*Widget{cascade.widget()};
        try widgets.append(state.allocator, &layer3);
    }

    for (state.custom_binds.items) |*item| {
        try state.buffer.registerGlobalKeybind(state.io, item.key, &customCommand, item);
    }

    try state.buffer.registerGlobalKeybind(state.io, "Esc", &disableInsertMode, &state);
    try state.buffer.registerGlobalKeybind(state.io, "I", &enableInsertMode, &state);

    try state.buffer.registerGlobalKeybind(state.io, "Ctrl+C", &quit, &state);

    try state.buffer.registerGlobalKeybind(state.io, "K", &viMoveCursorUp, &state);
    try state.buffer.registerGlobalKeybind(state.io, "J", &viMoveCursorDown, &state);

    try state.buffer.registerGlobalKeybind(state.io, "Enter", &authenticate, &state);

    try state.buffer.registerGlobalKeybind(state.io, state.config.shutdown_key, &shutdownCmd, &state);
    try state.buffer.registerGlobalKeybind(state.io, state.config.restart_key, &restartCmd, &state);
    try state.buffer.registerGlobalKeybind(state.io, state.config.show_password_key, &togglePasswordMask, &state);
    if (state.config.sleep_cmd != null) try state.buffer.registerGlobalKeybind(state.io, state.config.sleep_key, &sleepCmd, &state);
    if (state.config.hibernate_cmd != null) try state.buffer.registerGlobalKeybind(state.io, state.config.hibernate_key, &hibernateCmd, &state);
    if (state.config.brightness_down_key) |key| try state.buffer.registerGlobalKeybind(state.io, key, &decreaseBrightnessCmd, &state);
    if (state.config.brightness_up_key) |key| try state.buffer.registerGlobalKeybind(state.io, key, &increaseBrightnessCmd, &state);

    if (state.config.initial_info_text) |text| {
        try state.info_line.addMessage(text, state.config.bg, state.config.fg);
    } else get_host_name: {
        // Initialize information line with host name
        var name_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
        const hostname = std.posix.gethostname(&name_buf) catch |err| {
            try state.info_line.addMessage(
                state.lang.err_hostname,
                state.config.error_bg,
                state.config.error_fg,
            );
            try state.log_file.err(
                state.io,
                "sys",
                "failed to get hostname: {s}",
                .{@errorName(err)},
            );
            break :get_host_name;
        };
        try state.info_line.addMessage(
            hostname,
            state.config.bg,
            state.config.fg,
        );
    }

    if (state.is_autologin) _ = try authenticate(&state);

    const active_widget = switch (default_input) {
        .info_line => info_line_widget,
        .session => session_widget,
        .login => login_widget,
        .password => state.password_widget,
    };

    var shared_error = try SharedError.init(&uiErrorHandler, &state);
    defer shared_error.deinit();

    try state.buffer.runEventLoop(
        state.allocator,
        state.io,
        shared_error,
        widgets.items,
        active_widget,
        state.config.inactivity_delay,
        positionWidgets,
        handleInactivity,
        &state,
    );
}

fn uiErrorHandler(err: anyerror, ctx: *anyopaque) anyerror!void {
    var state: *UiState = @ptrCast(@alignCast(ctx));

    switch (err) {
        error.SetCursorFailed => {
            try state.info_line.addMessage(
                state.lang.err_alloc,
                state.config.error_bg,
                state.config.error_fg,
            );
        },
        error.WidgetReallocationFailed => {
            try state.info_line.addMessage(
                state.lang.err_alloc,
                state.config.error_bg,
                state.config.error_fg,
            );
        },
        error.CurrentWidgetHandlingFailed => {
            try state.info_line.addMessage(
                state.lang.err_alloc,
                state.config.error_bg,
                state.config.error_fg,
            );
        },
        else => unreachable,
    }
}

fn disableInsertMode(ptr: *anyopaque) !bool {
    var state: *UiState = @ptrCast(@alignCast(ptr));

    if (state.config.vi_mode and state.insert_mode) {
        state.insert_mode = false;
        state.password.should_insert = false;
        state.buffer.drawNextFrame(true);
    }
    return false;
}

fn enableInsertMode(ptr: *anyopaque) !bool {
    var state: *UiState = @ptrCast(@alignCast(ptr));
    if (state.insert_mode) return true;

    state.insert_mode = true;
    state.password.should_insert = true;
    state.buffer.drawNextFrame(true);
    return false;
}

fn viGoLeft(ptr: *anyopaque) !bool {
    var state: *UiState = @ptrCast(@alignCast(ptr));
    if (state.insert_mode) return true;

    return try state.buffer.simulateKeybind(state.io, "Left");
}

fn viGoRight(ptr: *anyopaque) !bool {
    var state: *UiState = @ptrCast(@alignCast(ptr));
    if (state.insert_mode) return true;

    return try state.buffer.simulateKeybind(state.io, "Right");
}

fn viMoveCursorUp(ptr: *anyopaque) !bool {
    var state: *UiState = @ptrCast(@alignCast(ptr));
    if (state.insert_mode) return true;

    return try state.buffer.simulateKeybind(state.io, "Up");
}

fn viMoveCursorDown(ptr: *anyopaque) !bool {
    var state: *UiState = @ptrCast(@alignCast(ptr));
    if (state.insert_mode) return true;

    return try state.buffer.simulateKeybind(state.io, "Down");
}

fn togglePasswordMask(ptr: *anyopaque) !bool {
    var state: *UiState = @ptrCast(@alignCast(ptr));

    state.password.toggleMask();
    state.buffer.drawNextFrame(true);
    return false;
}

fn quit(ptr: *anyopaque) !bool {
    var state: *UiState = @ptrCast(@alignCast(ptr));

    state.buffer.stopEventLoop();
    return false;
}

fn customCommand(ptr: *anyopaque) !bool {
    const lbl: *CustomBindLabel = @ptrCast(@alignCast(ptr));
    var proc = std.process.spawn(lbl.io, .{
        .argv = &[_][]const u8{ "/bin/sh", "-c", lbl.cmd.cmd },
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return false;

    const res = proc.wait(lbl.io) catch return false;
    if (res.exited != 0) return error.CommandFailed;
    return false;
}

fn authenticate(ptr: *anyopaque) !bool {
    var state: *UiState = @ptrCast(@alignCast(ptr));

    try state.log_file.info(state.io, "auth", "starting authentication", .{});

    if (!state.config.allow_empty_password and state.password.text.items.len == 0) {
        // Let's not log this message for security reasons
        try state.info_line.addMessage(
            state.lang.err_empty_password,
            state.config.error_bg,
            state.config.error_fg,
        );
        state.info_line.clearRendered(state.allocator) catch |err| {
            try state.info_line.addMessage(
                state.lang.err_alloc,
                state.config.error_bg,
                state.config.error_fg,
            );
            try state.log_file.err(
                state.io,
                "tui",
                "failed to clear info line: {s}",
                .{@errorName(err)},
            );
        };
        state.info_line.label.draw();
        TerminalBuffer.presentBuffer();
        return false;
    }

    try state.info_line.addMessage(
        state.lang.authenticating,
        state.config.bg,
        state.config.fg,
    );
    state.info_line.clearRendered(state.allocator) catch |err| {
        try state.info_line.addMessage(
            state.lang.err_alloc,
            state.config.error_bg,
            state.config.error_fg,
        );
        try state.log_file.err(
            state.io,
            "tui",
            "failed to clear info line: {s}",
            .{@errorName(err)},
        );
    };
    state.info_line.label.draw();
    TerminalBuffer.presentBuffer();

    if (state.config.save) save_last_settings: {
        // It isn't worth cluttering the code with precise error
        // handling, so let's just report a generic error message,
        // that should be good enough for debugging anyway.
        errdefer state.log_file.err(
            state.io,
            "conf",
            "failed to save current user data",
            .{},
        ) catch {};

        var file = std.Io.Dir.cwd().createFile(state.io, state.save_path, .{}) catch |err| {
            state.log_file.err(
                state.io,
                "sys",
                "failed to create save file: {s}",
                .{@errorName(err)},
            ) catch break :save_last_settings;
            break :save_last_settings;
        };
        defer file.close(state.io);

        var file_buffer: [256]u8 = undefined;
        var file_writer = file.writer(state.io, &file_buffer);
        var writer = &file_writer.interface;

        try writer.print("{d}\n", .{state.login.label.current});
        for (state.saved_users.user_list.items) |user| {
            try writer.print("{s}:{d}\n", .{ user.username, user.session_index });
        }
        try writer.flush();

        // Delete previous save file if it exists
        if (migrator.maybe_save_file) |path| {
            std.Io.Dir.cwd().deleteFile(state.io, path) catch {};
        } else if (state.has_old_save) {
            std.Io.Dir.cwd().deleteFile(state.io, state.old_save_path) catch {};
        }
    }

    var shared_err = try SharedError.init(null, null);
    defer shared_err.deinit();

    {
        state.log_file.deinit(state.io);

        session_pid = std.posix.system.fork();
        if (session_pid == 0) {
            const current_environment = state.session.label.list.items[state.session.label.current].environment;

            // Use auto_login_service for autologin, otherwise use configured service
            const service_name = if (state.is_autologin) state.config.auto_login_service else state.config.service_name;
            const password_text = if (state.is_autologin) "" else state.password.text.items;

            const auth_options = auth.AuthOptions{
                .tty = state.active_tty,
                .service_name = service_name,
                .path = state.config.path,
                .session_log = state.config.session_log,
                .xauth_cmd = state.config.xauth_cmd,
                .setup_cmd = state.config.setup_cmd,
                .login_cmd = state.config.login_cmd,
                .x_cmd = state.config.x_cmd,
                .x_vt = state.config.x_vt,
                .session_pid = session_pid,
                .use_kmscon_vt = state.use_kmscon_vt,
            };

            // Signal action to give up control on the TTY
            const tty_control_transfer_act = std.posix.Sigaction{
                .handler = .{ .handler = &ttyControlTransferSignalHandler },
                .mask = std.posix.sigemptyset(),
                .flags = 0,
            };
            std.posix.sigaction(std.posix.SIG.INT, &tty_control_transfer_act, null);

            try state.log_file.reinit(state.io);

            auth.authenticate(
                state.allocator,
                state.io,
                &state.log_file,
                auth_options,
                current_environment,
                state.login.getCurrentUsername(),
                password_text,
            ) catch |err| {
                shared_err.writeError(err);

                state.log_file.deinit(state.io);
                std.process.exit(1);
            };

            state.log_file.deinit(state.io);
            std.process.exit(0);
        }

        var session_status: c_int = undefined;
        _ = std.posix.system.waitpid(session_pid, &session_status, 0);
        // HACK: It seems like the session process is not exiting immediately after the waitpid call.
        // This is a workaround to ensure the session process has exited before re-initializing the TTY.
        state.io.sleep(.fromSeconds(1), .real) catch {};
        session_pid = -1;

        try state.log_file.reinit(state.io);
    }

    try state.buffer.reclaim();

    const auth_err = shared_err.readError();
    if (auth_err) |err| {
        state.auth_fails += 1;
        state.buffer.setActiveWidget(state.password_widget);

        try state.info_line.addMessage(
            getAuthErrorMsg(err, state.lang),
            state.config.error_bg,
            state.config.error_fg,
        );
        try state.log_file.err(
            state.io,
            "auth",
            "failed to authenticate: {s}",
            .{@errorName(err)},
        );

        if (state.config.clear_password or err != error.PamAuthError) state.password.clear();
    } else {
        if (state.config.logout_cmd) |logout_cmd| execute_cmd: {
            var process = std.process.spawn(state.io, .{
                .argv = &[_][]const u8{ "/bin/sh", "-c", logout_cmd },
            }) catch break :execute_cmd;
            _ = process.wait(state.io) catch {};
        }

        state.password.clear();
        state.is_autologin = false;
        try state.info_line.addMessage(
            state.lang.logout,
            state.config.bg,
            state.config.fg,
        );
        try state.log_file.info(state.io, "auth", "logged out", .{});
    }

    if (state.config.auth_fails == 0 or state.auth_fails < state.config.auth_fails) {
        try TerminalBuffer.clearScreen(true);
        state.buffer.drawNextFrame(true);
    }

    // Restore the cursor
    TerminalBuffer.setCursor(0, 0);
    TerminalBuffer.presentBuffer();
    return false;
}

fn shutdownCmd(ptr: *anyopaque) !bool {
    var state: *UiState = @ptrCast(@alignCast(ptr));

    shutdown = true;
    state.buffer.stopEventLoop();
    return false;
}

fn restartCmd(ptr: *anyopaque) !bool {
    var state: *UiState = @ptrCast(@alignCast(ptr));

    restart = true;
    state.buffer.stopEventLoop();
    return false;
}

fn sleepCmd(ptr: *anyopaque) !bool {
    var state: *UiState = @ptrCast(@alignCast(ptr));

    if (state.config.sleep_cmd) |sleep_cmd| {
        var process = std.process.spawn(state.io, .{
            .argv = &[_][]const u8{ "/bin/sh", "-c", sleep_cmd },
            .stdout = .ignore,
            .stderr = .ignore,
        }) catch return false;

        const process_result = process.wait(state.io) catch return false;
        if (process_result.exited != 0) {
            try state.info_line.addMessage(
                state.lang.err_sleep,
                state.config.error_bg,
                state.config.error_fg,
            );
            try state.log_file.err(
                state.io,
                "sys",
                "failed to execute sleep command: exit code {d}",
                .{process_result.exited},
            );
        }
    }
    return false;
}

fn hibernateCmd(ptr: *anyopaque) !bool {
    var state: *UiState = @ptrCast(@alignCast(ptr));

    if (state.config.hibernate_cmd) |hibernate_cmd| {
        var process = std.process.spawn(state.io, .{
            .argv = &[_][]const u8{ "/bin/sh", "-c", hibernate_cmd },
            .stdout = .ignore,
            .stderr = .ignore,
        }) catch return false;

        const process_result = process.wait(state.io) catch return false;
        if (process_result.exited != 0) {
            try state.info_line.addMessage(
                state.lang.err_hibernate,
                state.config.error_bg,
                state.config.error_fg,
            );
            try state.log_file.err(
                state.io,
                "sys",
                "failed to execute hibernate command: exit code {d}",
                .{process_result.exited},
            );
        }
    }
    return false;
}

fn decreaseBrightnessCmd(ptr: *anyopaque) !bool {
    var state: *UiState = @ptrCast(@alignCast(ptr));

    adjustBrightness(state.io, state.config.brightness_down_cmd) catch |err| {
        try state.info_line.addMessage(
            state.lang.err_brightness_change,
            state.config.error_bg,
            state.config.error_fg,
        );
        try state.log_file.err(
            state.io,
            "sys",
            "failed to decrease brightness: {s}",
            .{@errorName(err)},
        );
    };
    return false;
}

fn increaseBrightnessCmd(ptr: *anyopaque) !bool {
    var state: *UiState = @ptrCast(@alignCast(ptr));

    adjustBrightness(state.io, state.config.brightness_up_cmd) catch |err| {
        try state.info_line.addMessage(
            state.lang.err_brightness_change,
            state.config.error_bg,
            state.config.error_fg,
        );
        try state.log_file.err(
            state.io,
            "sys",
            "failed to increase brightness: {s}",
            .{@errorName(err)},
        );
    };
    return false;
}

fn updateNumlock(self: *Label, ptr: *anyopaque) !void {
    var state: *UiState = @ptrCast(@alignCast(ptr));

    const lock_state = interop.getLockState() catch |err| {
        self.update_fn = null;
        try state.info_line.addMessage(
            state.lang.err_lock_state,
            state.config.error_bg,
            state.config.error_fg,
        );
        try state.log_file.err(
            state.io,
            "sys",
            "failed to get lock state: {s}",
            .{@errorName(err)},
        );
        return;
    };

    self.setText(if (lock_state.numlock) state.lang.numlock else "");
}

fn updateCapslock(self: *Label, ptr: *anyopaque) !void {
    var state: *UiState = @ptrCast(@alignCast(ptr));

    const lock_state = interop.getLockState() catch |err| {
        self.update_fn = null;
        try state.info_line.addMessage(state.lang.err_lock_state, state.config.error_bg, state.config.error_fg);
        try state.log_file.err(state.io, "sys", "failed to get lock state: {s}", .{@errorName(err)});
        return;
    };

    self.setText(if (lock_state.capslock) state.lang.capslock else "");
}

fn updateBattery(self: *Label, ptr: *anyopaque) !void {
    var state: *UiState = @ptrCast(@alignCast(ptr));

    if (state.config.battery_id) |id| {
        const battery_percentage = getBatteryPercentage(state.io, id) catch |err| {
            self.update_fn = null;
            try state.log_file.err(
                state.io,
                "sys",
                "failed to get battery percentage: {s}",
                .{@errorName(err)},
            );
            try state.info_line.addMessage(
                state.lang.err_battery,
                state.config.error_bg,
                state.config.error_fg,
            );
            return;
        };

        try self.setTextBuf(
            &state.battery_buf,
            "BAT: {d}%",
            .{battery_percentage},
        );
    }
}

fn updateClock(self: *Label, ptr: *anyopaque) !void {
    var state: *UiState = @ptrCast(@alignCast(ptr));

    if (state.config.clock) |clock| draw_clock: {
        const clock_str = interop.timeAsString(state.io, &state.clock_buf, clock);

        if (clock_str.len == 0) {
            self.update_fn = null;
            try state.info_line.addMessage(
                state.lang.err_clock_too_long,
                state.config.error_bg,
                state.config.error_fg,
            );
            try state.log_file.err(
                state.io,
                "tui",
                "clock string too long",
                .{},
            );
            break :draw_clock;
        }

        self.setText(clock_str);
    }
}

fn updateCustomInfo(lbl: *Label, ptr: *anyopaque) !void {
    const state: *UiState = @ptrCast(@alignCast(ptr));
    const wid = lbl.widget().id;

    for (state.custom_info.items) |*i| {
        if (i.info.id != wid) continue;
        // Here, a counter ticks down every time `updateCustomInfo` runs on that
        // particular label. It will only run the command and update the label
        // once it reaches to 1. If a refresh value is defined it's then reset to
        // that refresh value.
        if (i.info.counter == 1) {
            var c = try std.process.spawn(state.io, .{
                .argv = &[_][]const u8{ "/bin/sh", "-c", i.info.cmd orelse custom.UNDEFINED_CMD },
                .stdout = .pipe,
                .stderr = .pipe,
            });

            var stdout_buffer: [1024]u8 = undefined;
            var stdout_file_reader = c.stdout.?.reader(state.io, &stdout_buffer);

            const stdout = stdout_file_reader.interface.allocRemaining(state.allocator, .limited(state.buffer.width)) catch alloc_error: {
                break :alloc_error try std.fmt.allocPrint(state.allocator, "{s}: [{s}]", .{ i.info.name, state.lang.custom_info_err_output_long });
            };
            defer state.allocator.free(stdout);

            var cur_stdout = stdout;
            const newline_index = std.mem.indexOfAny(u8, stdout, "\n");
            if (newline_index) |idx| cur_stdout = stdout[0..idx];

            _ = try c.wait(state.io);

            // Sometimes, the output of a command would have an unprintable character at
            // the end of its output, causing '�' (U+FFFD) to appear in its place. Here, we check
            // if this is the case and remove it.
            if (cur_stdout.len != 0 and !std.ascii.isPrint(cur_stdout[cur_stdout.len - 1])) {
                cur_stdout = cur_stdout[0 .. cur_stdout.len - 1];
            }

            state.allocator.free(lbl.text);
            if (cur_stdout.len == 0) {
                const stderr_length = try c.stderr.?.length(state.io);
                try lbl.setTextAlloc(state.allocator, "{s}: [{s}{s}]", .{ i.info.name, state.lang.custom_info_err_no_output, if (stderr_length > 0) state.lang.custom_info_err_no_output_error else "" });
            } else {
                try lbl.setTextAlloc(state.allocator, "{s}", .{cur_stdout});
            }

            // Called to re-position the widgets after they receive their output.
            try positionWidgets(state);
            if (i.info.refresh != 0)
                i.info.counter = i.info.refresh;
        }
        if (i.info.counter != 0)
            i.info.counter -= 1;
    }
}

fn calculateClockTimeout(_: *Label, _: *anyopaque) !?usize {
    const time = try interop.getTimeOfDay();

    return @intCast(1000 - @divTrunc(time.microseconds, 1000) + 1);
}

fn updateBigClock(self: *BigLabel, ptr: *anyopaque) !void {
    var state: *UiState = @ptrCast(@alignCast(ptr));

    if (state.box.height + (BigLabel.CHAR_HEIGHT + 2) * 2 >= state.buffer.height) return;

    const time = try interop.getTimeOfDay();
    const animate_time = @divTrunc(time.microseconds, 500_000);
    const separator = if (state.animate and animate_time != 0) " " else ":";
    const format = try std.fmt.bufPrintZ(
        &state.bigclock_format_buf,
        "{s}{s}{s}{s}{s}{s}",
        .{
            if (state.config.bigclock_12hr) "%I" else "%H",
            separator,
            "%M",
            if (state.config.bigclock_seconds) separator else "",
            if (state.config.bigclock_seconds) "%S" else "",
            if (state.config.bigclock_12hr) "%P" else "",
        },
    );

    const clock_str = interop.timeAsString(state.io, &state.bigclock_buf, format);
    self.setText(clock_str);
}

fn calculateBigClockTimeout(_: *BigLabel, ptr: *anyopaque) !?usize {
    const state: *UiState = @ptrCast(@alignCast(ptr));
    const time = try interop.getTimeOfDay();

    if (state.config.bigclock_seconds) {
        return @intCast(1000 - @divTrunc(time.microseconds, 1000) + 1);
    }

    return @intCast((60 - @rem(time.seconds, 60)) * 1000 - @divTrunc(time.microseconds, 1000) + 1);
}

fn updateBox(self: *Box, ptr: *anyopaque) !void {
    const state: *UiState = @ptrCast(@alignCast(ptr));

    if (state.config.vi_mode) {
        self.bottom_title = if (state.insert_mode) state.lang.insert else state.lang.normal;
    }
}

fn updateSessionSpecifier(self: *Label, ptr: *anyopaque) !void {
    const state: *UiState = @ptrCast(@alignCast(ptr));

    const env = state.session.label.list.items[state.session.label.current];
    self.setText(env.environment.specifier);
}

fn positionWidgets(ptr: *anyopaque) !void {
    var state: *UiState = @ptrCast(@alignCast(ptr));

    // Offsets for custom bind placement. Declared here instead of the
    // below if stmt as we need these for `battery_label` positioning.
    var x_offset: usize = 0;
    // To account for the first row of built-in key hints
    var y_offset: usize = 1;
    if (!state.config.hide_key_hints) {
        state.shutdown_label.positionX(state.edge_margin
            .add(TerminalBuffer.START_POSITION));
        var last_label = state.shutdown_label;
        state.restart_label.positionX(last_label
            .childrenPosition()
            .addX(1));
        last_label = state.restart_label;
        state.sleep_label.positionX(last_label
            .childrenPosition()
            .addX(1));
        if (state.config.sleep_cmd != null) {
            last_label = state.sleep_label;
        }
        state.hibernate_label.positionX(last_label
            .childrenPosition()
            .addX(1));
        if (state.config.hibernate_cmd != null) {
            last_label = state.hibernate_label;
        }
        state.toggle_password_label.positionX(last_label
            .childrenPosition()
            .addX(1));
        last_label = state.toggle_password_label;
        state.brightness_down_label.positionX(last_label
            .childrenPosition()
            .addX(1));
        if (state.config.brightness_down_key != null) {
            last_label = state.brightness_down_label;
        }
        state.brightness_up_label.positionXY(last_label
            .childrenPosition()
            .addX(1));
        for (state.custom_binds.items) |*item| {
            item.lbl.positionXY(state.edge_margin
                .addY(y_offset)
                .addX(x_offset));
            x_offset += item.lbl.text.len + 1;
            if (x_offset + item.lbl.text.len > state.config.custom_bind_width orelse state.buffer.width) {
                x_offset = 0;
                y_offset += 1;
            }
        }
    }
    for (state.custom_info.items, 0..) |*item, i| {
        item.lbl.positionXY(state.edge_margin
            .invertX(state.buffer.width)
            .removeX(item.lbl.text.len)
            .invertY(state.buffer.height)
            .removeY(state.custom_info.items.len)
            .addY(i));
    }

    state.battery_label.positionXY(state.edge_margin
        .add(TerminalBuffer.START_POSITION)
        .addYFromIf(state.brightness_up_label.childrenPosition(), !state.config.hide_key_hints)
        .addYIf(y_offset, !state.config.hide_key_hints)
        .removeYFromIf(state.edge_margin, !state.config.hide_key_hints));

    const tty_label_width = if (state.config.show_tty) TerminalBuffer.strWidth(state.tty_label.text) else 0;
    const tty_label_gap = if (state.config.show_tty and state.config.clock != null) @as(usize, 1) else 0;
    state.tty_label.positionXY(state.edge_margin
        .add(TerminalBuffer.START_POSITION)
        .invertX(state.buffer.width)
        .removeXIf(tty_label_width, state.buffer.width > tty_label_width + state.edge_margin.x));
    state.clock_label.positionXY(state.edge_margin
        .add(TerminalBuffer.START_POSITION)
        .invertX(state.buffer.width)
        .removeXIf(TerminalBuffer.strWidth(state.clock_label.text) + tty_label_width + tty_label_gap, state.buffer.width > TerminalBuffer.strWidth(state.clock_label.text) + tty_label_width + tty_label_gap + state.edge_margin.x));

    state.numlock_label.positionX(state.edge_margin
        .add(TerminalBuffer.START_POSITION)
        .addYFromIf(state.clock_label.childrenPosition(), state.config.clock != null)
        .removeYFromIf(state.edge_margin, state.config.clock != null)
        .invertX(state.buffer.width)
        .removeXIf(TerminalBuffer.strWidth(state.lang.numlock), state.buffer.width > TerminalBuffer.strWidth(state.lang.numlock) + state.edge_margin.x));
    state.capslock_label.positionX(state.numlock_label
        .childrenPosition()
        .removeX(TerminalBuffer.strWidth(state.lang.numlock) + TerminalBuffer.strWidth(state.lang.capslock) + 1));

    state.box.positionXY(TerminalBuffer.START_POSITION
        .addX((state.buffer.width - @min(state.buffer.width - 2, state.box.width)) / 2)
        .addY((state.buffer.height - @min(state.buffer.height - 2, state.box.height)) / 2));

    if (state.config.bigclock != .none) {
        const half_width = state.buffer.width / 2;
        const half_label_width = (TerminalBuffer.strWidth(state.bigclock_label.text) * (BigLabel.CHAR_WIDTH + 1)) / 2;
        const half_height = (if (state.buffer.height > state.box.height) state.buffer.height - state.box.height else state.buffer.height) / 2;

        state.bigclock_label.positionXY(TerminalBuffer.START_POSITION
            .addX(half_width)
            .removeXIf(half_label_width, half_width > half_label_width)
            .addY(half_height)
            .removeYIf(BigLabel.CHAR_HEIGHT + 2, half_height > BigLabel.CHAR_HEIGHT + 2));
    }

    state.info_line.label.positionY(state.box
        .childrenPosition());

    state.session_specifier_label.positionX(state.info_line.label
        .childrenPosition()
        .addY(1));
    state.session.label.positionY(state.session_specifier_label
        .childrenPosition()
        .addX(state.labels_max_length - TerminalBuffer.strWidth(state.session_specifier_label.text) + 1));

    state.login_label.positionX(state.session.label
        .childrenPosition()
        .resetXFrom(state.info_line.label.childrenPosition())
        .addY(1));
    state.login.label.positionY(state.login_label
        .childrenPosition()
        .addX(state.labels_max_length - TerminalBuffer.strWidth(state.login_label.text) + 1));

    state.password_label.positionX(state.login.label
        .childrenPosition()
        .resetXFrom(state.info_line.label.childrenPosition())
        .addY(1));
    state.password.positionY(state.password_label
        .childrenPosition()
        .addX(state.labels_max_length - TerminalBuffer.strWidth(state.password_label.text) + 1));

    state.version_label.positionXY(state.edge_margin
        .add(TerminalBuffer.START_POSITION)
        .invertY(state.buffer.height - 1));
}

fn handleInactivity(ptr: *anyopaque) !void {
    var state: *UiState = @ptrCast(@alignCast(ptr));

    if (state.config.inactivity_cmd) |inactivity_cmd| handle_inactivity_cmd: {
        var process = std.process.spawn(state.io, .{
            .argv = &[_][]const u8{ "/bin/sh", "-c", inactivity_cmd },
            .stdout = .ignore,
            .stderr = .ignore,
        }) catch break :handle_inactivity_cmd;

        const process_result = process.wait(state.io) catch {
            break :handle_inactivity_cmd;
        };
        if (process_result.exited != 0) {
            try state.info_line.addMessage(
                state.lang.err_inactivity,
                state.config.error_bg,
                state.config.error_fg,
            );
            try state.log_file.err(
                state.io,
                "sys",
                "failed to execute inactivity command: exit code {d}",
                .{process_result.exited},
            );
        }
    }
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

fn crawl(session: *Session, io: std.Io, lang: Lang, path: []const u8, display_server: DisplayServer) !void {
    if (!std.Io.Dir.path.isAbsolute(path)) return error.PathNotAbsolute;

    var iterable_directory = try std.Io.Dir.openDirAbsolute(io, path, .{ .iterate = true });
    defer iterable_directory.close(io);

    var iterator = iterable_directory.iterate();
    while (try iterator.next(io)) |item| {
        if (!std.mem.eql(u8, std.Io.Dir.path.extension(item.name), ".desktop")) continue;

        const entry_path = try std.fmt.allocPrint(session.label.allocator, "{s}/{s}", .{ path, item.name });
        defer session.label.allocator.free(entry_path);
        var entry_ini = Ini(Entry).init(session.label.allocator);
        const data = try entry_ini.readFileToStruct(io, entry_path, .{
            .fieldHandler = null,
            .comment_characters = "#",
        });
        errdefer entry_ini.deinit();

        const file_name = try session.label.allocator.dupe(u8, std.Io.Dir.path.stem(item.name));
        const entry = data.@"Desktop Entry";
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

fn getAllUsernames(allocator: Allocator, io: std.Io, login_defs_path: []const u8, uid_range_error: *?anyerror) !StringList {
    const uid_range = interop.getUserIdRange(allocator, io, login_defs_path) catch |err| no_uid_range: {
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

fn adjustBrightness(io: std.Io, cmd: []const u8) !void {
    var process = std.process.spawn(io, .{
        .argv = &[_][]const u8{ "/bin/sh", "-c", cmd },
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return;

    const process_result = process.wait(io) catch return;
    if (process_result.exited != 0) {
        return error.BrightnessChangeFailed;
    }
}

fn getBatteryPercentage(io: std.Io, battery_id: []const u8) !u8 {
    const path = try std.fmt.allocPrint(temporary_allocator, "/sys/class/power_supply/{s}/capacity", .{battery_id});
    defer temporary_allocator.free(path);

    const battery_file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer battery_file.close(io);

    var buffer: [8]u8 = undefined;
    const bytes_read = try battery_file.readStreaming(io, &.{&buffer});
    const capacity_str = buffer[0..bytes_read];

    const trimmed = std.mem.trimEnd(u8, capacity_str, "\n\r");

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
