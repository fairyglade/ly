const Animation = @This();

const VTable = struct {
    deinit_fn: *const fn (ptr: *anyopaque) void,
    realloc_fn: *const fn (ptr: *anyopaque) anyerror!void,
    draw_fn: *const fn (ptr: *anyopaque) void,
};

pointer: *anyopaque,
vtable: VTable,

pub fn init(
    pointer: anytype,
    comptime deinit_fn: fn (ptr: @TypeOf(pointer)) void,
    comptime realloc_fn: fn (ptr: @TypeOf(pointer)) anyerror!void,
    comptime draw_fn: fn (ptr: @TypeOf(pointer)) void,
) Animation {
    const Pointer = @TypeOf(pointer);
    const Impl = struct {
        pub fn deinitImpl(ptr: *anyopaque) void {
            const impl: Pointer = @ptrCast(@alignCast(ptr));
            return @call(.always_inline, deinit_fn, .{impl});
        }

        pub fn reallocImpl(ptr: *anyopaque) anyerror!void {
            const impl: Pointer = @ptrCast(@alignCast(ptr));
            return @call(.always_inline, realloc_fn, .{impl});
        }

        pub fn drawImpl(ptr: *anyopaque) void {
            const impl: Pointer = @ptrCast(@alignCast(ptr));
            return @call(.always_inline, draw_fn, .{impl});
        }

        const vtable = VTable{
            .deinit_fn = deinitImpl,
            .realloc_fn = reallocImpl,
            .draw_fn = drawImpl,
        };
    };

    return .{
        .pointer = pointer,
        .vtable = Impl.vtable,
    };
}

pub fn deinit(self: *Animation) void {
    const impl: @TypeOf(self.pointer) = @ptrCast(@alignCast(self.pointer));
    return @call(.auto, self.vtable.deinit_fn, .{impl});
}

pub fn realloc(self: *Animation) anyerror!void {
    const impl: @TypeOf(self.pointer) = @ptrCast(@alignCast(self.pointer));
    return @call(.auto, self.vtable.realloc_fn, .{impl});
}

pub fn draw(self: *Animation) void {
    const impl: @TypeOf(self.pointer) = @ptrCast(@alignCast(self.pointer));
    return @call(.auto, self.vtable.draw_fn, .{impl});
}
