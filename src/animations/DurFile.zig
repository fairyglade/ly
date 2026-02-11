const std = @import("std");
const Allocator = std.mem.Allocator;
const Json = std.json;
const eql = std.mem.eql;
const flate = std.compress.flate;

const ly_core = @import("ly-core");
const LogFile = ly_core.LogFile;

const enums = @import("../enums.zig");
const DurOffsetAlignment = enums.DurOffsetAlignment;
const Cell = @import("../tui/Cell.zig");
const TerminalBuffer = @import("../tui/TerminalBuffer.zig");
const Color = TerminalBuffer.Color;
const Styling = TerminalBuffer.Styling;
const Widget = @import("../tui/Widget.zig");

fn read_decompress_file(allocator: Allocator, file_path: []const u8) ![]u8 {
    const file_buffer = std.fs.cwd().openFile(file_path, .{}) catch {
        return error.FileNotFound;
    };
    defer file_buffer.close();

    var file_reader_buffer: [4096]u8 = undefined;
    var decompress_buffer: [flate.max_window_len]u8 = undefined;

    var file_reader = file_buffer.reader(&file_reader_buffer);
    var decompress: flate.Decompress = .init(&file_reader.interface, .gzip, &decompress_buffer);

    const file_decompressed = decompress.reader.allocRemaining(allocator, .unlimited) catch {
        return error.NotValidFile;
    };

    return file_decompressed;
}

const Frame = struct {
    frameNumber: i32,
    delay: f32,
    contents: [][]u8,
    colorMap: [][][]i32,

    // allocator must be outside of struct as it will fail the json parser
    pub fn deinit(self: *const Frame, allocator: Allocator) void {
        for (self.contents) |con| {
            allocator.free(con);
        }
        allocator.free(self.contents);

        for (self.colorMap) |cm| {
            for (cm) |int2| {
                allocator.free(int2);
            }
            allocator.free(cm);
        }
        allocator.free(self.colorMap);
    }
};

// https://github.com/cmang/durdraw/blob/0.29.0/durformat.md
const DurFormat = struct {
    allocator: Allocator,
    formatVersion: ?i64 = null,
    colorFormat: ?[]const u8 = null,
    encoding: ?[]const u8 = null,
    framerate: ?f64 = null,
    columns: ?i64 = null,
    lines: ?i64 = null,
    frames: std.ArrayList(Frame) = undefined,

    pub fn valid(self: *DurFormat) bool {
        if (self.formatVersion != null and
            self.colorFormat != null and
            self.encoding != null and
            self.framerate != null and
            self.columns != null and
            self.lines != null and
            self.frames.items.len >= 1)
        {
            // v8 may have breaking changes like changing the colormap xy direction
            // (https://github.com/cmang/durdraw/issues/24)
            if (self.formatVersion.? != 7) return false;

            // Code currently only supports 16 and 256 color format only
            if (!(eql(u8, "16", self.colorFormat.?) or eql(u8, "256", self.colorFormat.?)))
                return false;

            // Code currently supports only utf-8 encoding
            if (!eql(u8, self.encoding.?, "utf-8")) return false;

            // Sanity check on file
            if (self.columns.? <= 0) return false;
            if (self.lines.? <= 0) return false;
            if (self.framerate.? < 0) return false;

            return true;
        }

        return false;
    }

    fn parse_dur_from_json(self: *DurFormat, allocator: Allocator, dur_json_root: Json.Value) !void {
        var dur_movie = if (dur_json_root.object.get("DurMovie")) |dm| dm.object else return error.NotValidFile;

        // Depending on the version, a dur file can have different json object names (ie: columns vs sizeX)
        self.formatVersion = if (dur_movie.get("formatVersion")) |x| x.integer else null;
        self.colorFormat = if (dur_movie.get("colorFormat")) |x| try allocator.dupe(u8, x.string) else null;
        self.encoding = if (dur_movie.get("encoding")) |x| try allocator.dupe(u8, x.string) else null;
        self.framerate = if (dur_movie.get("framerate")) |x| x.float else null;
        self.columns = if (dur_movie.get("columns")) |x| x.integer else if (dur_movie.get("sizeX")) |x| x.integer else null;

        self.lines = if (dur_movie.get("lines")) |x| x.integer else if (dur_movie.get("sizeY")) |x| x.integer else null;

        const frames = dur_movie.get("frames") orelse return error.NotValidFile;

        self.frames = try .initCapacity(allocator, frames.array.items.len);

        for (frames.array.items) |json_frame| {
            var parsed_frame = try Json.parseFromValue(Frame, allocator, json_frame, .{});
            defer parsed_frame.deinit();

            const frame_val = parsed_frame.value;

            // copy all fields to own the ptrs for deallocation, the parsed_frame has some other
            // allocated memory making it difficult to deallocate without leaks
            const frame: Frame = .{ .frameNumber = frame_val.frameNumber, .delay = frame_val.delay, .contents = try allocator.alloc([]u8, frame_val.contents.len), .colorMap = try allocator.alloc([][]i32, frame_val.colorMap.len) };

            for (0..frame.contents.len) |i| {
                frame.contents[i] = try allocator.dupe(u8, frame_val.contents[i]);
            }

            // colorMap is stored as an 3d array where:
            // the outer (i) most array is the horizontal position of the color
            // the middle (j) is the vertical position of the color
            // the inner (0/1) is the foreground/background color
            for (0..frame.colorMap.len) |i| {
                frame.colorMap[i] = try allocator.alloc([]i32, frame_val.colorMap[i].len);
                for (0..frame.colorMap[i].len) |j| {
                    frame.colorMap[i][j] = try allocator.alloc(i32, 2);
                    frame.colorMap[i][j][0] = frame_val.colorMap[i][j][0];
                    frame.colorMap[i][j][1] = frame_val.colorMap[i][j][1];
                }
            }

            try self.frames.append(allocator, frame);
        }
    }

    pub fn create_from_file(self: *DurFormat, allocator: Allocator, file_path: []const u8) !void {
        const file_decompressed = try read_decompress_file(allocator, file_path);
        defer allocator.free(file_decompressed);

        const parsed = try Json.parseFromSlice(Json.Value, allocator, file_decompressed, .{});
        defer parsed.deinit();

        try parse_dur_from_json(self, allocator, parsed.value);

        if (!self.valid()) {
            return error.NotValidFile;
        }
    }

    pub fn init(allocator: Allocator) DurFormat {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *DurFormat) void {
        if (self.colorFormat) |str| self.allocator.free(str);
        if (self.encoding) |str| self.allocator.free(str);

        for (self.frames.items) |frame| {
            frame.deinit(self.allocator);
        }
        self.frames.deinit(self.allocator);
    }
};

const tb_color_16 = [16]u32{
    Color.ECOL_BLACK,
    Color.ECOL_RED,
    Color.ECOL_GREEN,
    Color.ECOL_YELLOW,
    Color.ECOL_BLUE,
    Color.ECOL_MAGENTA,
    Color.ECOL_CYAN,
    Color.ECOL_WHITE,
    Color.ECOL_BLACK | Styling.BOLD,
    Color.ECOL_RED | Styling.BOLD,
    Color.ECOL_GREEN | Styling.BOLD,
    Color.ECOL_YELLOW | Styling.BOLD,
    Color.ECOL_BLUE | Styling.BOLD,
    Color.ECOL_MAGENTA | Styling.BOLD,
    Color.ECOL_CYAN | Styling.BOLD,
    Color.ECOL_WHITE | Styling.BOLD,
};

// Using bold for bright colors allows for all 16 colors to be rendered on tty term
const rgb_color_16 = [16]u32{
    Color.DEFAULT, // DEFAULT instead of TRUE_BLACK to not break compositors (the latter ignores transparency)
    Color.TRUE_DIM_RED,
    Color.TRUE_DIM_GREEN,
    Color.TRUE_DIM_YELLOW,
    Color.TRUE_DIM_BLUE,
    Color.TRUE_DIM_MAGENTA,
    Color.TRUE_DIM_CYAN,
    Color.TRUE_DIM_WHITE,
    Color.DEFAULT | Styling.BOLD,
    Color.TRUE_RED | Styling.BOLD,
    Color.TRUE_GREEN | Styling.BOLD,
    Color.TRUE_YELLOW | Styling.BOLD,
    Color.TRUE_BLUE | Styling.BOLD,
    Color.TRUE_MAGENTA | Styling.BOLD,
    Color.TRUE_CYAN | Styling.BOLD,
    Color.TRUE_WHITE | Styling.BOLD,
};

// Made this table from looking at colormapping in dur source, not sure whats going on with the mapping logic
// Array indexes are dur colormappings which value maps to indexes in table above. Only needed for dur 16 color
const durcolor_table_to_color16 = [17]u32{
    0, // 0 black
    0, // 1 nothing?? dur source did not say why 1 is unused
    4, // 2 blue
    2, // 3 green
    6, // 4 cyan
    1, // 5 red
    5, // 6 magenta
    3, // 7 yellow
    7, // 8 light gray
    8, // 9 gray
    12, // 10 bright blue
    10, // 11 bright green
    14, // 12 bright cyan
    9, // 13 bright red
    13, // 14 bright magenta
    11, // 15 bright yellow
    15, // 16 bright white
};

fn sixcube_to_channel(sixcube: u32) u32 {
    // Although the range top for the extended range is 0xFF, 6 is not divisible into 0xFF,
    // so we use 0xF0 instead with a scaler
    const equal_divisions = 0xF0 / 6;

    // Since the range is to 0xFF but 6 isn't divisible, we must add a scaler to get it to 0xFF at the last index (5)
    const scaler = 0xFF - (equal_divisions * 5);

    return if (sixcube > 0) (sixcube * equal_divisions) + scaler else 0;
}

fn convert_256_to_rgb(color_256: u32) u32 {
    var rgb_color: u32 = 0;

    // 0 - 15 is the standard color range, map to array table
    if (color_256 < 16) {
        rgb_color = rgb_color_16[color_256];
    }
    // 16 - 231 is the extended range
    else if (color_256 < 232) {

        // For extended term range we subtract by 16 to get it in a 0..(6x6x6) cube (range of 216)
        // divide by 36 gets the depth of the cube (6x6x1)
        // divide by 6 gets the width of the cube (6x1)
        // divide by 1 gets the height of the cube (divide 1 for clarity for what we are doing)
        // each channel can be 6 levels of brightness hence remander operation of 6
        // finally bitshift to correct rgb channel (16 for red, 8 for green, 0 for blue)
        rgb_color |= sixcube_to_channel(((color_256 - 16) / 36) % 6) << 16;
        rgb_color |= sixcube_to_channel(((color_256 - 16) / 6) % 6) << 8;
        rgb_color |= sixcube_to_channel(((color_256 - 16) / 1) % 6);
    }
    // 232 - 255 is the grayscale range
    else {

        // For grayscale we have a space of 232 - 255 (24)
        // subtract by 232 to get it into the 0..23 range
        // standard colors will contain white and black, so we do not use them in the grayscale range (0 is 0x08, 23 is 0xEE)
        // this results in a skip of 0x08 for the first color and divisions of 0x0A
        // example: term_col 232 = scaler + equal_divisions * (232 - 232) which becomes (scaler + 0x00) == 0x08
        // example: term_col 255 = scaler + equal_divisions * (255 - 232) which becomes (scaler + 0xE6) == 0xEE
        const scaler = 0x08;

        // to get equal parts, the equation is:
        // 0xEE = equal_divisions * 23 + scaler | top of range is 0xEE, 23 is last element value (255 minus 232)
        // reordered to solve for equal_divisions:
        const equal_divisions = (0xEE - scaler) / 23; // evals to 0x0A

        const channel = scaler + equal_divisions * (color_256 - 232);

        // gray is equal value of same channel color in rgb
        rgb_color = channel | (channel << 8) | (channel << 16);
    }

    return rgb_color;
}

const UVec2 = @Vector(2, u32);
const IVec2 = @Vector(2, i64);

const VEC_X = 0;
const VEC_Y = 1;

const DurFile = @This();

allocator: Allocator,
terminal_buffer: *TerminalBuffer,
dur_movie: DurFormat,
frames: u64,
frame_size: UVec2,
start_pos: IVec2,
full_color: bool,
timeout: *bool,
frame_time: u32,
time_previous: i64,
is_color_format_16: bool,
offset_alignment: DurOffsetAlignment,
offset: IVec2,

// if the user has an even number of columns or rows, we will default to the left or higher position (e.g. 4 columns center = .x..)
fn center(v: u32) i64 {
    return @intCast((v / 2) + (v % 2));
}

fn calc_start_position(terminal_buffer: *TerminalBuffer, dur_movie: *DurFormat, offset_alignment: DurOffsetAlignment, offset: IVec2) IVec2 {
    const buf_width: u32 = @intCast(terminal_buffer.width);
    const buf_height: u32 = @intCast(terminal_buffer.height);

    var movie_width: u32 = @intCast(dur_movie.columns.?);
    var movie_height: u32 = @intCast(dur_movie.lines.?);

    if (movie_width > buf_width) movie_width = buf_width;
    if (movie_height > buf_height) movie_height = buf_height;

    const start_pos: IVec2 = switch (offset_alignment) {
        DurOffsetAlignment.center => .{ center(buf_width) - center(movie_width), center(buf_height) - center(movie_height) },
        DurOffsetAlignment.topleft => .{ 0, 0 },
        DurOffsetAlignment.topcenter => .{ center(buf_width) - center(movie_width), 0 },
        DurOffsetAlignment.topright => .{ buf_width - movie_width, 0 },
        DurOffsetAlignment.centerleft => .{ 0, center(buf_height) - center(movie_height) },
        DurOffsetAlignment.centerright => .{ buf_width - movie_width, center(buf_height) - center(movie_height) },
        DurOffsetAlignment.bottomleft => .{ 0, buf_height - movie_height },
        DurOffsetAlignment.bottomcenter => .{ center(buf_width) - center(movie_width), buf_height - movie_height },
        DurOffsetAlignment.bottomright => .{ buf_width - movie_width, buf_height - movie_height },
    };

    return start_pos + offset;
}

fn calc_frame_size(terminal_buffer: *TerminalBuffer, dur_movie: *DurFormat) UVec2 {
    const buf_width: u32 = @intCast(terminal_buffer.width);
    const buf_height: u32 = @intCast(terminal_buffer.height);

    const movie_width: u32 = @intCast(dur_movie.columns.?);
    const movie_height: u32 = @intCast(dur_movie.lines.?);

    // Draw only the needed amount if movie smaller than screen. If movie is bigger, we will just draw entire screen
    const frame_width = if (movie_width < buf_width) movie_width else buf_width;
    const frame_height = if (movie_height < buf_height) movie_height else buf_height;

    return .{ frame_width, frame_height };
}

pub fn init(
    allocator: Allocator,
    terminal_buffer: *TerminalBuffer,
    log_file: *LogFile,
    file_path: []const u8,
    offset_alignment: DurOffsetAlignment,
    x_offset: i32,
    y_offset: i32,
    full_color: bool,
    timeout: *bool,
) !DurFile {
    var dur_movie: DurFormat = .init(allocator);

    dur_movie.create_from_file(allocator, file_path) catch |err| switch (err) {
        error.FileNotFound => {
            try log_file.err("tui", "dur_file was not found at: {s}", .{file_path});
            return err;
        },
        error.NotValidFile => {
            try log_file.err("tui", "dur_file loaded was invalid or not a dur file!", .{});
            return err;
        },
        else => return err,
    };

    // 4 bit mode with 256 color is unsupported
    if (!full_color and eql(u8, dur_movie.colorFormat.?, "256")) {
        try log_file.err("tui", "dur_file can not be 256 color encoded when not using full_color option!", .{});
        dur_movie.deinit();
        return error.InvalidColorFormat;
    }

    const offset: IVec2 = .{ x_offset, y_offset };

    const start_pos = calc_start_position(terminal_buffer, &dur_movie, offset_alignment, offset);
    const frame_size = calc_frame_size(terminal_buffer, &dur_movie);

    // Convert dur fps to frames per ms
    const frame_time: u32 = @intFromFloat(1000 / dur_movie.framerate.?);

    return .{
        .allocator = allocator,
        .terminal_buffer = terminal_buffer,
        .frames = 0,
        .time_previous = std.time.milliTimestamp(),
        .frame_size = frame_size,
        .start_pos = start_pos,
        .full_color = full_color,
        .timeout = timeout,
        .dur_movie = dur_movie,
        .frame_time = frame_time,
        .is_color_format_16 = eql(u8, dur_movie.colorFormat.?, "16"),
        .offset_alignment = offset_alignment,
        .offset = offset,
    };
}

pub fn widget(self: *DurFile) Widget {
    return Widget.init(
        "DurFile",
        self,
        deinit,
        realloc,
        draw,
        null,
        null,
    );
}

fn deinit(self: *DurFile) void {
    self.dur_movie.deinit();
}

fn realloc(self: *DurFile) !void {
    // when terminal size changes, we need to recalculate the start_pos and frame_size based on the new size
    self.start_pos = calc_start_position(self.terminal_buffer, &self.dur_movie, self.offset_alignment, self.offset);
    self.frame_size = calc_frame_size(self.terminal_buffer, &self.dur_movie);
}

fn draw(self: *DurFile) void {
    if (self.timeout.*) return;

    const current_frame = self.dur_movie.frames.items[self.frames];

    const buf_width: u32 = @intCast(self.terminal_buffer.width);
    const buf_height: u32 = @intCast(self.terminal_buffer.height);

    // y is used as an iterator in the durformat, while cell_y gives us the correct placement for the cell (same for x)
    for (0..self.frame_size[VEC_Y]) |y| {
        const y_offset_i = @as(i32, @intCast(y)) + self.start_pos[VEC_Y];
        // we skip the pass if it falls outside of the draw window (ensure no int underflow)
        const cell_y: u32 = if (y_offset_i >= 0 and y_offset_i < buf_height) @intCast(y_offset_i) else continue;

        var iter = std.unicode.Utf8View.initUnchecked(current_frame.contents[y]).iterator();

        for (0..self.frame_size[VEC_X]) |x| {
            const x_offset_i = @as(i32, @intCast(x)) + self.start_pos[VEC_X];
            // skip pass, same as y but also increment the codepoint iter to fetch correct values in later passes
            const cell_x: u32 = if (x_offset_i >= 0 and x_offset_i < buf_width) @intCast(x_offset_i) else {
                _ = iter.nextCodepoint().?;
                continue;
            };

            const codepoint: u21 = iter.nextCodepoint().?;
            const color_map = current_frame.colorMap[x][y];

            var color_map_0: u32 = @intCast(if (color_map[0] == -1) 0 else color_map[0]);
            var color_map_1: u32 = @intCast(if (color_map[1] == -1) 0 else color_map[1]);

            if (self.is_color_format_16) {
                color_map_0 = durcolor_table_to_color16[color_map_0];
                color_map_1 = durcolor_table_to_color16[color_map_1 + 1]; // Add 1, dur source stores it like this for some reason
            }

            const fg_color = if (self.full_color) convert_256_to_rgb(color_map_0) else tb_color_16[color_map_0];
            const bg_color = if (self.full_color) convert_256_to_rgb(color_map_1) else tb_color_16[color_map_1];

            const cell = Cell{ .ch = @intCast(codepoint), .fg = fg_color, .bg = bg_color };

            cell.put(cell_x, cell_y);
        }
    }

    const time_current = std.time.milliTimestamp();
    const delta_time = time_current - self.time_previous;

    // Convert delay from sec to ms
    const delay_time: u32 = @intFromFloat(current_frame.delay * 1000);
    if (delta_time > (self.frame_time + delay_time)) {
        self.time_previous = time_current;

        const frame_count = self.dur_movie.frames.items.len;
        self.frames = (self.frames + 1) % frame_count;
    }
}
