const std = @import("std");

pub const ini = @import("zigini");
pub const zlua = @import("zlua");
pub const Lua = zlua.Lua;

pub const interop = @import("interop.zig");
pub const UidRange = @import("UidRange.zig");
pub const LogFile = @import("LogFile.zig");
pub const SharedError = @import("SharedError.zig");
pub const custom = @import("custom.zig");

pub fn Parser(comptime T: type) type {
    return union(enum) {
        ini: IniParser(T),
        lua: LuaParser(T),

        pub fn errors(self: *const @This()) std.ArrayList(Error) {
            return switch (self.*) {
                inline else => |p| p.errors,
            };
        }

        pub fn maybe_load_error(self: *const @This()) ?anyerror {
            return switch (self.*) {
                inline else => |p| p.maybe_load_error,
            };
        }
        pub fn structure(self: *const @This()) T {
            return switch (self.*) {
                inline else => |p| p.structure,
            };
        }

        pub fn deinit(self: *@This()) void {
            switch (self.*) {
                inline else => |*p| p.deinit(),
            }
        }
    };
}

pub const Error = struct {
    type_name: []const u8,
    key: []const u8,
    value: []const u8,
    error_name: []const u8,
};

pub fn IniParser(comptime Struct: type) type {
    return struct {
        const Self = @This();
        const temporary_allocator = std.heap.page_allocator;

        pub var global_errors: std.ArrayList(Error) = .empty;

        ini_struct: ini.Ini(Struct),
        structure: Struct,
        maybe_load_error: ?anyerror,
        errors: std.ArrayList(Error),

        pub fn init(
            allocator: std.mem.Allocator,
            io: std.Io,
            path: []const u8,
            field_handler: ?fn (allocator: std.mem.Allocator, field: ini.IniField) ?ini.IniField,
        ) !Self {
            var ini_struct = ini.Ini(Struct).init(allocator);
            errdefer ini_struct.deinit();

            var maybe_load_error: ?anyerror = null;

            const structure = ini_struct.readFileToStruct(io, path, .{
                .fieldHandler = field_handler,
                .errorHandler = errorHandler,
                .comment_characters = "#",
            }) catch |err| load_error: {
                maybe_load_error = err;
                break :load_error Struct{};
            };

            return .{
                .ini_struct = ini_struct,
                .structure = structure,
                .maybe_load_error = maybe_load_error,
                .errors = global_errors,
            };
        }

        pub fn deinit(self: *Self) void {
            self.ini_struct.deinit();

            for (0..global_errors.items.len) |i| {
                const err = global_errors.items[i];
                temporary_allocator.free(err.type_name);
                temporary_allocator.free(err.key);
                temporary_allocator.free(err.value);
            }

            global_errors.deinit(temporary_allocator);
        }

        fn errorHandler(type_name: []const u8, key: []const u8, value: []const u8, err: anyerror) void {
            global_errors.append(temporary_allocator, .{
                .type_name = temporary_allocator.dupe(u8, type_name) catch return,
                .key = temporary_allocator.dupe(u8, key) catch return,
                .value = temporary_allocator.dupe(u8, value) catch return,
                .error_name = @errorName(err),
            }) catch return;
        }
    };
}

pub fn LuaParser(comptime Struct: type) type {
    return struct {
        const Self = @This();
        const temporary_allocator = std.heap.page_allocator;

        pub var global_errors: std.ArrayList(Error) = .empty;

        structure: Struct,
        errors: std.ArrayList(Error),
        maybe_load_error: ?anyerror,
        allocator: std.mem.Allocator,
        arena: std.heap.ArenaAllocator,

        pub fn init(
            allocator: std.mem.Allocator,
            path: []const u8,
        ) !Self {
            var arena = std.heap.ArenaAllocator.init(allocator);
            const arena_alloc = arena.allocator();

            var maybe_load_error: ?anyerror = null;
            errdefer |err| maybe_load_error = err;

            const data = parseLua(arena_alloc, path) catch load_error: {
                break :load_error Struct{};
            };

            if (global_errors.items.len != 0) {
                maybe_load_error = error.InvalidConfig;
            }

            return .{
                .structure = data,
                .errors = global_errors,
                .maybe_load_error = maybe_load_error,
                .allocator = allocator,
                .arena = arena,
            };
        }

        fn parseLua(
            allocator: std.mem.Allocator,
            path: []const u8,
        ) !Struct {
            var lua: *Lua = try .init(allocator);
            defer lua.deinit();

            lua.openBase();
            lua.openBit();
            lua.openMath();
            lua.openString();
            lua.openTable();

            // convert to sentinel terminated slice
            const spath: [:0]const u8 = try allocator.dupeSentinel(u8, path, 0);
            defer allocator.free(spath);
            lua.doFile(spath) catch return error.LuaError;

            var data: Struct = .{};
            switch (@typeInfo(Struct)) {
                .@"struct" => |struc| {
                    const ly_type = lua.getGlobal("ly");
                    defer lua.pop(1); // pop ly table
                    if (ly_type == .nil) return error.MissingLyTable;

                    inline for (struc.fields) |field| {
                        try setField(allocator, lua, field, &data);
                    }
                },
                else => @compileError("Expected a struct."),
            }

            // Parse custom binds and labels
            try parseCustom(lua);
            return data;
        }

        pub fn setField(allocator: std.mem.Allocator, lua: *Lua, comptime field: std.builtin.Type.StructField, data: *Struct) !void {
            const type_info = @typeInfo(field.type);
            const actual_type, const is_optional = blk: {
                if (type_info == .optional) {
                    break :blk .{ type_info.optional.child, true };
                }
                break :blk .{ field.type, false };
            };
            // push value to top of stack
            _ = lua.getField(-1, field.name);
            defer lua.pop(1);

            // handle null, i.e. undefined fields
            if (is_optional and lua.isNil(-1)) {
                @field(data, field.name) = null;
                return;
            }

            // handle missing required fields
            if (lua.isNil(-1)) {
                return error.MissingRequiredField;
            }
            const actual_type_info = @typeInfo(actual_type);

            errdefer |err| {
                const value = lua.toString(-1) catch "";
                const duped = allocator.dupe(u8, value) catch "";
                errorHandler(@typeName(field.type), field.name, duped, err);
            }

            // dispatch depending on type
            if (actual_type_info == .int and is_optional) {
                if (lua.isNumber(-1)) {
                    const value = try lua.toNumber(-1);
                    @field(data, field.name) = @trunc(value);
                } else {
                    const str = try lua.toString(-1);

                    var view = try std.unicode.Utf8View.init(str);
                    var iter = view.iterator();

                    const codepoint = iter.nextCodepoint();

                    if (iter.nextCodepoint() != null) return error.ExpectedSingleCharacter;

                    @field(data, field.name) = if (codepoint) |cp| @intCast(cp) else null;
                }
                // non null integer
            } else if (actual_type_info == .int) {
                if (lua.isNumber(-1)) {
                    const value = try lua.toNumber(-1);
                    @field(data, field.name) = @trunc(value);
                } else {
                    const str = try lua.toString(-1);

                    var view = try std.unicode.Utf8View.init(str);
                    var iter = view.iterator();

                    const codepoint = iter.nextCodepoint() orelse return error.EmptyString;

                    if (iter.nextCodepoint() != null) return error.ExpectedSingleCharacter;

                    @field(data, field.name) = @intCast(codepoint);
                }
            } else if (actual_type_info == .float) { // all floats
                const value = try lua.toNumber(-1);
                @field(data, field.name) = @floatCast(value);
            } else if (actual_type_info == .bool) {
                if (!lua.isBoolean(-1)) return error.ExpectedBoolean;
                const value = lua.toBoolean(-1);
                @field(data, field.name) = value;
            } else if (actual_type == []const u8) {
                const value = try lua.toString(-1);
                const duped = try allocator.dupe(u8, value);
                @field(data, field.name) = duped;
            } else if (actual_type == [:0]const u8) {
                const value = try lua.toString(-1);
                const duped = try allocator.dupeSentinel(u8, value, 0);
                @field(data, field.name) = duped;
            } else if (actual_type_info == .@"enum") {
                const value = try lua.toString(-1);
                const variant = std.meta.stringToEnum(actual_type, value) orelse return error.InvalidVariant;
                @field(data, field.name) = variant;
            } else unreachable;
        }

        pub fn parseCustom(lua: *Lua) !void {
            _ = lua.getGlobal("ly");
            defer lua.pop(1); // pop ly table
            if (!lua.isTable(-1)) return error.MissingLyTable;

            _ = lua.getField(-1, "custom_commands");
            // custom_commands can be omitted or empty, so we just skip instead of erroring

            if (lua.isTable(-1)) binds: {
                const len: usize = @intCast(lua.objectLen(-1));
                if (len == 0) break :binds;

                for (1..len + 1) |i| {
                    // push i-th table to stack
                    lua.pushInteger(@intCast(i));
                    const ith_table_type = lua.getTable(-2);
                    defer lua.pop(1); // i-th table in custom_commands
                    if (ith_table_type != .table) continue;

                    // skip command if binding isn't set or not a string
                    const binding_type = lua.getField(-1, "binding");
                    if (binding_type != .string) continue;
                    const binding = lua.toString(-1) catch continue;
                    const bindingZ = temporary_allocator.dupe(u8, binding) catch "";
                    std.debug.print("{s}", .{bindingZ});
                    lua.pop(1); // binding value

                    if (!custom.binds.contains(bindingZ)) {
                        custom.binds.put(temporary_allocator, bindingZ, .{}) catch {};
                    }
                    if (custom.binds.getPtr(bindingZ)) |command| {
                        // binding name
                        const name_type = lua.getField(-1, "name");
                        if (name_type != .string) continue;
                        const binding_name = lua.toString(-1) catch "";
                        command.name = temporary_allocator.dupe(u8, binding_name) catch "";
                        lua.pop(1); // name value

                        // binding command
                        const cmd_type = lua.getField(-1, "cmd");
                        if (cmd_type != .string) continue;
                        const binding_cmd = lua.toString(-1) catch "";
                        command.cmd = temporary_allocator.dupe(u8, binding_cmd) catch "";
                        lua.pop(1); // cmd value
                    }
                }
            }
            lua.pop(1);

            _ = lua.getField(-1, "custom_labels");
            // custom_labels can be omitted, so we just skip instead of erroring

            if (lua.isTable(-1)) labels: {
                const len: usize = @intCast(lua.objectLen(-1));
                if (len == 0) break :labels;

                for (1..len + 1) |i| {
                    // push i-th table to stack
                    lua.pushInteger(@intCast(i));
                    const ith_table_type = lua.getTable(-2);
                    defer lua.pop(1); // i-th table in custom_labels
                    if (ith_table_type != .table) continue;

                    // skip command if binding isn't set or not a string
                    const label_type = lua.getField(-1, "label");
                    if (label_type != .string) continue;
                    const label = lua.toString(-1) catch continue;
                    const labelZ = temporary_allocator.dupe(u8, label) catch "";
                    lua.pop(1); // label value

                    if (!custom.labels.contains(labelZ)) {
                        custom.labels.put(temporary_allocator, labelZ, .{ .name = labelZ }) catch {};
                    }
                    if (custom.labels.getPtr(labelZ)) |label_ptr| {
                        // label command
                        const cmd_type = lua.getField(-1, "cmd");
                        if (cmd_type != .string) continue;
                        const label_cmd = lua.toString(-1) catch "";
                        label_ptr.cmd = temporary_allocator.dupe(u8, label_cmd) catch "";
                        lua.pop(1); // cmd value

                        // label refresh
                        const name_type = lua.getField(-1, "refresh");
                        if (name_type != .number) continue;
                        const label_refresh: u32 = @intCast(lua.toInteger(-1) catch 0);
                        label_ptr.refresh = label_refresh;
                        lua.pop(1); // name value
                    }
                }
            }

            lua.pop(1);
        }

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
            for (0..global_errors.items.len) |i| {
                const err = global_errors.items[i];
                temporary_allocator.free(err.type_name);
                temporary_allocator.free(err.key);
                temporary_allocator.free(err.value);
            }

            global_errors.deinit(temporary_allocator);
        }

        fn errorHandler(type_name: []const u8, key: []const u8, value: []const u8, err: anyerror) void {
            global_errors.append(temporary_allocator, .{
                .type_name = temporary_allocator.dupe(u8, type_name) catch return,
                .key = temporary_allocator.dupe(u8, key) catch return,
                .value = temporary_allocator.dupe(u8, value) catch return,
                .error_name = @errorName(err),
            }) catch return;
        }
    };
}
