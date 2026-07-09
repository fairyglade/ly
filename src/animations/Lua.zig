const std = @import("std");
const ly_ui = @import("ly-ui");
const LogFile = ly_ui.ly_core.LogFile;
const Widget = ly_ui.Widget;
const TerminalBuffer = ly_ui.TerminalBuffer;
const Cell = ly_ui.Cell;
const Allocator = std.mem.Allocator;
const InfoLine = @import("../components/InfoLine.zig");
const Lang = @import("../config/Lang.zig");

const zlua = @import("zlua");

const ly_lua = @embedFile("ly.lua");

const Lua = @This();

allocator: Allocator,
instance: ?Widget = null,
lua: *zlua.Lua,
log: *LogFile,
terminal_buffer: *TerminalBuffer,
width: usize,
height: usize,
margin: usize,
io: std.Io,
animation_delay: u16,

info_line: *InfoLine,
fg: u32,
bg: u32,

lang: Lang,
full_color: bool,

lua_error: bool = false,
lua_error_logged: bool = false,
lua_str: ?[:0]const u8 = null,

pub fn init(
    io: std.Io,
    alloc: Allocator,
    log: *LogFile,
    buf: *TerminalBuffer,
    file: []const u8,
    margin: u8,
    animation_delay: u16,
    info_line: *InfoLine,
    fg: u32,
    bg: u32,
    lang: Lang,
    full_color: bool,
) !Lua {
    var self: Lua = .{
        .lua = try zlua.Lua.init(alloc),
        .allocator = alloc,
        .terminal_buffer = buf,
        .instance = null,
        .log = log,
        .width = 0,
        .height = 0,
        .margin = margin,
        .io = io,
        .animation_delay = animation_delay,
        .info_line = info_line,
        .fg = fg,
        .bg = bg,
        .lang = lang,
        .full_color = full_color,
    };

    // exclude IO and debug libraries
    self.lua.openBase();
    self.lua.openBit();
    self.lua.openMath();
    self.lua.openString();
    self.lua.openTable();

    file_loading: {
        const zf = std.mem.concatWithSentinel(alloc, u8, &[1][]const u8{file}, 0) catch |e| {
            try self.log.err(self.io, "lua", "failed to allocate file path: {}", .{e});
            self.lua_str = "failed to allocate file path!";
            self.info_line.addMessage(lang.err_alloc, self.bg, self.fg) catch {};
            return e;
        };
        defer alloc.free(zf);

        // create the ly table
        self.lua.newTable();
        self.lua.setGlobal("ly");

        // create ly.width and ly.height from TerminalBuffer width/height
        self.propagateTerminalBounds();

        _ = self.lua.getGlobal("ly");
        _ = self.lua.pushString("clock");
        self.lua.pushFunction(luaLyClock);
        self.lua.setTable(-3);
        _ = self.lua.pushString("putCell");
        self.lua.pushFunction(luaPutCell);
        self.lua.setTable(-3);
        _ = self.lua.pushString("putLabel");
        self.lua.pushFunction(luaPutLabel);
        self.lua.setTable(-3);
        _ = self.lua.pushString("putRect");
        self.lua.pushFunction(luaPutRect);
        self.lua.setTable(-3);
        self.lua.setGlobal("ly");

        self.lua.doFile(zf) catch {
            const errorStr = self.lua.toString(-1) catch unreachable;
            self.lua_str = try self.allocator.dupeSentinel(u8, errorStr, 0);
            try self.log.err(self.io, "lua", "lua error: {s}", .{errorStr});
            self.lua_error = true;
            break :file_loading;
        };
    }

    return self;
}

fn draw(self: *Lua) void {
    self.propagateTerminalBounds();
    if (self.lua_error) {
        // Ly's Red Screen of Omega-Death:tm:
        const RED: u32 = if (self.full_color) TerminalBuffer.Color.TRUE_RED else TerminalBuffer.Color.ECOL_RED;
        const cell = Cell.init(0x2588, RED, RED);
        for (0..self.terminal_buffer.height) |y|
            for (0..self.terminal_buffer.width) |x|
                cell.put(x, y) catch {};
        if (self.lua_str) |str|
            for (str, 0..) |c, i| {
                const dwidth = @divFloor(self.width, 2);
                const dlen = @divFloor(str.len, 2);
                Cell.init(c, 0x00FFFFFF, 0).put(
                    (if (dlen > dwidth) 0 else dwidth - dlen) + i,
                    self.margin + 5,
                ) catch {};
            };
        if (!self.lua_error_logged) {
            self.info_line.addMessage("lua animation failed", self.bg, self.fg) catch {};
            self.lua_error_logged = true;
        }
        return;
    }

    _ = self.lua.getGlobal("draw");
    self.lua.protectedCall(.{}) catch {
        const errorStr = self.lua.toString(-1) catch unreachable;
        self.lua_str = std.mem.concatWithSentinel(
            self.allocator,
            u8,
            &.{ "cannot call draw(): ", errorStr },
            0,
        ) catch unreachable;
        self.log.err(self.io, "lua", "error (cannot call draw()): {s}", .{errorStr}) catch unreachable;
        self.lua_error = true;
    };
}

fn calculateTimeout(self: *Lua, _: *anyopaque) !?usize {
    return self.animation_delay;
}

fn deinit(self: *Lua) void {
    if (self.lua_str) |str| self.allocator.free(str);
    self.lua.deinit();
}

pub fn widget(self: *Lua) *Widget {
    if (self.instance) |*inst| return inst;
    self.instance = Widget.init(
        "Lua",
        null,
        self,
        deinit,
        null,
        draw,
        null,
        null,
        calculateTimeout,
    );
    return &self.instance.?;
}

fn propagateTerminalBounds(self: *Lua) void {
    if (self.terminal_buffer.height == self.height and
        self.terminal_buffer.width == self.width)
        return;
    self.width = self.terminal_buffer.width;
    self.height = self.terminal_buffer.height;
    _ = self.lua.getGlobal("ly");
    _ = self.lua.pushString("width");
    self.lua.pushInteger(@intCast(self.terminal_buffer.width));
    self.lua.setTable(-3);
    _ = self.lua.pushString("height");
    self.lua.pushInteger(@intCast(self.terminal_buffer.height));
    self.lua.setTable(-3);
    self.lua.setGlobal("ly");
}

fn luaLyClock(state: ?*zlua.LuaState) callconv(.c) c_int {
    var threaded = std.Io.Threaded.init_single_threaded;
    const lua: *zlua.Lua = @ptrCast(@alignCast(state orelse unreachable));
    lua.pushInteger(std.Io.Timestamp.now(threaded.io(), .real).toMicroseconds());
    return 1;
}

fn luaPutCell(state: ?*zlua.LuaState) callconv(.c) c_int {
    const lua: *zlua.Lua = @ptrCast(@alignCast(state orelse unreachable));
    const MSG = "ly.putCell: cannot convert %s-typed ";
    const byte = lua.toNumeric(u32, 1) catch {
        const t = lua.typeName(lua.typeOf(1));
        lua.raiseErrorStr(MSG ++ "byte to u32", .{t.ptr});
    };
    const fg = lua.toNumeric(u32, 2) catch {
        const t = lua.typeName(lua.typeOf(2));
        lua.raiseErrorStr(MSG ++ "fg to u32", .{t.ptr});
    };
    const bg = lua.toNumeric(u32, 3) catch {
        const t = lua.typeName(lua.typeOf(3));
        lua.raiseErrorStr(MSG ++ "bg to u32", .{t.ptr});
    };
    const x = lua.toNumeric(usize, 4) catch {
        const t = lua.typeName(lua.typeOf(4));
        lua.raiseErrorStr(MSG ++ "x to usize", .{t.ptr});
    };
    const y = lua.toNumeric(usize, 5) catch {
        const t = lua.typeName(lua.typeOf(5));
        lua.raiseErrorStr(MSG ++ "y to usize", .{t.ptr});
    };
    TerminalBuffer.setCell(x, y, .{
        .fg = fg,
        .bg = bg,
        .ch = byte,
    }) catch {};
    return 0;
}

fn luaPutRect(state: ?*zlua.LuaState) callconv(.c) c_int {
    const lua: *zlua.Lua = @ptrCast(@alignCast(state orelse unreachable));
    const MSG = "ly.putRect: cannot convert %s-typed ";
    const byte = lua.toNumeric(u32, 1) catch {
        const t = lua.typeName(lua.typeOf(1));
        lua.raiseErrorStr(MSG ++ "byte to u32", .{t.ptr});
    };
    const fg = lua.toNumeric(u32, 2) catch {
        const t = lua.typeName(lua.typeOf(2));
        lua.raiseErrorStr(MSG ++ "fg to u32", .{t.ptr});
    };
    const bg = lua.toNumeric(u32, 3) catch {
        const t = lua.typeName(lua.typeOf(3));
        lua.raiseErrorStr(MSG ++ "bg to u32", .{t.ptr});
    };
    const x = lua.toNumeric(usize, 4) catch {
        const t = lua.typeName(lua.typeOf(4));
        lua.raiseErrorStr(MSG ++ "x to usize", .{t.ptr});
    };
    const y = lua.toNumeric(usize, 5) catch {
        const t = lua.typeName(lua.typeOf(5));
        lua.raiseErrorStr(MSG ++ "y to usize", .{t.ptr});
    };
    const w = lua.toNumeric(usize, 6) catch {
        const t = lua.typeName(lua.typeOf(5));
        lua.raiseErrorStr(MSG ++ "w to usize", .{t.ptr});
    };
    const h = lua.toNumeric(usize, 7) catch {
        const t = lua.typeName(lua.typeOf(5));
        lua.raiseErrorStr(MSG ++ "h to usize", .{t.ptr});
    };
    for (0..w) |wx| for (0..h) |hy|
        TerminalBuffer.setCell(x + wx, y + hy, .{
            .fg = fg,
            .bg = bg,
            .ch = byte,
        }) catch {};
    return 0;
}

fn luaPutLabel(state: ?*zlua.LuaState) callconv(.c) c_int {
    const lua: *zlua.Lua = @ptrCast(@alignCast(state orelse unreachable));
    const MSG = "ly.putLabel: cannot convert %s-typed ";
    const str = lua.toString(1) catch {
        const t = lua.typeName(lua.typeOf(2));
        lua.raiseErrorStr(MSG ++ "str to string", .{t.ptr});
    };
    const fg = lua.toNumeric(u32, 2) catch {
        const t = lua.typeName(lua.typeOf(2));
        lua.raiseErrorStr(MSG ++ "fg to u32", .{t.ptr});
    };
    const bg = lua.toNumeric(u32, 3) catch {
        const t = lua.typeName(lua.typeOf(3));
        lua.raiseErrorStr(MSG ++ "bg to u32", .{t.ptr});
    };
    const x = lua.toNumeric(usize, 4) catch {
        const t = lua.typeName(lua.typeOf(4));
        lua.raiseErrorStr(MSG ++ "x to usize", .{t.ptr});
    };
    const y = lua.toNumeric(usize, 5) catch {
        const t = lua.typeName(lua.typeOf(5));
        lua.raiseErrorStr(MSG ++ "y to usize", .{t.ptr});
    };
    TerminalBuffer.drawText(str, x, y, fg, bg) catch {};
    return 0;
}
