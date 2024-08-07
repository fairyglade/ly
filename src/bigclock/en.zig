const Lang = @import("Lang.zig");

const LocaleChars = Lang.LocaleChars;
const X = Lang.X;
const O = Lang.O;

// zig fmt: off
pub const locale_chars = LocaleChars{
    .ZERO = [_]u21{
        X,X,X,X,X,
        X,X,O,X,X,
        X,X,O,X,X,
        X,X,O,X,X,
        X,X,X,X,X,
    },
    .ONE = [_]u21{
        O,O,O,X,X,
        O,O,O,X,X,
        O,O,O,X,X,
        O,O,O,X,X,
        O,O,O,X,X,
    },
    .TWO = [_]u21{
        X,X,X,X,X,
        O,O,O,X,X,
        X,X,X,X,X,
        X,X,O,O,O,
        X,X,X,X,X,
    },
    .THREE = [_]u21{
        X,X,X,X,X,
        O,O,O,X,X,
        X,X,X,X,X,
        O,O,O,X,X,
        X,X,X,X,X,
    },
    .FOUR = [_]u21{
        X,X,O,X,X,
        X,X,O,X,X,
        X,X,X,X,X,
        O,O,O,X,X,
        O,O,O,X,X,
    },
    .FIVE = [_]u21{
        X,X,X,X,X,
        X,X,O,O,O,
        X,X,X,X,X,
        O,O,O,X,X,
        X,X,X,X,X,
    },
    .SIX = [_]u21{
        X,X,X,X,X,
        X,X,O,O,O,
        X,X,X,X,X,
        X,X,O,X,X,
        X,X,X,X,X,
    },
    .SEVEN = [_]u21{
        X,X,X,X,X,
        O,O,O,X,X,
        O,O,O,X,X,
        O,O,O,X,X,
        O,O,O,X,X,
    },
    .EIGHT = [_]u21{
        X,X,X,X,X,
        X,X,O,X,X,
        X,X,X,X,X,
        X,X,O,X,X,
        X,X,X,X,X,
    },
    .NINE = [_]u21{
        X,X,X,X,X,
        X,X,O,X,X,
        X,X,X,X,X,
        O,O,O,X,X,
        X,X,X,X,X,
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