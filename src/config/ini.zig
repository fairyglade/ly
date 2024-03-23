const std = @import("std");
const ini = @import("ini");

const Allocator = std.mem.Allocator;

const trueOrFalse = std.ComptimeStringMap(bool, .{ .{ "true", true }, .{ "false", false }, .{ "1", true }, .{ "0", false } });

pub fn Ini(comptime T: type) type {
    return struct {
        const Self = @This();

        data: T,
        allocator: std.mem.Allocator,
        list: std.ArrayList([]u8),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .data = T{},
                .allocator = allocator,
                .list = std.ArrayList([]u8).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.list.items) |item| {
                self.allocator.free(item);
            }
            self.list.deinit();
        }

        pub fn readToStruct(self: *Self, path: []const u8) !T {
            const file = try std.fs.cwd().openFile(path, .{});
            defer file.close();
            var parser = ini.parse(self.allocator, file.reader());
            defer parser.deinit();

            var ns: []u8 = &.{};
            defer self.allocator.free(ns);

            while (try parser.next()) |record| {
                switch (record) {
                    .section => |heading| {
                        ns = try self.allocator.realloc(ns, heading.len);
                        @memcpy(ns, heading);
                        std.mem.replaceScalar(u8, ns, ' ', '_');
                    },
                    .property => |kv| {
                        inline for (std.meta.fields(T)) |field| {
                            const field_info = @typeInfo(field.type);
                            if (field_info == .Struct or (field_info == .Optional and @typeInfo(field_info.Optional.child) == .Struct)) {
                                if (ns.len != 0 and std.mem.eql(u8, field.name, ns)) {
                                    inline for (std.meta.fields(@TypeOf(@field(self.data, field.name)))) |inner_field| {
                                        if (std.mem.eql(u8, inner_field.name, kv.key)) {
                                            @field(@field(self.data, field.name), inner_field.name) = try self.convert(inner_field.type, kv.value);
                                        }
                                    }
                                }
                            } else if (ns.len == 0 and std.mem.eql(u8, field.name, kv.key)) {
                                @field(self.data, field.name) = try self.convert(field.type, kv.value);
                            }
                        }
                    },
                    .enumeration => {},
                }
            }

            return self.data;
        }

        fn convert(self: *Self, comptime T1: type, val: []const u8) !T1 {
            return switch (@typeInfo(T1)) {
                .Int, .ComptimeInt => try std.fmt.parseInt(T1, val, 0),
                .Float, .ComptimeFloat => try std.fmt.parseFloat(T1, val),
                .Bool => trueOrFalse.get(val).?,
                .Enum => std.meta.stringToEnum(T1, val).?,
                .Optional => |opt| {
                    if (val.len == 0 or std.mem.eql(u8, val, "null")) return null;
                    return try self.convert(opt.child, val);
                },
                else => {
                    const a_val = try self.allocator.alloc(u8, val.len);
                    @memcpy(a_val, val);
                    try self.list.append(a_val);
                    return @as(T1, a_val);
                },
            };
        }
    };
}

fn writeProperty(writer: anytype, field_name: []const u8, val: anytype) !void {
    switch (@typeInfo(@TypeOf(val))) {
        .Bool => {
            try writer.print("{s}={d}\n", .{ field_name, @intFromBool(val) });
        },
        .Int, .ComptimeInt, .Float, .ComptimeFloat => {
            try writer.print("{s}={d}\n", .{ field_name, val });
        },
        .Enum => {
            try writer.print("{s}={s}\n", .{ field_name, @tagName(val) });
        },
        else => {
            try writer.print("{s}={s}\n", .{ field_name, val });
        },
    }
}

fn isDefaultValue(field: anytype, field_value: field.type) bool {
    if (field.default_value) |default_value_ao| {
        const def_val: *align(field.alignment) const anyopaque = @alignCast(default_value_ao);
        const default_value = @as(*const field.type, @ptrCast(def_val)).*;
        const field_t_info = @typeInfo(field.type);
        if (field_t_info == .Optional) {
            if (default_value != null) {
                if (field_value != null) {
                    if (field_t_info == .Pointer) {
                        return std.mem.eql(field_t_info.Pointer.child, default_value.?, field_value.?);
                    } else {
                        return default_value.? == field_value.?;
                    }
                }
                return false;
            }
            return field_value == null;
        }

        if (field_t_info == .Pointer) {
            return std.mem.eql(field_t_info.Pointer.child, default_value, field_value);
        } else {
            return default_value == field_value;
        }
    }

    return false;
}

pub fn writeFromStruct(data: anytype, writer: anytype, ns: ?[]const u8) !void {
    if (@typeInfo(@TypeOf(data)) != .Struct) @compileError("writeFromStruct() requires a struct");

    var should_write_ns = ns != null;

    inline for (std.meta.fields(@TypeOf(data))) |field| {
        switch (@typeInfo(field.type)) {
            .Struct => continue,
            .Optional => |opt| {
                if (@typeInfo(opt.child) != .Struct) {
                    const val = @field(data, field.name);
                    if (val) |field_val| {
                        if (!isDefaultValue(field, @field(data, field.name))) {
                            if (should_write_ns) {
                                try writer.print("[{s}]\n", .{ns.?});
                                should_write_ns = false;
                            }
                            try writeProperty(writer, field.name, field_val);
                        }
                    } else if (!isDefaultValue(field, @field(data, field.name))) {
                        if (should_write_ns) {
                            try writer.print("[{s}]\n", .{ns.?});
                            should_write_ns = false;
                        }
                        try writeProperty(writer, field.name, "");
                    }
                } else continue;
            },
            else => {
                if (!isDefaultValue(field, @field(data, field.name))) {
                    if (should_write_ns) {
                        try writer.print("[{s}]\n", .{ns.?});
                        should_write_ns = false;
                    }
                    try writeProperty(writer, field.name, @field(data, field.name));
                }
            },
        }
    }

    if (ns == null) {
        inline for (std.meta.fields(@TypeOf(data))) |field| {
            switch (@typeInfo(field.type)) {
                .Struct => {
                    try writeFromStruct(@field(data, field.name), writer, field.name);
                },
                .Optional => |opt| {
                    if (@typeInfo(opt.child) == .Struct) {
                        if (@field(data, field.name)) |inner_data| {
                            try writeFromStruct(inner_data, writer, field.name);
                        }
                    } else continue;
                },
                else => continue,
            }
        }
    }
}
