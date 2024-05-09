const std = @import("std");

const ErrInt = std.meta.Int(.unsigned, @bitSizeOf(anyerror));

const ErrorHandler = packed struct {
    has_error: bool = false,
    err_int: ErrInt = 0,
};

const SharedError = @This();

data: []align(std.mem.page_size) u8,

pub fn init() !SharedError {
    const data = try std.posix.mmap(null, @sizeOf(ErrorHandler), std.posix.PROT.READ | std.posix.PROT.WRITE, .{ .TYPE = .SHARED, .ANONYMOUS = true }, -1, 0);

    return .{ .data = data };
}

pub fn deinit(self: *SharedError) void {
    std.posix.munmap(self.data);
}

pub fn writeError(self: SharedError, err: anyerror) void {
    var buf_stream = std.io.fixedBufferStream(self.data);
    const writer = buf_stream.writer();
    writer.writeStruct(ErrorHandler{ .has_error = true, .err_int = @intFromError(err) }) catch {};
}

pub fn readError(self: SharedError) ?anyerror {
    var buf_stream = std.io.fixedBufferStream(self.data);
    const reader = buf_stream.reader();
    const err_handler = try reader.readStruct(ErrorHandler);

    if (err_handler.has_error)
        return @errorFromInt(err_handler.err_int);

    return null;
}
