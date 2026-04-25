const std = @import("std");

const ErrInt = std.meta.Int(.unsigned, @bitSizeOf(anyerror));
const PaddingInt = std.meta.Int(.unsigned, 8 - (@bitSizeOf(ErrInt) + @bitSizeOf(bool)) % 8);

const ErrorHandler = packed struct {
    has_error: bool = false,
    err_int: ErrInt = 0,
    padding: PaddingInt = 0,
};

const SharedError = @This();

data: []align(std.heap.page_size_min) u8,
write_error_event_fn: ?*const fn (anyerror, *anyopaque) anyerror!void,
ctx: ?*anyopaque,

pub fn init(
    write_error_event_fn: ?*const fn (anyerror, *anyopaque) anyerror!void,
    ctx: ?*anyopaque,
) !SharedError {
    const data = try std.posix.mmap(null, @sizeOf(ErrorHandler), .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED, .ANONYMOUS = true }, -1, 0);

    return .{
        .data = data,
        .write_error_event_fn = write_error_event_fn,
        .ctx = ctx,
    };
}

pub fn deinit(self: *SharedError) void {
    std.posix.munmap(self.data);
}

pub fn writeError(self: SharedError, err: anyerror) void {
    var writer: std.Io.Writer = .fixed(self.data);
    writer.writeStruct(ErrorHandler{ .has_error = true, .err_int = @intFromError(err) }, .native) catch {};

    if (self.write_error_event_fn) |write_error_event_fn| {
        @call(.auto, write_error_event_fn, .{ err, self.ctx.? }) catch {};
    }
}

pub fn readError(self: SharedError) ?anyerror {
    var reader: std.Io.Reader = .fixed(self.data);
    const err_handler = try reader.takeStruct(ErrorHandler, .native);

    if (err_handler.has_error)
        return @errorFromInt(err_handler.err_int);

    return null;
}
