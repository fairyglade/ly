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

pub fn addIf(self: Position, other: Position, condition: bool) Position {
    return .{
        .x = self.x + if (condition) other.x else 0,
        .y = self.y + if (condition) other.y else 0,
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

pub fn addXIf(self: Position, x: usize, condition: bool) Position {
    return .{
        .x = self.x + if (condition) x else 0,
        .y = self.y,
    };
}

pub fn addYIf(self: Position, y: usize, condition: bool) Position {
    return .{
        .x = self.x,
        .y = self.y + if (condition) y else 0,
    };
}

pub fn addXFrom(self: Position, other: Position) Position {
    return .{
        .x = self.x + other.x,
        .y = self.y,
    };
}

pub fn addYFrom(self: Position, other: Position) Position {
    return .{
        .x = self.x,
        .y = self.y + other.y,
    };
}

pub fn addXFromIf(self: Position, other: Position, condition: bool) Position {
    return .{
        .x = self.x + if (condition) other.x else 0,
        .y = self.y,
    };
}

pub fn addYFromIf(self: Position, other: Position, condition: bool) Position {
    return .{
        .x = self.x,
        .y = self.y + if (condition) other.y else 0,
    };
}

pub fn remove(self: Position, other: Position) Position {
    return .{
        .x = self.x - other.x,
        .y = self.y - other.y,
    };
}

pub fn removeIf(self: Position, other: Position, condition: bool) Position {
    return .{
        .x = self.x - if (condition) other.x else 0,
        .y = self.y - if (condition) other.y else 0,
    };
}

pub fn removeX(self: Position, x: usize) Position {
    return .{
        .x = self.x - x,
        .y = self.y,
    };
}

pub fn removeY(self: Position, y: usize) Position {
    return .{
        .x = self.x,
        .y = self.y - y,
    };
}

pub fn removeXIf(self: Position, x: usize, condition: bool) Position {
    return .{
        .x = self.x - if (condition) x else 0,
        .y = self.y,
    };
}

pub fn removeYIf(self: Position, y: usize, condition: bool) Position {
    return .{
        .x = self.x,
        .y = self.y - if (condition) y else 0,
    };
}

pub fn removeXFrom(self: Position, other: Position) Position {
    return .{
        .x = self.x - other.x,
        .y = self.y,
    };
}

pub fn removeYFrom(self: Position, other: Position) Position {
    return .{
        .x = self.x,
        .y = self.y - other.y,
    };
}

pub fn removeXFromIf(self: Position, other: Position, condition: bool) Position {
    return .{
        .x = self.x - if (condition) other.x else 0,
        .y = self.y,
    };
}

pub fn removeYFromIf(self: Position, other: Position, condition: bool) Position {
    return .{
        .x = self.x,
        .y = self.y - if (condition) other.y else 0,
    };
}

pub fn invert(self: Position, other: Position) Position {
    return .{
        .x = other.x - self.x,
        .y = other.y - self.y,
    };
}

pub fn invertIf(self: Position, other: Position, condition: bool) Position {
    return .{
        .x = if (condition) other.x - self.x else self.x,
        .y = if (condition) other.y - self.y else self.y,
    };
}

pub fn invertX(self: Position, width: usize) Position {
    return .{
        .x = width - self.x,
        .y = self.y,
    };
}

pub fn invertY(self: Position, height: usize) Position {
    return .{
        .x = self.x,
        .y = height - self.y,
    };
}

pub fn invertXIf(self: Position, width: usize, condition: bool) Position {
    return .{
        .x = if (condition) width - self.x else self.x,
        .y = self.y,
    };
}

pub fn invertYIf(self: Position, height: usize, condition: bool) Position {
    return .{
        .x = self.x,
        .y = if (condition) height - self.y else self.y,
    };
}

pub fn resetXFrom(self: Position, other: Position) Position {
    return .{
        .x = other.x,
        .y = self.y,
    };
}

pub fn resetYFrom(self: Position, other: Position) Position {
    return .{
        .x = self.x,
        .y = other.y,
    };
}

pub fn resetXFromIf(self: Position, other: Position, condition: bool) Position {
    return .{
        .x = if (condition) other.x else self.x,
        .y = self.y,
    };
}

pub fn resetYFromIf(self: Position, other: Position, condition: bool) Position {
    return .{
        .x = self.x,
        .y = if (condition) other.y else self.y,
    };
}
