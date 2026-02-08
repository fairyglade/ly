const Position = @This();

x: usize,
y: usize,

pub fn init(x: usize, y: usize) Position {
    return .{
        .x = x,
        .y = y,
    };
}

pub fn add(self: Position, other: Position) Position {
    return .{
        .x = self.x + other.x,
        .y = self.y + other.y,
    };
}

pub fn addX(self: Position, x: usize) Position {
    return .{
        .x = self.x + x,
        .y = self.y,
    };
}

pub fn addY(self: Position, y: usize) Position {
    return .{
        .x = self.x,
        .y = self.y + y,
    };
}
