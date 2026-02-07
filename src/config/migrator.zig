// The migrator ensures compatibility with older configuration files
// Properties removed or changed since 0.6.0
// Color codes interpreted differently since 1.1.0

const std = @import("std");
var temporary_allocator = std.heap.page_allocator;

const ini = @import("zigini");
const ly_core = @import("ly-core");
const IniParser = ly_core.IniParser;

const TerminalBuffer = @import("../tui/TerminalBuffer.zig");
const Color = TerminalBuffer.Color;
const Styling = TerminalBuffer.Styling;
const Config = @import("Config.zig");
const OldSave = @import("OldSave.zig");
const SavedUsers = @import("SavedUsers.zig");

const color_properties = [_][]const u8{
    "bg",
    "border_fg",
    "cmatrix_fg",
    "colormix_col1",
    "colormix_col2",
    "colormix_col3",
    "error_bg",
    "error_fg",
    "fg",
};

var set_color_properties =
    [_]bool{ false, false, false, false, false, false, false, false, false };

const removed_properties = [_][]const u8{
    "wayland_specifier",
    "max_desktop_len",
    "max_login_len",
    "max_password_len",
    "mcookie_cmd",
    "term_reset_cmd",
    "term_restore_cursor_cmd",
    "x_cmd_setup",
    "wayland_cmd",
    "console_dev",
    "load",
};

pub var auto_eight_colors: bool = true;

pub var maybe_animate: ?bool = null;
pub var maybe_save_file: ?[]const u8 = null;

pub fn configFieldHandler(_: std.mem.Allocator, field: ini.IniField) ?ini.IniField {
    if (std.mem.eql(u8, field.key, "animate")) {
        // The option doesn't exist anymore, but we save its value for "animation"
        maybe_animate = std.mem.eql(u8, field.value, "true");

        return null;
    }

    if (std.mem.eql(u8, field.key, "animation")) {
        // The option now uses a string (which then gets converted into an enum) instead of an integer
        // It also combines the previous "animate" and "animation" options
        const animation = std.fmt.parseInt(u8, field.value, 10) catch return field;
        var mapped_field = field;

        mapped_field.value = switch (animation) {
            0 => "doom",
            1 => "matrix",
            else => "none",
        };

        return mapped_field;
    }

    inline for (color_properties, &set_color_properties) |property, *status| {
        if (std.mem.eql(u8, field.key, property)) {
            // Color has been set; it won't be overwritten if we default to eight-color output
            status.* = true;

            // These options now uses a 32-bit RGB value instead of an arbitrary 16-bit integer
            // If they're all using eight-color codes, we start in eight-color mode
            const color = std.fmt.parseInt(u16, field.value, 0) catch {
                auto_eight_colors = false;
                return field;
            };

            const color_no_styling = color & 0x00FF;
            const styling_only = color & 0xFF00;

            // If color is "greater" than TB_WHITE, or the styling is "greater" than TB_DIM,
            // we have an invalid color, so do not use eight-color mode
            if (color_no_styling > 0x0008 or styling_only > 0x8000) auto_eight_colors = false;

            return field;
        }
    }

    if (std.mem.eql(u8, field.key, "blank_password")) {
        // The option has simply been renamed
        var mapped_field = field;
        mapped_field.key = "clear_password";

        return mapped_field;
    }

    if (std.mem.eql(u8, field.key, "default_input")) {
        // The option now uses a string (which then gets converted into an enum) instead of an integer
        const default_input = std.fmt.parseInt(u8, field.value, 10) catch return field;
        var mapped_field = field;

        mapped_field.value = switch (default_input) {
            0 => "session",
            1 => "login",
            2 => "password",
            else => "login",
        };

        return mapped_field;
    }

    if (std.mem.eql(u8, field.key, "save_file")) {
        // The option doesn't exist anymore, but we save its value for migration later on
        maybe_save_file = temporary_allocator.dupe(u8, field.value) catch return null;

        return null;
    }

    inline for (removed_properties) |property| {
        if (std.mem.eql(u8, field.key, property)) {
            // The options don't exist anymore
            return null;
        }
    }

    if (std.mem.eql(u8, field.key, "bigclock")) {
        // The option now uses a string (which then gets converted into an enum) instead of an boolean
        // It also includes the ability to change active bigclock's language
        var mapped_field = field;

        if (std.mem.eql(u8, field.value, "true")) {
            mapped_field.value = "en";
        } else if (std.mem.eql(u8, field.value, "false")) {
            mapped_field.value = "none";
        }

        return mapped_field;
    }

    if (std.mem.eql(u8, field.key, "full_color")) {
        // If color mode is defined, definitely don't set it automatically
        auto_eight_colors = false;
        return field;
    }

    return field;
}

// This is the stuff we only handle after reading the config.
// For example, the "animate" field could come after "animation"
pub fn lateConfigFieldHandler(config: *Config) void {
    if (maybe_animate) |animate| {
        if (!animate) config.*.animation = .none;
    }

    if (auto_eight_colors) {
        // Valid config file predates true-color mode
        // Will use eight-color output instead
        config.full_color = false;

        // We cannot rely on Config defaults when in eight-color mode,
        // because they will appear as undesired colors.
        // Instead set color properties to matching eight-color codes
        config.doom_top_color = Color.ECOL_RED;
        config.doom_middle_color = Color.ECOL_YELLOW;
        config.doom_bottom_color = Color.ECOL_WHITE;
        config.cmatrix_head_col = Styling.BOLD | Color.ECOL_WHITE;

        // These may be in the config, so only change those which were not set
        if (!set_color_properties[0]) config.bg = Color.DEFAULT;
        if (!set_color_properties[1]) config.border_fg = Color.ECOL_WHITE;
        if (!set_color_properties[2]) config.cmatrix_fg = Color.ECOL_GREEN;
        if (!set_color_properties[3]) config.colormix_col1 = Color.ECOL_RED;
        if (!set_color_properties[4]) config.colormix_col2 = Color.ECOL_BLUE;
        if (!set_color_properties[5]) config.colormix_col3 = Color.ECOL_BLACK;
        if (!set_color_properties[6]) config.error_bg = Color.DEFAULT;
        if (!set_color_properties[7]) config.error_fg = Styling.BOLD | Color.ECOL_RED;
        if (!set_color_properties[8]) config.fg = Color.ECOL_WHITE;
    }
}

pub fn tryMigrateIniSaveFile(allocator: std.mem.Allocator, path: []const u8, saved_users: *SavedUsers, usernames: [][]const u8) !?IniParser(OldSave) {
    var save_parser = try IniParser(OldSave).init(allocator, path, null);
    errdefer save_parser.deinit();

    var user_buf: [32]u8 = undefined;
    const maybe_save = if (save_parser.maybe_load_error == null) save_parser.structure else tryMigrateFirstSaveFile(&user_buf);

    if (maybe_save) |save| {
        // Add all other users to the list
        for (usernames, 0..) |username, i| {
            if (save.user) |user| {
                if (std.mem.eql(u8, user, username)) saved_users.last_username_index = i;
            }

            try saved_users.user_list.append(allocator, .{
                .username = username,
                .session_index = save.session_index orelse 0,
                .first_run = false,
                .allocated_username = false,
            });
        }

        return save_parser;
    }

    return null;
}

fn tryMigrateFirstSaveFile(user_buf: *[32]u8) ?OldSave {
    if (maybe_save_file) |path| {
        defer temporary_allocator.free(path);

        var save = OldSave{};
        var file = std.fs.openFileAbsolute(path, .{}) catch return null;
        defer file.close();

        var file_buffer: [64]u8 = undefined;
        var file_reader = file.reader(&file_buffer);
        var reader = &file_reader.interface;

        var user_writer = std.Io.Writer.fixed(user_buf);
        var written = reader.streamDelimiter(&user_writer, '\n') catch return null;
        if (written > 0) save.user = user_buf[0..written];

        var session_buf: [20]u8 = undefined;
        var session_writer = std.Io.Writer.fixed(&session_buf);
        written = reader.streamDelimiter(&session_writer, '\n') catch return null;

        var session_index: ?usize = null;
        if (written > 0) {
            session_index = std.fmt.parseUnsigned(usize, session_buf[0..written], 10) catch return null;
        }
        save.session_index = session_index;

        return save;
    }

    return null;
}
