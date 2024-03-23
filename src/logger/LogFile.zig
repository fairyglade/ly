const std = @import("std");

const LogFile = @This();

file: ?std.fs.File = null,
writer: ?std.fs.File.Writer = null,
start_time: i64 = 0,

pub fn init(log_path: ?[]const u8) LogFile {
    if (log_path == null or log_path.?.len == 0) return LogFile{};

    const directory = std.fs.openDirAbsolute(log_path.?, std.fs.Dir.OpenDirOptions{}) catch return LogFile{};

    directory.rename("ly.log", "ly.log.old") catch |e| {
        if (e != error.FileNotFound) return LogFile{};
    };

    const createFlags = std.fs.File.CreateFlags{};
    const file = directory.createFile("ly.log", createFlags) catch return LogFile{};

    return LogFile{
        .file = file,
        .writer = file.writer(),
        .start_time = std.time.milliTimestamp(),
    };
}

pub fn deinit(self: LogFile) void {
    if (self.file) |file| file.close();
}

fn prettyPrint(self: LogFile, comptime log_level: std.log.Level, comptime format: []const u8, args: anytype) void {
    //if (comptime !std.log.logEnabled(log_level, .log_file)) return;
    const ms_since_start: f80 = @floatFromInt(std.time.milliTimestamp() - self.start_time);
    const log_time: f64 = @floatCast(ms_since_start / 1000);

    if (self.writer) |writer| {
        writer.print("[{d:.2}s] " ++ "{s}: " ++ format ++ "\n", .{ log_time, log_level.asText() } ++ args) catch return;
    }
}

pub fn info(self: LogFile, comptime format: []const u8, args: anytype) void {
    self.prettyPrint(.info, format, args);
}

pub fn debug(self: LogFile, comptime format: []const u8, args: anytype) void {
    self.prettyPrint(.debug, format, args);
}

pub fn warn(self: LogFile, comptime format: []const u8, args: anytype) void {
    self.prettyPrint(.warn, format, args);
}

pub fn err(self: LogFile, comptime format: []const u8, args: anytype) void {
    self.prettyPrint(.err, format, args);
}
