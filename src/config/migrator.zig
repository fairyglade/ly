// The migrator ensures compatibility with <=0.6.0 configuration files

const std = @import("std");
const ini = @import("zigini");
const Save = @import("Save.zig");
const enums = @import("../enums.zig");

var temporary_allocator = std.heap.page_allocator;

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

    if (std.mem.eql(u8, field.key, "wayland_specifier") or
        std.mem.eql(u8, field.key, "max_desktop_len") or
        std.mem.eql(u8, field.key, "max_login_len") or
        std.mem.eql(u8, field.key, "max_password_len") or
        std.mem.eql(u8, field.key, "mcookie_cmd") or
        std.mem.eql(u8, field.key, "term_reset_cmd") or
        std.mem.eql(u8, field.key, "term_restore_cursor_cmd") or
        std.mem.eql(u8, field.key, "x_cmd_setup") or
        std.mem.eql(u8, field.key, "wayland_cmd"))
    {
        // The options don't exist anymore
        mapped_config_fields = true;
        return null;
    }

    if (std.mem.eql(u8, field.key, "bigclock")) {
        // The option now uses a string (which then gets converted into an enum) instead of an boolean
        // It also includes the ability to change active bigclock's language
        var mapped_field = field;

        if (std.mem.eql(u8, field.value, "true")){
            mapped_field.value = "en";
            mapped_config_fields = true;
        }else if (std.mem.eql(u8, field.value, "false")){
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
