const std = @import("std");

const LogFile = @This();

path: []const u8,
could_open_log_file: bool = undefined,
file: std.fs.File = undefined,
buffer: []u8,
file_writer: std.fs.File.Writer = undefined,

pub fn init(path: []const u8, buffer: []u8) !LogFile {
    var log_file = LogFile{ .path = path, .buffer = buffer };
    log_file.could_open_log_file = try openLogFile(path, &log_file);
    return log_file;
}

pub fn reinit(self: *LogFile) !void {
    self.could_open_log_file = try openLogFile(self.path, self);
}

pub fn deinit(self: *LogFile) void {
    self.file_writer.interface.flush() catch {};
    self.file.close();
}

fn openLogFile(path: []const u8, log_file: *LogFile) !bool {
    var could_open_log_file = true;
    open_log_file: {
        log_file.file = std.fs.cwd().openFile(path, .{ .mode = .write_only }) catch std.fs.cwd().createFile(path, .{ .mode = 0o666 }) catch {
            // If we could neither open an existing log file nor create a new
            // one, abort.
            could_open_log_file = false;
            break :open_log_file;
        };
    }

    if (!could_open_log_file) {
        log_file.file = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    }

    var log_file_writer = log_file.file.writer(log_file.buffer);

    // Seek to the end of the log file
    if (could_open_log_file) {
        const stat = try log_file.file.stat();
        try log_file_writer.seekTo(stat.size);
    }

    log_file.file_writer = log_file_writer;
    return could_open_log_file;
}
