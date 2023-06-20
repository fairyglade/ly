const std = @import("std");

// we ignore whitespace and comments
pub const Token = union(enum) { comment, section: []const u8, key: []const u8, value: []const u8 };

pub const State = enum { normal, section, key, value, comment };

pub fn getTok(data: []const u8, pos: *usize, state: *State) ?Token {
    // if the position advances to the end of the data, there's no more tokens for us
    if (pos.* >= data.len) return null;
    var cur: u8 = 0;
    // used for slicing
    var start = pos.*;
    var end = start;

    while (pos.* < data.len) {
        cur = data[pos.*];
        pos.* += 1;
        switch (state.*) {
            .normal => {
                switch (cur) {
                    '[' => {
                        state.* = .section;
                        start = pos.*;
                        end = start;
                    },
                    '=' => {
                        state.* = .value;
                        start = pos.*;
                        if (std.ascii.isWhitespace(data[start])) start += 1;
                        end = start;
                    },
                    ';', '#' => {
                        state.* = .comment;
                    },
                    // if it is whitespace itgets skipped over anyways
                    else => if (!std.ascii.isWhitespace(cur)) {
                        state.* = .key;
                        start = pos.* - 1;
                        end = start;
                    },
                }
            },
            .section => {
                end += 1;
                switch (cur) {
                    ']' => {
                        state.* = .normal;
                        pos.* += 1;
                        return Token{ .section = data[start .. end - 1] };
                    },
                    else => {},
                }
            },
            .value => {
                switch (cur) {
                    ';', '#' => {
                        state.* = .comment;
                        return Token{ .value = data[start .. end - 2] };
                    },
                    else => {
                        end += 1;
                        switch (cur) {
                            '\n' => {
                                state.* = .normal;
                                return Token{ .value = data[start .. end - 2] };
                            },
                            else => {},
                        }
                    },
                }
            },
            .comment => {
                end += 1;
                switch (cur) {
                    '\n' => {
                        state.* = .normal;
                        return Token.comment;
                    },
                    else => {},
                }
            },
            .key => {
                end += 1;
                if (!(std.ascii.isAlphanumeric(cur) or cur == '_')) {
                    state.* = .normal;
                    return Token{ .key = data[start..end] };
                }
            },
        }
    }
    return null;
}
pub fn readToStruct(comptime T: type, data: []const u8) !T {
    var namespace: []const u8 = "";
    var pos: usize = 0;
    var state: State = .normal;
    var ret = std.mem.zeroes(T);
    while (getTok(data, &pos, &state)) |tok| {
        switch (tok) {
            .comment => {},
            .section => |ns| {
                namespace = ns;
            },
            .key => |key| {
                var next_tok = getTok(data, &pos, &state);
                // if there's nothing just give a comment which is also a syntax error
                switch (next_tok orelse .comment) {
                    .value => |value| {
                        // now we have the namespace, key, and value
                        // namespace and key are runtime values, so we need to loop the struct instead of using @field
                        inline for (std.meta.fields(T)) |ns_info| {
                            if (std.mem.eql(u8, ns_info.name, namespace)) {
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
                    else => return error.SyntaxError,
                }
            },
            // if we get a value with no key, that's a bit nonsense
            .value => return error.SyntaxError,
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
fn parseInt(comptime T: type, buf: []const u8, base: u8) std.fmt.ParseIntError!T {
    if (buf.len == 1) {
        var first_char = buf[0];

        if (std.ascii.isASCII(first_char) and !std.ascii.isDigit(first_char)) {
            return first_char;
        }
    }

    return std.fmt.parseInt(T, buf, base);
}
