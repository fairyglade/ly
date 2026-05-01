const std = @import("std");
const interop = @import("interop.zig");

const LogFile = @This();

maybe_path: ?[]const u8,
could_open_log_file: bool = undefined,
maybe_file: ?std.Io.File = null,
buffer: []u8,
maybe_file_writer: ?std.Io.File.Writer = null,

pub fn init(io: std.Io, path: ?[]const u8, buffer: []u8) !LogFile {
    var log_file = LogFile{
        .maybe_path = path,
        .buffer = buffer,
    };

    if (path) |p| {
        log_file.could_open_log_file = try openLogFile(io, p, &log_file);
    } else {
        std.posix.system.openlog("ly", 0, 0);
        log_file.could_open_log_file = true;
    }

    return log_file;
}

pub fn reinit(self: *LogFile, io: std.Io) !void {
    if (self.maybe_path) |path| {
        self.could_open_log_file = try openLogFile(io, path, self);
    } else {
        std.posix.system.openlog("ly", 0, 0);
        self.could_open_log_file = true;
    }
}

pub fn deinit(self: *LogFile, io: std.Io) void {
    if (self.maybe_file) |file| {
        file.close(io);
    } else {
        std.posix.system.closelog();
    }
}

pub fn info(self: *LogFile, io: std.Io, category: []const u8, comptime message: []const u8, args: anytype) !void {
    if (self.maybe_file_writer) |*writer| {
        var buffer: [128:0]u8 = undefined;
        const time = interop.timeAsString(io, &buffer, "%Y-%m-%d %H:%M:%S");

        try writer.interface.print("{s} [info/{s}] ", .{ time, category });
        try writer.interface.print(message, args);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    } else {
        var buffer: [1024]u8 = undefined;
        const slice = try std.fmt.bufPrint(&buffer, message, args);
        const msg = try std.fmt.bufPrintZ(buffer[slice.len..], "[info/{s}] {s}", .{ category, slice });

        std.posix.system.syslog(std.posix.LOG.INFO, msg.ptr);
    }
}

pub fn err(self: *LogFile, io: std.Io, category: []const u8, comptime message: []const u8, args: anytype) !void {
    if (self.maybe_file_writer) |*writer| {
        var buffer: [128:0]u8 = undefined;
        const time = interop.timeAsString(io, &buffer, "%Y-%m-%d %H:%M:%S");

        try writer.interface.print("{s} [err/{s}] ", .{ time, category });
        try writer.interface.print(message, args);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    } else {
        var buffer: [1024]u8 = undefined;
        const slice = try std.fmt.bufPrint(&buffer, message, args);
        const msg = try std.fmt.bufPrintZ(buffer[slice.len..], "[info/{s}] {s}", .{ category, slice });

        std.posix.system.syslog(std.posix.LOG.ERR, msg.ptr);
    }
}

fn openLogFile(io: std.Io, path: []const u8, log_file: *LogFile) !bool {
    var could_open_log_file = true;
    open_log_file: {
        log_file.maybe_file = std.Io.Dir.cwd().openFile(io, path, .{ .mode = .write_only }) catch std.Io.Dir.cwd().createFile(io, path, .{ .permissions = .fromMode(0o666) }) catch {
            // If we could neither open an existing log file nor create a new
            // one, abort.
            could_open_log_file = false;
            break :open_log_file;
        };
    }

    if (!could_open_log_file) {
        log_file.maybe_file = try std.Io.Dir.openFileAbsolute(io, "/dev/null", .{ .mode = .write_only });
    }

    var log_file_writer = log_file.maybe_file.?.writer(io, log_file.buffer);

    // Seek to the end of the log file
    if (could_open_log_file) {
        const stat = try log_file.maybe_file.?.stat(io);
        try log_file_writer.seekTo(stat.size);
    }

    log_file.maybe_file_writer = log_file_writer;
    return could_open_log_file;
}
