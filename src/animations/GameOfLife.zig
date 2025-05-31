const std = @import("std");
const Animation = @import("../tui/Animation.zig");
const Cell = @import("../tui/Cell.zig");
const TerminalBuffer = @import("../tui/TerminalBuffer.zig");

const Allocator = std.mem.Allocator;
const Random = std.Random;

const GameOfLife = @This();

// Visual styles - using block characters like other animations
const ALIVE_CHAR: u21 = 0x2588; // Full block █
const DEAD_CHAR: u21 = ' ';
const NEIGHBOR_DIRS = [_][2]i8{
    .{ -1, -1 }, .{ -1, 0 }, .{ -1, 1 },
    .{ 0, -1 },  .{ 0, 1 },  .{ 1, -1 },
    .{ 1, 0 },   .{ 1, 1 },
};

allocator: Allocator,
terminal_buffer: *TerminalBuffer,
current_grid: []bool,
next_grid: []bool,
frame_counter: usize,
generation: u64,
fg_color: u32,
entropy_interval: usize,
frame_delay: usize,
initial_density: f32,
randomize_colors: bool,
dead_cell: Cell,
width: usize,
height: usize,

pub fn init(allocator: Allocator, terminal_buffer: *TerminalBuffer, fg_color: u32, entropy_interval: usize, frame_delay: usize, initial_density: f32, randomize_colors: bool) !GameOfLife {
    const width = terminal_buffer.width;
    const height = terminal_buffer.height;
    const grid_size = width * height;

    const current_grid = try allocator.alloc(bool, grid_size);
    const next_grid = try allocator.alloc(bool, grid_size);

    var game = GameOfLife{
        .allocator = allocator,
        .terminal_buffer = terminal_buffer,
        .current_grid = current_grid,
        .next_grid = next_grid,
        .frame_counter = 0,
        .generation = 0,
        .fg_color = if (randomize_colors) generateRandomColor(terminal_buffer.random) else fg_color,
        .entropy_interval = entropy_interval,
        .frame_delay = frame_delay,
        .initial_density = initial_density,
        .randomize_colors = randomize_colors,
        .dead_cell = .{ .ch = DEAD_CHAR, .fg = @intCast(TerminalBuffer.Color.DEFAULT), .bg = terminal_buffer.bg },
        .width = width,
        .height = height,
    };

    // Initialize grid
    game.initializeGrid();

    return game;
}

pub fn animation(self: *GameOfLife) Animation {
    return Animation.init(self, deinit, realloc, draw);
}

fn deinit(self: *GameOfLife) void {
    self.allocator.free(self.current_grid);
    self.allocator.free(self.next_grid);
}

fn realloc(self: *GameOfLife) anyerror!void {
    const new_width = self.terminal_buffer.width;
    const new_height = self.terminal_buffer.height;
    const new_size = new_width * new_height;

    const current_grid = try self.allocator.realloc(self.current_grid, new_size);
    const next_grid = try self.allocator.realloc(self.next_grid, new_size);

    self.current_grid = current_grid;
    self.next_grid = next_grid;
    self.width = new_width;
    self.height = new_height;

    self.initializeGrid();
    self.generation = 0;
}

fn draw(self: *GameOfLife) void {
    // Update game state at controlled frame rate
    self.frame_counter += 1;
    if (self.frame_counter >= self.frame_delay) {
        self.frame_counter = 0;
        self.updateGeneration();
        self.generation += 1;

        // Add entropy based on configuration (0 = disabled, >0 = interval)
        if (self.entropy_interval > 0 and self.generation % self.entropy_interval == 0) {
            self.addEntropy();
        }
    }

    // Render with the set color (either configured or randomly generated at startup)
    const alive_cell = Cell{ .ch = ALIVE_CHAR, .fg = self.fg_color, .bg = self.terminal_buffer.bg };

    for (0..self.height) |y| {
        const row_offset = y * self.width;
        for (0..self.width) |x| {
            const cell = if (self.current_grid[row_offset + x]) alive_cell else self.dead_cell;
            cell.put(x, y);
        }
    }
}

fn generateRandomColor(random: Random) u32 {
    // Generate a random RGB color with good visibility
    // Avoid very dark colors by using range 64-255 for each component
    const r = random.intRangeAtMost(u8, 64, 255);
    const g = random.intRangeAtMost(u8, 64, 255);
    const b = random.intRangeAtMost(u8, 64, 255);
    return (@as(u32, r) << 16) | (@as(u32, g) << 8) | @as(u32, b);
}

fn updateGeneration(self: *GameOfLife) void {
    // Conway's Game of Life rules with optimized neighbor counting
    for (0..self.height) |y| {
        const row_offset = y * self.width;
        for (0..self.width) |x| {
            const index = row_offset + x;
            const neighbors = self.countNeighborsOptimized(x, y);
            const is_alive = self.current_grid[index];

            // Optimized rule application
            self.next_grid[index] = switch (neighbors) {
                2 => is_alive,
                3 => true,
                else => false,
            };
        }
    }

    // Efficient grid swap
    std.mem.swap([]bool, &self.current_grid, &self.next_grid);
}

fn countNeighborsOptimized(self: *GameOfLife, x: usize, y: usize) u8 {
    var count: u8 = 0;

    for (NEIGHBOR_DIRS) |dir| {
        const neighbor_x = @as(i32, @intCast(x)) + dir[0];
        const neighbor_y = @as(i32, @intCast(y)) + dir[1];
        const width_i32: i32 = @intCast(self.width);
        const height_i32: i32 = @intCast(self.height);

        // Toroidal wrapping with modular arithmetic
        const wx: usize = @intCast(@mod(neighbor_x + width_i32, width_i32));
        const wy: usize = @intCast(@mod(neighbor_y + height_i32, height_i32));

        if (self.current_grid[wy * self.width + wx]) {
            count += 1;
        }
    }

    return count;
}

fn initializeGrid(self: *GameOfLife) void {
    const total_cells = self.width * self.height;

    // Clear grid
    @memset(self.current_grid, false);
    @memset(self.next_grid, false);

    // Random initialization with configurable density
    for (0..total_cells) |i| {
        self.current_grid[i] = self.terminal_buffer.random.float(f32) < self.initial_density;
    }
}

fn addEntropy(self: *GameOfLife) void {
    // Add fewer random cells but in clusters for more interesting patterns
    const clusters = 2;
    for (0..clusters) |_| {
        const cx = self.terminal_buffer.random.intRangeAtMost(usize, 1, self.width - 2);
        const cy = self.terminal_buffer.random.intRangeAtMost(usize, 1, self.height - 2);

        // Small cluster around center point
        for (0..3) |dy| {
            for (0..3) |dx| {
                if (self.terminal_buffer.random.float(f32) < 0.4) {
                    const x = (cx + dx) % self.width;
                    const y = (cy + dy) % self.height;
                    self.current_grid[y * self.width + x] = true;
                }
            }
        }
    }
}
