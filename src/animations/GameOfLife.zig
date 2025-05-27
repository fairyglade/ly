const std = @import("std");
const Animation = @import("../tui/Animation.zig");
const Cell = @import("../tui/Cell.zig");
const TerminalBuffer = @import("../tui/TerminalBuffer.zig");

const Allocator = std.mem.Allocator;
const Random = std.Random;

const GameOfLife = @This();

pub const FRAME_DELAY: usize = 6; // Slightly faster for smoother animation
pub const INITIAL_DENSITY: f32 = 0.4; // Increased for more activity
pub const COLOR_CYCLE_DELAY: usize = 192; // Change color every N frames

// Visual styles - using block characters like other animations
const ALIVE_CHAR: u21 = 0x2588; // Full block █
const DEAD_CHAR: u21 = ' ';

// ANSI basic colors using TerminalBuffer.Color like other animations
const ANSI_COLORS = [_]u32{
    @intCast(TerminalBuffer.Color.RED),
    @intCast(TerminalBuffer.Color.GREEN),
    @intCast(TerminalBuffer.Color.YELLOW),
    @intCast(TerminalBuffer.Color.BLUE),
    @intCast(TerminalBuffer.Color.MAGENTA),
    @intCast(TerminalBuffer.Color.CYAN),
    @intCast(TerminalBuffer.Color.RED | TerminalBuffer.Styling.BOLD),
    @intCast(TerminalBuffer.Color.GREEN | TerminalBuffer.Styling.BOLD),
    @intCast(TerminalBuffer.Color.YELLOW | TerminalBuffer.Styling.BOLD),
    @intCast(TerminalBuffer.Color.BLUE | TerminalBuffer.Styling.BOLD),
    @intCast(TerminalBuffer.Color.MAGENTA | TerminalBuffer.Styling.BOLD),
    @intCast(TerminalBuffer.Color.CYAN | TerminalBuffer.Styling.BOLD),
};
const NUM_COLORS = ANSI_COLORS.len;
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
color_index: usize,
color_counter: usize,
dead_cell: Cell,
width: usize,
height: usize,

pub fn init(allocator: Allocator, terminal_buffer: *TerminalBuffer) !GameOfLife {
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
        .color_index = 0,
        .color_counter = 0,
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

    // Only reallocate if size changed significantly
    if (new_size != self.width * self.height) {
        const current_grid = try self.allocator.realloc(self.current_grid, new_size);
        const next_grid = try self.allocator.realloc(self.next_grid, new_size);

        self.current_grid = current_grid;
        self.next_grid = next_grid;
        self.width = new_width;
        self.height = new_height;

        self.initializeGrid();
        self.generation = 0;
        self.color_index = 0;
        self.color_counter = 0;
    }
}

fn draw(self: *GameOfLife) void {
    // Update ANSI color cycling at controlled rate
    self.color_counter += 1;
    if (self.color_counter >= COLOR_CYCLE_DELAY) {
        self.color_counter = 0;
        self.color_index = (self.color_index + 1) % NUM_COLORS;
    }

    // Update game state at controlled frame rate
    self.frame_counter += 1;
    if (self.frame_counter >= FRAME_DELAY) {
        self.frame_counter = 0;
        self.updateGeneration();
        self.generation += 1;

        // Add entropy less frequently to reduce computational overhead
        if (self.generation % 150 == 0) {
            self.addEntropy();
        }
    }

    // Render with ANSI color cycling - use current color from the array (same method as Matrix/Doom)
    const current_color = ANSI_COLORS[self.color_index];
    const alive_cell = Cell{ .ch = ALIVE_CHAR, .fg = current_color, .bg = self.terminal_buffer.bg };

    for (0..self.height) |y| {
        const row_offset = y * self.width;
        for (0..self.width) |x| {
            const cell = if (self.current_grid[row_offset + x]) alive_cell else self.dead_cell;
            cell.put(x, y);
        }
    }
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

    // Use cached dimensions and more efficient bounds checking
    for (NEIGHBOR_DIRS) |dir| {
        const nx = @as(i32, @intCast(x)) + dir[0];
        const ny = @as(i32, @intCast(y)) + dir[1];

        // Toroidal wrapping with modular arithmetic
        const wx: usize = @intCast(@mod(nx + @as(i32, @intCast(self.width)), @as(i32, @intCast(self.width))));
        const wy: usize = @intCast(@mod(ny + @as(i32, @intCast(self.height)), @as(i32, @intCast(self.height))));

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

    // Random initialization with better distribution
    for (0..total_cells) |i| {
        self.current_grid[i] = self.terminal_buffer.random.float(f32) < INITIAL_DENSITY;
    }

    // Add interesting patterns with better positioning
    self.addPatterns();
}

fn addPatterns(self: *GameOfLife) void {
    if (self.width < 8 or self.height < 8) return;

    // Add multiple instances of each pattern for liveliness
    for (0..3) |_| {
        self.addGlider();
        if (self.width >= 10 and self.height >= 10) {
            self.addBlock();
            self.addBlinker();
        }
    }
}

fn addGlider(self: *GameOfLife) void {
    const x = self.terminal_buffer.random.intRangeAtMost(usize, 2, self.width - 4);
    const y = self.terminal_buffer.random.intRangeAtMost(usize, 2, self.height - 4);

    // Classic glider pattern
    const positions = [_][2]usize{ .{ 1, 0 }, .{ 2, 1 }, .{ 0, 2 }, .{ 1, 2 }, .{ 2, 2 } };

    for (positions) |pos| {
        const idx = (y + pos[1]) * self.width + (x + pos[0]);
        self.current_grid[idx] = true;
    }
}

fn addBlock(self: *GameOfLife) void {
    const x = self.terminal_buffer.random.intRangeAtMost(usize, 1, self.width - 3);
    const y = self.terminal_buffer.random.intRangeAtMost(usize, 1, self.height - 3);

    // 2x2 block
    const positions = [_][2]usize{ .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 1, 1 } };

    for (positions) |pos| {
        const idx = (y + pos[1]) * self.width + (x + pos[0]);
        self.current_grid[idx] = true;
    }
}

fn addBlinker(self: *GameOfLife) void {
    const x = self.terminal_buffer.random.intRangeAtMost(usize, 1, self.width - 4);
    const y = self.terminal_buffer.random.intRangeAtMost(usize, 1, self.height - 2);

    // 3-cell horizontal line
    for (0..3) |i| {
        const idx = y * self.width + (x + i);
        self.current_grid[idx] = true;
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
