const Widget = @This();

const keyboard = @import("keyboard.zig");
const TerminalBuffer = @import("TerminalBuffer.zig");

const VTable = struct {
    deinit_fn: *const fn (ptr: *anyopaque) void,
    realloc_fn: *const fn (ptr: *anyopaque) anyerror!void,
    draw_fn: *const fn (ptr: *anyopaque) void,
    update_fn: *const fn (ptr: *anyopaque, ctx: *anyopaque) anyerror!void,
    handle_fn: *const fn (ptr: *anyopaque, maybe_key: ?keyboard.Key, insert_mode: bool) anyerror!void,
};

pointer: *anyopaque,
vtable: VTable,

pub fn init(
    pointer: anytype,
    comptime deinit_fn: ?fn (ptr: @TypeOf(pointer)) void,
    comptime realloc_fn: ?fn (ptr: @TypeOf(pointer)) anyerror!void,
    comptime draw_fn: ?fn (ptr: @TypeOf(pointer)) void,
    comptime update_fn: ?fn (ptr: @TypeOf(pointer), ctx: *anyopaque) anyerror!void,
    comptime handle_fn: ?fn (ptr: @TypeOf(pointer), maybe_key: ?keyboard.Key, insert_mode: bool) anyerror!void,
) Widget {
    const Pointer = @TypeOf(pointer);
    const Impl = struct {
        pub fn deinitImpl(ptr: *anyopaque) void {
            const impl: Pointer = @ptrCast(@alignCast(ptr));

            if (deinit_fn) |func| {
                return @call(
                    .always_inline,
                    func,
                    .{impl},
                );
            }
        }

        pub fn reallocImpl(ptr: *anyopaque) !void {
            const impl: Pointer = @ptrCast(@alignCast(ptr));

            if (realloc_fn) |func| {
                return @call(
                    .always_inline,
                    func,
                    .{impl},
                );
            }
        }

        pub fn drawImpl(ptr: *anyopaque) void {
            const impl: Pointer = @ptrCast(@alignCast(ptr));

            if (draw_fn) |func| {
                return @call(
                    .always_inline,
                    func,
                    .{impl},
                );
            }
        }

        pub fn updateImpl(ptr: *anyopaque, ctx: *anyopaque) !void {
            const impl: Pointer = @ptrCast(@alignCast(ptr));

            if (update_fn) |func| {
                return @call(
                    .always_inline,
                    func,
                    .{ impl, ctx },
                );
            }
        }

        pub fn handleImpl(ptr: *anyopaque, maybe_key: ?keyboard.Key, insert_mode: bool) !void {
            const impl: Pointer = @ptrCast(@alignCast(ptr));

            if (handle_fn) |func| {
                return @call(
                    .always_inline,
                    func,
                    .{ impl, maybe_key, insert_mode },
                );
            }
        }

        const vtable = VTable{
            .deinit_fn = deinitImpl,
            .realloc_fn = reallocImpl,
            .draw_fn = drawImpl,
            .update_fn = updateImpl,
            .handle_fn = handleImpl,
        };
    };

    return .{
        .pointer = pointer,
        .vtable = Impl.vtable,
    };
}

pub fn deinit(self: *Widget) void {
    const impl: @TypeOf(self.pointer) = @ptrCast(@alignCast(self.pointer));

    return @call(
        .auto,
        self.vtable.deinit_fn,
        .{impl},
    );
}

pub fn realloc(self: *Widget) !void {
    const impl: @TypeOf(self.pointer) = @ptrCast(@alignCast(self.pointer));

    return @call(
        .auto,
        self.vtable.realloc_fn,
        .{impl},
    );
}

pub fn draw(self: *Widget) void {
    const impl: @TypeOf(self.pointer) = @ptrCast(@alignCast(self.pointer));

    return @call(
        .auto,
        self.vtable.draw_fn,
        .{impl},
    );
}

pub fn update(self: *Widget, ctx: *anyopaque) !void {
    const impl: @TypeOf(self.pointer) = @ptrCast(@alignCast(self.pointer));

    return @call(
        .auto,
        self.vtable.update_fn,
        .{ impl, ctx },
    );
}

pub fn handle(self: *Widget, maybe_key: ?keyboard.Key, insert_mode: bool) !void {
    const impl: @TypeOf(self.pointer) = @ptrCast(@alignCast(self.pointer));

    return @call(
        .auto,
        self.vtable.handle_fn,
        .{ impl, maybe_key, insert_mode },
    );
}
