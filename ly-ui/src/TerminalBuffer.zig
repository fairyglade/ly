const std = @import("std");
const Allocator = std.mem.Allocator;
const Random = std.Random;

const ly_core = @import("ly-core");
const interop = ly_core.interop;
const LogFile = ly_core.LogFile;
const SharedError = ly_core.SharedError;
pub const termbox = @import("termbox2");

const Cell = @import("Cell.zig");
const keyboard = @import("keyboard.zig");
const Position = @import("Position.zig");
const Widget = @import("Widget.zig");

const TerminalBuffer = @This();

const KeybindCallbackFn = *const fn (*anyopaque) anyerror!bool;
const KeybindMap = std.AutoHashMap(keyboard.Key, struct {
    callback: KeybindCallbackFn,
    context: *anyopaque,
});

pub const InitOptions = struct {
    fg: u32,
    bg: u32,
    border_fg: u32,
    full_color: bool,
    is_tty: bool,
};

pub const Styling = struct {
    pub const BOLD = termbox.TB_BOLD;
    pub const UNDERLINE = termbox.TB_UNDERLINE;
    pub const REVERSE = termbox.TB_REVERSE;
    pub const ITALIC = termbox.TB_ITALIC;
    pub const BLINK = termbox.TB_BLINK;
    pub const HI_BLACK = termbox.TB_HI_BLACK;
    pub const BRIGHT = termbox.TB_BRIGHT;
    pub const DIM = termbox.TB_DIM;
};

pub const Color = struct {
    pub const DEFAULT = 0x00000000;
    pub const TRUE_BLACK = Styling.HI_BLACK;
    pub const TRUE_RED = 0x00FF0000;
    pub const TRUE_GREEN = 0x0000FF00;
    pub const TRUE_YELLOW = 0x00FFFF00;
    pub const TRUE_BLUE = 0x000000FF;
    pub const TRUE_MAGENTA = 0x00FF00FF;
    pub const TRUE_CYAN = 0x0000FFFF;
    pub const TRUE_WHITE = 0x00FFFFFF;
    pub const TRUE_DIM_RED = 0x00800000;
    pub const TRUE_DIM_GREEN = 0x00008000;
    pub const TRUE_DIM_YELLOW = 0x00808000;
    pub const TRUE_DIM_BLUE = 0x00000080;
    pub const TRUE_DIM_MAGENTA = 0x00800080;
    pub const TRUE_DIM_CYAN = 0x00008080;
    pub const TRUE_DIM_WHITE = 0x00C0C0C0;
    pub const ECOL_BLACK = 1;
    pub const ECOL_RED = 2;
    pub const ECOL_GREEN = 3;
    pub const ECOL_YELLOW = 4;
    pub const ECOL_BLUE = 5;
    pub const ECOL_MAGENTA = 6;
    pub const ECOL_CYAN = 7;
    pub const ECOL_WHITE = 8;
};

pub const START_POSITION = Position.init(0, 0);

log_file: *LogFile,
random: Random,
width: usize,
height: usize,
fg: u32,
bg: u32,
border_fg: u32,
box_chars: struct {
    left_up: u32,
    left_down: u32,
    right_up: u32,
    right_down: u32,
    top: u32,
    bottom: u32,
    left: u32,
    right: u32,
},
blank_cell: Cell,
full_color: bool,
termios: ?std.posix.termios,
keybinds: KeybindMap,
handlable_widgets: std.ArrayList(*Widget),
run: bool,
update: bool,
active_widget_index: usize,

pub fn init(
    allocator: Allocator,
    options: InitOptions,
    log_file: *LogFile,
    random: Random,
) !TerminalBuffer {
    // Initialize termbox
    _ = termbox.tb_init();

    if (options.full_color) {
        _ = termbox.tb_set_output_mode(termbox.TB_OUTPUT_TRUECOLOR);
        try log_file.info("tui", "termbox2 set to 24-bit color output mode", .{});
    } else {
        try log_file.info("tui", "termbox2 set to eight-color output mode", .{});
    }

    _ = termbox.tb_clear();

    // Let's take some precautions here and clear the back buffer as well
    try clearBackBuffer();

    const width: usize = @intCast(termbox.tb_width());
    const height: usize = @intCast(termbox.tb_height());

    try log_file.info("tui", "screen resolution is {d}x{d}", .{ width, height });

    return .{
        .log_file = log_file,
        .random = random,
        .width = width,
        .height = height,
        .fg = options.fg,
        .bg = options.bg,
        .border_fg = options.border_fg,
        .box_chars = if (interop.supportsUnicode()) .{
            .left_up = 0x250C,
            .left_down = 0x2514,
            .right_up = 0x2510,
            .right_down = 0x2518,
            .top = 0x2500,
            .bottom = 0x2500,
            .left = 0x2502,
            .right = 0x2502,
        } else .{
            .left_up = '+',
            .left_down = '+',
            .right_up = '+',
            .right_down = '+',
            .top = '-',
            .bottom = '-',
            .left = '|',
            .right = '|',
        },
        .blank_cell = Cell.init(' ', options.fg, options.bg),
        .full_color = options.full_color,
        // Needed to reclaim the TTY after giving up its control
        .termios = try std.posix.tcgetattr(std.posix.STDIN_FILENO),
        .keybinds = KeybindMap.init(allocator),
        .handlable_widgets = .empty,
        .run = true,
        .update = true,
        .active_widget_index = 0,
    };
}

pub fn deinit(self: *TerminalBuffer) void {
    self.keybinds.deinit();
    TerminalBuffer.shutdown();
}

pub fn runEventLoop(
    self: *TerminalBuffer,
    allocator: Allocator,
    shared_error: SharedError,
    layers: [][]Widget,
    active_widget: Widget,
    inactivity_delay: u16,
    insert_mode: *bool,
    position_widgets_fn: *const fn (*anyopaque) anyerror!void,
    inactivity_event_fn: ?*const fn (*anyopaque) anyerror!void,
    context: *anyopaque,
) !void {
    try self.registerKeybind("Ctrl+K", &moveCursorUp, self);
    try self.registerKeybind("Up", &moveCursorUp, self);

    try self.registerKeybind("Ctrl+J", &moveCursorDown, self);
    try self.registerKeybind("Down", &moveCursorDown, self);

    try self.registerKeybind("Tab", &wrapCursor, self);
    try self.registerKeybind("Shift+Tab", &wrapCursorReverse, self);

    defer self.handlable_widgets.deinit(allocator);

    var i: usize = 0;
    for (layers) |layer| {
        for (layer) |*widget| {
            if (widget.vtable.handle_fn != null) {
                try self.handlable_widgets.append(allocator, widget);

                if (widget.id == active_widget.id) self.active_widget_index = i;
                i += 1;
            }
        }
    }

    for (layers) |layer| {
        for (layer) |*widget| {
            try widget.update(context);
        }
    }
    try @call(.auto, position_widgets_fn, .{context});

    var event: termbox.tb_event = undefined;
    var inactivity_cmd_ran = false;
    var inactivity_time_start = try interop.getTimeOfDay();

    while (self.run) {
        if (self.update) {
            for (layers) |layer| {
                for (layer) |*widget| {
                    try widget.update(context);
                }
            }

            // Reset cursor
            const current_widget = self.getActiveWidget();
            current_widget.handle(null, insert_mode.*) catch |err| {
                shared_error.writeError(error.SetCursorFailed);
                try self.log_file.err(
                    "tui",
                    "failed to set cursor in active widget '{s}': {s}",
                    .{ current_widget.display_name, @errorName(err) },
                );
            };

            try TerminalBuffer.clearScreen(false);

            for (layers) |layer| {
                for (layer) |*widget| {
                    widget.draw();
                }
            }

            TerminalBuffer.presentBuffer();
        }

        var maybe_timeout: ?usize = null;
        for (layers) |layer| {
            for (layer) |*widget| {
                if (try widget.calculateTimeout(context)) |widget_timeout| {
                    if (maybe_timeout == null or widget_timeout < maybe_timeout.?) maybe_timeout = widget_timeout;
                }
            }
        }

        if (inactivity_event_fn) |inactivity_fn| {
            const time = try interop.getTimeOfDay();

            if (!inactivity_cmd_ran and time.seconds - inactivity_time_start.seconds > inactivity_delay) {
                try @call(.auto, inactivity_fn, .{context});
                inactivity_cmd_ran = true;
            }
        }

        const event_error = if (maybe_timeout) |timeout| termbox.tb_peek_event(&event, @intCast(timeout)) else termbox.tb_poll_event(&event);

        self.update = maybe_timeout != null;

        if (event_error < 0) continue;

        // Input of some kind was detected, so reset the inactivity timer
        inactivity_time_start = try interop.getTimeOfDay();

        if (event.type == termbox.TB_EVENT_RESIZE) {
            self.width = TerminalBuffer.getWidth();
            self.height = TerminalBuffer.getHeight();

            try self.log_file.info(
                "tui",
                "screen resolution updated to {d}x{d}",
                .{ self.width, self.height },
            );

            for (layers) |layer| {
                for (layer) |*widget| {
                    widget.realloc() catch |err| {
                        shared_error.writeError(error.WidgetReallocationFailed);
                        try self.log_file.err(
                            "tui",
                            "failed to reallocate widget '{s}': {s}",
                            .{ widget.display_name, @errorName(err) },
                        );
                    };
                }
            }

            try @call(.auto, position_widgets_fn, .{context});

            self.update = true;
            continue;
        }

        var maybe_keys = try self.handleKeybind(allocator, event);
        if (maybe_keys) |*keys| {
            defer keys.deinit(allocator);

            const current_widget = self.getActiveWidget();
            for (keys.items) |key| {
                current_widget.handle(key, insert_mode.*) catch |err| {
                    shared_error.writeError(error.CurrentWidgetHandlingFailed);
                    try self.log_file.err(
                        "tui",
                        "failed to handle active widget '{s}': {s}",
                        .{ current_widget.display_name, @errorName(err) },
                    );
                };
            }

            self.update = true;
        }
    }
}

pub fn stopEventLoop(self: *TerminalBuffer) void {
    self.run = false;
}

pub fn drawNextFrame(self: *TerminalBuffer, value: bool) void {
    self.update = value;
}

pub fn getActiveWidget(self: *TerminalBuffer) *Widget {
    return self.handlable_widgets.items[self.active_widget_index];
}

pub fn setActiveWidget(self: *TerminalBuffer, widget: Widget) void {
    for (self.handlable_widgets.items, 0..) |widg, i| {
        if (widg.id == widget.id) self.active_widget_index = i;
    }
}

pub fn getWidth() usize {
    return @intCast(termbox.tb_width());
}

pub fn getHeight() usize {
    return @intCast(termbox.tb_height());
}

pub fn setCursor(x: usize, y: usize) void {
    _ = termbox.tb_set_cursor(@intCast(x), @intCast(y));
}

pub fn clearScreen(clear_back_buffer: bool) !void {
    _ = termbox.tb_clear();
    if (clear_back_buffer) try clearBackBuffer();
}

pub fn shutdown() void {
    _ = termbox.tb_shutdown();
}

pub fn presentBuffer() void {
    _ = termbox.tb_present();
}

pub fn getCell(x: usize, y: usize) ?Cell {
    var maybe_cell: ?*termbox.tb_cell = undefined;
    _ = termbox.tb_get_cell(
        @intCast(x),
        @intCast(y),
        1,
        &maybe_cell,
    );

    if (maybe_cell) |cell| {
        return Cell.init(cell.ch, cell.fg, cell.bg);
    }

    return null;
}

pub fn setCell(x: usize, y: usize, cell: Cell) void {
    _ = termbox.tb_set_cell(
        @intCast(x),
        @intCast(y),
        cell.ch,
        cell.fg,
        cell.bg,
    );
}

pub fn reclaim(self: TerminalBuffer) !void {
    if (self.termios) |termios| {
        // Take back control of the TTY
        _ = termbox.tb_init();

        if (self.full_color) {
            _ = termbox.tb_set_output_mode(termbox.TB_OUTPUT_TRUECOLOR);
        }

        try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, termios);
    }
}

pub fn registerKeybind(
    self: *TerminalBuffer,
    keybind: []const u8,
    callback: KeybindCallbackFn,
    context: *anyopaque,
) !void {
    const key = try self.parseKeybind(keybind);

    self.keybinds.put(key, .{
        .callback = callback,
        .context = context,
    }) catch |err| {
        try self.log_file.err(
            "tui",
            "failed to register keybind {s}: {s}",
            .{ keybind, @errorName(err) },
        );
    };
}

pub fn simulateKeybind(self: *TerminalBuffer, keybind: []const u8) !bool {
    const key = try self.parseKeybind(keybind);

    if (self.keybinds.get(key)) |binding| {
        return try @call(
            .auto,
            binding.callback,
            .{binding.context},
        );
    }

    return true;
}

pub fn drawText(
    text: []const u8,
    x: usize,
    y: usize,
    fg: u32,
    bg: u32,
) void {
    const yc: c_int = @intCast(y);
    const utf8view = std.unicode.Utf8View.init(text) catch return;
    var utf8 = utf8view.iterator();

    var i: c_int = @intCast(x);
    while (utf8.nextCodepoint()) |codepoint| : (i += termbox.tb_wcwidth(codepoint)) {
        _ = termbox.tb_set_cell(i, yc, codepoint, fg, bg);
    }
}

pub fn drawConfinedText(
    text: []const u8,
    x: usize,
    y: usize,
    max_length: usize,
    fg: u32,
    bg: u32,
) void {
    const yc: c_int = @intCast(y);
    const utf8view = std.unicode.Utf8View.init(text) catch return;
    var utf8 = utf8view.iterator();

    var i: c_int = @intCast(x);
    while (utf8.nextCodepoint()) |codepoint| : (i += termbox.tb_wcwidth(codepoint)) {
        if (i - @as(c_int, @intCast(x)) >= max_length) break;
        _ = termbox.tb_set_cell(i, yc, codepoint, fg, bg);
    }
}

pub fn drawCharMultiple(
    char: u32,
    x: usize,
    y: usize,
    length: usize,
    fg: u32,
    bg: u32,
) void {
    const cell = Cell.init(char, fg, bg);
    for (0..length) |xx| cell.put(x + xx, y);
}

// Every codepoint is assumed to have a width of 1.
// Since Ly is normally running in a TTY, this should be fine.
pub fn strWidth(str: []const u8) usize {
    const utf8view = std.unicode.Utf8View.init(str) catch return str.len;
    var utf8 = utf8view.iterator();
    var length: c_int = 0;

    while (utf8.nextCodepoint()) |codepoint| {
        length += termbox.tb_wcwidth(codepoint);
    }

    return @intCast(length);
}

fn clearBackBuffer() !void {
    // Clear the TTY because termbox2 doesn't seem to do it properly
    const capability = termbox.global.caps[termbox.TB_CAP_CLEAR_SCREEN];
    const capability_slice = std.mem.span(capability);
    _ = try std.posix.write(termbox.global.ttyfd, capability_slice);
}

fn parseKeybind(self: *TerminalBuffer, keybind: []const u8) !keyboard.Key {
    var key = std.mem.zeroes(keyboard.Key);
    var iterator = std.mem.splitScalar(u8, keybind, '+');

    while (iterator.next()) |item| {
        var found = false;

        inline for (std.meta.fields(keyboard.Key)) |field| {
            if (std.ascii.eqlIgnoreCase(field.name, item)) {
                @field(key, field.name) = true;
                found = true;
                break;
            }
        }

        if (!found) {
            try self.log_file.err(
                "tui",
                "failed to parse key {s} of keybind {s}",
                .{ item, keybind },
            );
        }
    }

    return key;
}

fn handleKeybind(
    self: *TerminalBuffer,
    allocator: Allocator,
    tb_event: termbox.tb_event,
) !?std.ArrayList(keyboard.Key) {
    var keys = try keyboard.getKeyList(allocator, tb_event);

    for (keys.items) |key| {
        if (self.keybinds.get(key)) |binding| {
            const passthrough_event = try @call(
                .auto,
                binding.callback,
                .{binding.context},
            );

            if (!passthrough_event) {
                keys.deinit(allocator);
                return null;
            }

            return keys;
        }
    }

    return keys;
}

fn moveCursorUp(ptr: *anyopaque) !bool {
    var state: *TerminalBuffer = @ptrCast(@alignCast(ptr));
    if (state.active_widget_index == 0) return false;

    state.active_widget_index -= 1;
    state.update = true;
    return false;
}

fn moveCursorDown(ptr: *anyopaque) !bool {
    var state: *TerminalBuffer = @ptrCast(@alignCast(ptr));
    if (state.active_widget_index == state.handlable_widgets.items.len - 1) return false;

    state.active_widget_index += 1;
    state.update = true;
    return false;
}

fn wrapCursor(ptr: *anyopaque) !bool {
    var state: *TerminalBuffer = @ptrCast(@alignCast(ptr));

    state.active_widget_index = (state.active_widget_index + 1) % state.handlable_widgets.items.len;
    state.update = true;
    return false;
}

fn wrapCursorReverse(ptr: *anyopaque) !bool {
    var state: *TerminalBuffer = @ptrCast(@alignCast(ptr));

    state.active_widget_index = if (state.active_widget_index == 0) state.handlable_widgets.items.len - 1 else state.active_widget_index - 1;
    state.update = true;
    return false;
}
