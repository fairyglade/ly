const utils = @import("../utils.zig");

const InfoLine = @This();

text: []const u8 = "",
width: u8 = 0,

pub fn setText(self: *InfoLine, text: []const u8) !void {
    self.width = if (text.len > 0) try utils.strWidth(text) else 0;
    self.text = text;
}
