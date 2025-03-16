// The migrator ensures compatibility with <=0.6.0 configuration files

const std = @import("std");
const ini = @import("zigini");
const Save = @import("Save.zig");
const enums = @import("../enums.zig");

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
};

var temporary_allocator = std.heap.page_allocator;
var buffer = std.mem.zeroes([10 * color_properties.len]u8);

pub var maybe_animate: ?bool = null;
pub var maybe_save_file: ?[]const u8 = null;

pub var mapped_config_fields = false;

pub fn configFieldHandler(_: std.mem.Allocator, field: ini.IniField) ?ini.IniField {
    if (std.mem.eql(u8, field.key, "animate")) {
        // The option doesn't exist anymore, but we save its value for "animation"
        maybe_animate = std.mem.eql(u8, field.value, "true");

        mapped_config_fields = true;
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

        mapped_config_fields = true;
        return mapped_field;
    }

    inline for (color_properties) |property| {
        if (std.mem.eql(u8, field.key, property)) {
            // These options now uses a 32-bit RGB value instead of an arbitrary 16-bit integer
            const color = std.fmt.parseInt(u16, field.value, 0) catch return field;
            var mapped_field = field;

            mapped_field.value = mapColor(color) catch return field;
            mapped_config_fields = true;
            return mapped_field;
        }
    }

    if (std.mem.eql(u8, field.key, "blank_password")) {
        // The option has simply been renamed
        var mapped_field = field;
        mapped_field.key = "clear_password";

        mapped_config_fields = true;
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

        mapped_config_fields = true;
        return mapped_field;
    }

    if (std.mem.eql(u8, field.key, "save_file")) {
        // The option doesn't exist anymore, but we save its value for migration later on
        maybe_save_file = temporary_allocator.dupe(u8, field.value) catch return null;

        mapped_config_fields = true;
        return null;
    }

    inline for (removed_properties) |property| {
        if (std.mem.eql(u8, field.key, property)) {
            // The options don't exist anymore
            mapped_config_fields = true;
            return null;
        }
    }

    if (std.mem.eql(u8, field.key, "bigclock")) {
        // The option now uses a string (which then gets converted into an enum) instead of an boolean
        // It also includes the ability to change active bigclock's language
        var mapped_field = field;

        if (std.mem.eql(u8, field.value, "true")) {
            mapped_field.value = "en";
            mapped_config_fields = true;
        } else if (std.mem.eql(u8, field.value, "false")) {
            mapped_field.value = "none";
            mapped_config_fields = true;
        }

        return mapped_field;
    }

    return field;
}

// This is the stuff we only handle after reading the config.
// For example, the "animate" field could come after "animation"
pub fn lateConfigFieldHandler(animation: *enums.Animation) void {
    if (maybe_animate) |animate| {
        if (!animate) animation.* = .none;
    }
}

pub fn tryMigrateSaveFile(user_buf: *[32]u8) Save {
    var save = Save{};

    if (maybe_save_file) |path| {
        defer temporary_allocator.free(path);

        var file = std.fs.openFileAbsolute(path, .{}) catch return save;
        defer file.close();

        const reader = file.reader();

        var user_fbs = std.io.fixedBufferStream(user_buf);
        reader.streamUntilDelimiter(user_fbs.writer(), '\n', user_buf.len) catch return save;
        const user = user_fbs.getWritten();
        if (user.len > 0) save.user = user;

        var session_buf: [20]u8 = undefined;
        var session_fbs = std.io.fixedBufferStream(&session_buf);
        reader.streamUntilDelimiter(session_fbs.writer(), '\n', session_buf.len) catch return save;

        const session_index_str = session_fbs.getWritten();
        var session_index: ?usize = null;
        if (session_index_str.len > 0) {
            session_index = std.fmt.parseUnsigned(usize, session_index_str, 10) catch return save;
        }
        save.session_index = session_index;
    }

    return save;
}

fn mapColor(color: u16) ![]const u8 {
    const color_no_styling = color & 0x00FF;
    const styling_only = color & 0xFF00;

    // If color is "greater" than TB_WHITE, or the styling is "greater" than TB_DIM,
    // we have an invalid color, so return an error
    if (color_no_styling > 0x0008 or styling_only > 0x8000) return error.InvalidColor;

    var new_color: u32 = switch (color_no_styling) {
        0x0000 => 0x00000000, // Default
        0x0001 => 0x20000000, // "Hi-black" styling
        0x0002 => 0x00FF0000, // Red
        0x0003 => 0x0000FF00, // Green
        0x0004 => 0x00FFFF00, // Yellow
        0x0005 => 0x000000FF, // Blue
        0x0006 => 0x00FF00FF, // Magenta
        0x0007 => 0x0000FFFF, // Cyan
        0x0008 => 0x00FFFFFF, // White
        else => unreachable,
    };

    // Only applying styling if color isn't black and styling isn't also black
    if (!(new_color == 0x20000000 and styling_only == 0x20000000)) {
        // Shift styling by 16 to the left to apply it to the new 32-bit color
        new_color |= @as(u32, @intCast(styling_only)) << 16;
    }

    return try std.fmt.bufPrint(&buffer, "0x{X}", .{new_color});
}
