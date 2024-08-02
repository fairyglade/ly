const builtin = @import("builtin");

pub const WIDTH = 5;
pub const HEIGHT = 5;
pub const SIZE = WIDTH * HEIGHT;

pub const X: u32 = if (builtin.os.tag == .linux or builtin.os.tag.isBSD()) 0x2593 else '#';
pub const O: u32 = 0;

pub const LocaleChars = struct {
    ZERO:   [SIZE]u21,
    ONE:    [SIZE]u21,
    TWO:    [SIZE]u21,
    THREE:  [SIZE]u21,
    FOUR:   [SIZE]u21,
    FIVE:   [SIZE]u21,
    SIX:    [SIZE]u21,
    SEVEN:  [SIZE]u21,
    EIGHT:  [SIZE]u21,
    NINE:   [SIZE]u21,
    S:      [SIZE]u21,
    E:      [SIZE]u21,
};