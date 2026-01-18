const ly_core = @import("ly-core");

pub const WIDTH = 5;
pub const HEIGHT = 5;
pub const SIZE = WIDTH * HEIGHT;

pub const X: u32 = if (ly_core.interop.supportsUnicode()) 0x2593 else '#';
pub const O: u32 = 0;

// zig fmt: off
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
    P:      [SIZE]u21,
    A:      [SIZE]u21,
    M:      [SIZE]u21,
};
// zig fmt: on
