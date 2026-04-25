const std = @import("std");
const interop = @import("interop.zig");

const LogFile = @This();

path: []const u8,
could_open_log_file: bool = undefined,
file: std.Io.File = undefined,
buffer: []u8,
file_writer: std.Io.File.Writer = undefined,

pub fn init(io: std.Io, path: []const u8, buffer: []u8) !LogFile {
    var log_file = LogFile{ .path = path, .buffer = buffer };
    log_file.could_open_log_file = try openLogFile(io, path, &log_file);
    return log_file;
}

pub fn reinit(self: *LogFile, io: std.Io) !void {
    self.could_open_log_file = try openLogFile(io, self.path, self);
}

pub fn deinit(self: *LogFile, io: std.Io) void {
    self.file.close(io);
}

pub fn info(self: *LogFile, io: std.Io, category: []const u8, comptime message: []const u8, args: anytype) !void {
    var buffer: [128:0]u8 = undefined;
    const time = interop.timeAsString(io, &buffer, "%Y-%m-%d %H:%M:%S");

    try self.file_writer.interface.print("{s} [info/{s}] ", .{ time, category });
    try self.file_writer.interface.print(message, args);
    try self.file_writer.interface.writeByte('\n');
    try self.file_writer.interface.flush();
}

pub fn err(self: *LogFile, io: std.Io, category: []const u8, comptime message: []const u8, args: anytype) !void {
    var buffer: [128:0]u8 = undefined;
    const time = interop.timeAsString(io, &buffer, "%Y-%m-%d %H:%M:%S");

    try self.file_writer.interface.print("{s} [err/{s}] ", .{ time, category });
    try self.file_writer.interface.print(message, args);
    try self.file_writer.interface.writeByte('\n');
    try self.file_writer.interface.flush();
}

fn openLogFile(io: std.Io, path: []const u8, log_file: *LogFile) !bool {
    var could_open_log_file = true;
    open_log_file: {
        log_file.file = std.Io.Dir.cwd().openFile(io, path, .{ .mode = .write_only }) catch std.Io.Dir.cwd().createFile(io, path, .{ .permissions = .fromMode(0o666) }) catch {
            // If we could neither open an existing log file nor create a new
            // one, abort.
            could_open_log_file = false;
            break :open_log_file;
        };
    }

    if (!could_open_log_file) {
        log_file.file = try std.Io.Dir.openFileAbsolute(io, "/dev/null", .{ .mode = .write_only });
    }

    var log_file_writer = log_file.file.writer(io, log_file.buffer);

    // Seek to the end of the log file
    if (could_open_log_file) {
        const stat = try log_file.file.stat(io);
        try log_file_writer.seekTo(stat.size);
    }

    log_file.file_writer = log_file_writer;
    return could_open_log_file;
}
