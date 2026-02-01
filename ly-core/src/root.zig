const std = @import("std");
const ini = @import("zigini");

pub const interop = @import("interop.zig");
pub const UidRange = @import("UidRange.zig");
pub const LogFile = @import("LogFile.zig");
pub const SharedError = @import("SharedError.zig");

pub fn IniParser(comptime Struct: type) type {
    return struct {
        const Self = @This();
        const temporary_allocator = std.heap.page_allocator;

        pub const Error = struct {
            type_name: []const u8,
            key: []const u8,
            value: []const u8,
            error_name: []const u8,
        };
        pub var global_errors: std.ArrayList(Error) = .empty;

        ini_struct: ini.Ini(Struct),
        structure: Struct,
        maybe_load_error: ?anyerror,
        errors: std.ArrayList(Error),

        pub fn init(
            allocator: std.mem.Allocator,
            path: []const u8,
            field_handler: ?fn (allocator: std.mem.Allocator, field: ini.IniField) ?ini.IniField,
        ) !Self {
            var ini_struct = ini.Ini(Struct).init(allocator);
            errdefer ini_struct.deinit();

            var maybe_load_error: ?anyerror = null;

            const structure = ini_struct.readFileToStruct(path, .{
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
