const Lang = @import("Lang.zig");

const LocaleChars = Lang.LocaleChars;
const X = Lang.X;
const O = Lang.O;

// zig fmt: off
pub const locale_chars = LocaleChars{
    .ZERO = [_]u21{
        O,O,O,O,O,
        O,O,X,O,O,
        O,X,O,X,O,
        O,O,X,O,O,
        O,O,O,O,O,
    },
    .ONE = [_]u21{
        O,O,X,O,O,
        O,X,X,O,O,
        O,O,X,O,O,
        O,O,X,O,O,
        O,O,X,O,O,
    },
    .TWO = [_]u21{
        O,X,O,X,O,
        O,X,X,X,O,
        O,X,O,O,O,
        O,X,O,O,O,
        O,X,O,O,O,
    },
    .THREE = [_]u21{
        X,O,X,O,X,
        X,X,X,X,X,
        X,O,O,O,O,
        X,O,O,O,O,
        X,O,O,O,O,
    },
    .FOUR = [_]u21{
        O,X,O,X,X,
        O,X,X,O,O,
        O,X,X,X,X,
        O,X,O,O,O,
        O,X,O,O,O,
    },
    .FIVE = [_]u21{
        O,O,X,X,O,
        O,X,O,O,X,
        X,O,O,O,X,
        X,O,X,O,X,
        O,X,O,X,O,
    },
    .SIX = [_]u21{
        O,X,X,O,O,
        O,X,O,O,X,
        O,O,X,O,O,
        O,X,O,O,O,
        X,O,O,O,O,
    },
    .SEVEN = [_]u21{
        X,O,O,O,X,
        X,O,O,O,X,
        O,X,O,X,O,
        O,X,O,X,O,
        O,O,X,O,O,
    },
    .EIGHT = [_]u21{
        O,O,O,X,O,
        O,O,X,O,X,
        O,O,X,O,X,
        O,X,O,O,X,
        O,X,O,O,X,
    },
    .NINE = [_]u21{
        O,X,X,X,O,
        O,X,O,X,O,
        O,X,X,X,O,
        O,O,O,X,O,
        O,O,O,X,O,
    },
    .S = [_]u21{
        O,O,O,O,O,
        O,O,X,O,O,
        O,O,O,O,O,
        O,O,X,O,O,
        O,O,O,O,O,
    },
    .E = [_]u21{
        O,O,O,O,O,
        O,O,O,O,O,
        O,O,O,O,O,
        O,O,O,O,O,
        O,O,O,O,O,
    },
};
// zig fmt: on