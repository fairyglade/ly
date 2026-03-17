const Widget = @This();

const keyboard = @import("keyboard.zig");
const TerminalBuffer = @import("TerminalBuffer.zig");

const VTable = struct {
    deinit_fn: ?*const fn (ptr: *anyopaque) void,
    realloc_fn: ?*const fn (ptr: *anyopaque) anyerror!void,
    draw_fn: *const fn (ptr: *anyopaque) void,
    update_fn: ?*const fn (ptr: *anyopaque, ctx: *anyopaque) anyerror!void,
    handle_fn: ?*const fn (ptr: *anyopaque, maybe_key: ?keyboard.Key, insert_mode: bool) anyerror!void,
    calculate_timeout_fn: ?*const fn (ptr: *anyopaque, ctx: *anyopaque) anyerror!?usize,
};

id: u64,
display_name: []const u8,
pointer: *anyopaque,
vtable: VTable,

pub fn init(
    display_name: []const u8,
    pointer: anytype,
    comptime deinit_fn: ?fn (ptr: @TypeOf(pointer)) void,
    comptime realloc_fn: ?fn (ptr: @TypeOf(pointer)) anyerror!void,
    comptime draw_fn: fn (ptr: @TypeOf(pointer)) void,
    comptime update_fn: ?fn (ptr: @TypeOf(pointer), ctx: *anyopaque) anyerror!void,
    comptime handle_fn: ?fn (ptr: @TypeOf(pointer), maybe_key: ?keyboard.Key, insert_mode: bool) anyerror!void,
    comptime calculate_timeout_fn: ?fn (ptr: @TypeOf(pointer), ctx: *anyopaque) anyerror!?usize,
) Widget {
    const Pointer = @TypeOf(pointer);
    const Impl = struct {
        pub fn deinitImpl(ptr: *anyopaque) void {
            const impl: Pointer = @ptrCast(@alignCast(ptr));

            return @call(
                .always_inline,
                deinit_fn.?,
                .{impl},
            );
        }

        pub fn reallocImpl(ptr: *anyopaque) !void {
            const impl: Pointer = @ptrCast(@alignCast(ptr));

            return @call(
                .always_inline,
                realloc_fn.?,
                .{impl},
            );
        }

        pub fn drawImpl(ptr: *anyopaque) void {
            const impl: Pointer = @ptrCast(@alignCast(ptr));

            return @call(
                .always_inline,
                draw_fn,
                .{impl},
            );
        }

        pub fn updateImpl(ptr: *anyopaque, ctx: *anyopaque) !void {
            const impl: Pointer = @ptrCast(@alignCast(ptr));

            return @call(
                .always_inline,
                update_fn.?,
                .{ impl, ctx },
            );
        }

        pub fn handleImpl(ptr: *anyopaque, maybe_key: ?keyboard.Key, insert_mode: bool) !void {
            const impl: Pointer = @ptrCast(@alignCast(ptr));

            return @call(
                .always_inline,
                handle_fn.?,
                .{ impl, maybe_key, insert_mode },
            );
        }

        pub fn calculateTimeoutImpl(ptr: *anyopaque, ctx: *anyopaque) !?usize {
            const impl: Pointer = @ptrCast(@alignCast(ptr));

            return @call(
                .always_inline,
                calculate_timeout_fn.?,
                .{ impl, ctx },
            );
        }

        const vtable = VTable{
            .deinit_fn = if (deinit_fn != null) deinitImpl else null,
            .realloc_fn = if (realloc_fn != null) reallocImpl else null,
            .draw_fn = drawImpl,
            .update_fn = if (update_fn != null) updateImpl else null,
            .handle_fn = if (handle_fn != null) handleImpl else null,
            .calculate_timeout_fn = if (calculate_timeout_fn != null) calculateTimeoutImpl else null,
        };
    };

    return .{
        .id = @intFromPtr(Impl.vtable.draw_fn),
        .display_name = display_name,
        .pointer = pointer,
        .vtable = Impl.vtable,
    };
}

pub fn deinit(self: *Widget) void {
    const impl: @TypeOf(self.pointer) = @ptrCast(@alignCast(self.pointer));

    if (self.vtable.deinit_fn) |deinit_fn| {
        return @call(
            .auto,
            deinit_fn,
            .{impl},
        );
    }
}

pub fn realloc(self: *Widget) !void {
    const impl: @TypeOf(self.pointer) = @ptrCast(@alignCast(self.pointer));

    if (self.vtable.realloc_fn) |realloc_fn| {
        return @call(
            .auto,
            realloc_fn,
            .{impl},
        );
    }
}

pub fn draw(self: *Widget) void {
    const impl: @TypeOf(self.pointer) = @ptrCast(@alignCast(self.pointer));

    @call(
        .auto,
        self.vtable.draw_fn,
        .{impl},
    );
}

pub fn update(self: *Widget, ctx: *anyopaque) !void {
    const impl: @TypeOf(self.pointer) = @ptrCast(@alignCast(self.pointer));

    if (self.vtable.update_fn) |update_fn| {
        return @call(
            .auto,
            update_fn,
            .{ impl, ctx },
        );
    }
}

pub fn handle(self: *Widget, maybe_key: ?keyboard.Key, insert_mode: bool) !void {
    const impl: @TypeOf(self.pointer) = @ptrCast(@alignCast(self.pointer));

    if (self.vtable.handle_fn) |handle_fn| {
        return @call(
            .auto,
            handle_fn,
            .{ impl, maybe_key, insert_mode },
        );
    }
}

pub fn calculateTimeout(self: *Widget, ctx: *anyopaque) !?usize {
    const impl: @TypeOf(self.pointer) = @ptrCast(@alignCast(self.pointer));

    if (self.vtable.calculate_timeout_fn) |calculate_timeout_fn| {
        return @call(
            .auto,
            calculate_timeout_fn,
            .{ impl, ctx },
        );
    }

    return null;
}
