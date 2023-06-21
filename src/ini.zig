const std = @import("std");

pub const Token = union(enum) { comment, section: []const u8, key: []const u8, value: []const u8 };

pub fn getTok(data: []const u8, pos: *usize) ?Token {
    // If the position advances to the end of the data, there's no more tokens for us
    if (pos.* >= data.len) {
        return null;
    }

    while (pos.* < data.len) {
        var current = data[pos.*];
        pos.* += 1;

        switch (current) {
            ' ', '\t', '\r', '\n' => {},
            '[' => {
                var start = pos.*;

                current = data[pos.*];

                while (current != ']') : (pos.* += 1) {
                    current = data[pos.*];
                }

                return Token{ .section = data[start .. pos.* - 1] };
            },
            '=' => {
                current = data[pos.*];

                while (current == ' ' or current == '\t') {
                    pos.* += 1;
                    current = data[pos.*];
                }

                var start = pos.*;

                while (current != '\n') : (pos.* += 1) {
                    current = data[pos.*];
                }

                return Token{ .value = if (start == pos.*) "" else data[start .. pos.* - 1] };
            },
            ';', '#' => {
                current = data[pos.*];

                while (current != '\n') : (pos.* += 1) {
                    current = data[pos.*];
                }

                return Token.comment;
            },
            else => {
                var start = pos.* - 1;

                current = data[pos.*];

                while (std.ascii.isAlphanumeric(current) or current == '_') : (pos.* += 1) {
                    current = data[pos.*];
                }

                pos.* -= 1;

                return Token{ .key = data[start..pos.*] };
            },
        }
    }

    return null;
}
pub fn readToStruct(comptime T: type, data: []const u8) !T {
    var namespace: []const u8 = "";
    var pos: usize = 0;
    var ret = std.mem.zeroes(T);
    while (getTok(data, &pos)) |tok| {
        switch (tok) {
            .comment => {},
            .section => |ns| {
                namespace = ns;
            },
            .key => |key| {
                var next_tok = getTok(data, &pos);
                // if there's nothing just give a comment which is also a syntax error
                switch (next_tok orelse .comment) {
                    .value => |value| {
                        // now we have the namespace, key, and value
                        // namespace and key are runtime values, so we need to loop the struct instead of using @field
                        inline for (std.meta.fields(T)) |ns_info| {
                            if (eql(ns_info.name, namespace)) {
                                // @field(ret, ns_info.name) contains the inner struct now
                                // loop over the fields of the inner struct, and check for key matches
                                inline for (std.meta.fields(@TypeOf(@field(ret, ns_info.name)))) |key_info| {
                                    if (std.mem.eql(u8, key_info.name, key)) {
                                        // now we have a key match, give it the value
                                        const my_type = @TypeOf(@field(@field(ret, ns_info.name), key_info.name));
                                        @field(@field(ret, ns_info.name), key_info.name) = try convert(my_type, value);
                                    }
                                }
                            }
                        }
                    },
                    // after a key, a value must follow
                    else => return error.NoValueAfterKey,
                }
            },
            // if we get a value with no key, that's a bit nonsense
            .value => return error.ValueWithNoKey,
        }
    }
    return ret;
}
// I'll add more later
const truthyAndFalsy = std.ComptimeStringMap(bool, .{ .{ "true", true }, .{ "false", false }, .{ "1", true }, .{ "0", false } });
pub fn convert(comptime T: type, val: []const u8) !T {
    return switch (@typeInfo(T)) {
        .Int, .ComptimeInt => try parseInt(T, val, 0),
        .Float, .ComptimeFloat => try std.fmt.parseFloat(T, val),
        .Bool => truthyAndFalsy.get(val).?,
        .Enum => std.meta.stringToEnum(T, val).?,
        else => @as(T, val),
    };
}
pub fn writeStruct(struct_value: anytype, writer: anytype) !void {
    inline for (std.meta.fields(@TypeOf(struct_value))) |field| {
        try writer.print("[{s}]\n", .{field.name});
        const pairs = @field(struct_value, field.name);
        inline for (std.meta.fields(@TypeOf(pairs))) |pair| {
            const key_value = @field(pairs, pair.name);
            const key_value_type = @TypeOf(key_value);
            const key_value_type_info = @typeInfo(key_value_type);

            if (key_value_type == []const u8) {
                try writer.print("{s} = {s}\n", .{ pair.name, key_value });
            } else if (key_value_type_info == .Enum) {
                inline for (key_value_type_info.Enum.fields) |f| {
                    var buffer: [128]u8 = undefined;
                    var haystack = try std.fmt.bufPrint(&buffer, "{}", .{key_value});

                    // TODO: Check type?
                    if (std.mem.endsWith(u8, haystack, f.name)) {
                        try writer.print("{s} = {s}\n", .{ pair.name, f.name });
                    }
                }
            } else {
                try writer.print("{s} = {}\n", .{ pair.name, key_value });
            }
        }
    }
}
// Checks if the string is actually a single ASCII character, else, parse as an integer
fn parseInt(comptime T: type, buf: []const u8, base: u8) std.fmt.ParseIntError!T {
    if (buf.len == 1) {
        var first_char = buf[0];

        if (std.ascii.isASCII(first_char) and !std.ascii.isDigit(first_char)) {
            return first_char;
        }
    }

    return std.fmt.parseInt(T, buf, base);
}
// Checks if 2 strings are equal, but comparing " " with "_"
fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) {
        return false;
    }

    if (a.ptr == b.ptr) {
        return true;
    }

    for (a, b) |a_elem, b_elem| {
        if (a_elem != if (b_elem == ' ') '_' else b_elem) {
            return false;
        }
    }

    return true;
}
