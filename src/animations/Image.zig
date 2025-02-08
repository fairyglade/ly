const std = @import("std");
const Allocator = std.mem.Allocator;
const TerminalBuffer = @import("../tui/TerminalBuffer.zig");
const interop = @import("../interop.zig");
const termbox = interop.termbox;
const Image = @This();

allocator: Allocator,
terminal_buffer: *TerminalBuffer,
Text: []const u8,

pub fn init(allocator: Allocator, terminal_buffer: *TerminalBuffer, path: []const u8) !Image {
    var buffer: [100]u8 = undefined;
    const text = try std.fmt.bufPrint(&buffer, "{}X{}", .{terminal_buffer.width, terminal_buffer.height - 1});
    try writeTextToFile("/etc/ly/Dimensions.txt", text);
    const Texto = try readFile(path);
    return .{
        .allocator = allocator,
        .terminal_buffer = terminal_buffer,
        .Text = Texto,
    };
}

pub fn countNewLines(text: []const u8) usize {
    var lines: usize = 0;
    for (text) |c| {
        if (c == '\n') {
            lines += 1;
        }
    }
    return lines;
}

pub fn draw(self: *Image) !void {
    const buf_height = self.terminal_buffer.height - 1;
    const buf_width = self.terminal_buffer.width;
    const Text_size = self.Text.len;
    const Lines_number = countNewLines(self.Text);
    const widthImage = Text_size / Lines_number;
    const widthImageRange = widthImage - 1;
    const maxRow = min(buf_height, Lines_number);
    const maxCol = min(buf_width, widthImageRange);
    for (0..maxRow) |y| {
        for (0..maxCol) |x| {
            const colorText: []const u8 = &[_]u8{ self.Text[(y * widthImage) + x] };
            const color = try std.fmt.parseInt(u16, colorText, 10);
            setPixel(x, y, self.terminal_buffer, color);
        }
    }
}

pub fn setPixel(x: usize, y: usize, terminal_buffer: *TerminalBuffer, color: u16) void {
    if (x >= terminal_buffer.width or y >= terminal_buffer.height) {
        @panic("Coordinates out of bounds of the buffer");
    }

    _ = termbox.tb_set_cell(@intCast(x), @intCast(y + 1), ' ', color + 1, color + 1);
}

pub fn min(a: usize, b: usize) usize {
    if (a < b) {
        return a;
    }
    return b;
}

pub fn readFile(path: []const u8) ![]const u8 {
    var file_path = path;    
    const allocator = std.heap.page_allocator;
    const fs = std.fs;
    const cwd = fs.cwd();
    var flag = false;
    var file = cwd.openFile(file_path, .{ .mode = .read_write}) catch |err| {
        if (err == error.FileNotFound) {
            file_path = "/etc/ly/default_img.lyim";
            flag = true;
            
        }
        return err;
    };
    if (flag){
        file = try cwd.openFile(file_path, .{ .mode = .read_write});
    }

    defer file.close();
    const file_size = (try file.stat()).size;
    const buffer = try allocator.alloc(u8, file_size);
    _ = try file.readAll(buffer);

    const Text_size = buffer.len * 2;
    var Text = try allocator.alloc(u8, Text_size);
    var Index:usize = 0;

    for (buffer) |c| {
        if (c != ' ') { 
            const Nchar: usize = getAsciiChar(c); 
            const NBinary: [6]u8 = getBinary(Nchar - 33);
            const ColorABin: [3]u8 = getBinPart(NBinary, 1);
            const ColorBBin: [3]u8 = getBinPart(NBinary, 2);
            const ColorA: usize = binarytoUsize(ColorABin);
            const ColorB: usize = binarytoUsize(ColorBBin);
            Text[Index] = UsizeToU8(ColorA);
            Index += 1;
            Text[Index] = UsizeToU8(ColorB);
            Index += 1;
        }else{
            Text[Index] = '\n';
            Index += 1;
        }
    }

    return Text[0..Index];

}

pub fn writeTextToFile(file_path: []const u8, text: []const u8) !void {
    var file = try std.fs.cwd().createFile(file_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(text);
}

pub fn getAsciiChar(char: u8) usize {
    const ascii_table = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";
    var index: usize = 0;
    while (index < ascii_table.len) {
        if (ascii_table[index] == char) {
            return index + 32;
        }
        index += 1;
    }
    return 0;
}


pub fn getBinary(N: usize) [6]u8 {
    var binary: [6]u8 = undefined;
    var num: usize = N;
    var index: usize = 6;
    while (num > 1) {
        if (num % 2 == 0) {
            binary[index-1] = '0';
        } else {
            binary[index-1] = '1';
        }


        num = num / 2;
        index -= 1;
    }
    if (num == 0) {
        binary[index-1] = '0';
    } else {
        binary[index-1] = '1';
    }
    
    index -= 1;
    while (index > 0) {
        binary[index-1] = '0';
        index -= 1;
    }

    

    return binary;
}

pub fn getBinPart(Bin: [6]u8, part:usize) [3]u8{
    var binary: [3]u8 = undefined;
    if (part == 1){
        binary[0] = Bin[0];
        binary[1] = Bin[1];
        binary[2] = Bin[2];
    }else{
        binary[0] = Bin[3];
        binary[1] = Bin[4];
        binary[2] = Bin[5];
    }
    return binary;
}

pub fn UsizeToU8(dec: usize) u8{
     
    if(dec == 0){
        return '0';
    }else if(dec == 1){
        return '1';
    }else if(dec == 2){
        return '2';
    }else if(dec == 3){
        return '3';
    }else if(dec == 4){
        return '4';
    }else if(dec == 5){
        return '5';
    }else if(dec == 6){
        return '6';
    }else if(dec == 7){
        return '7';
    }else if(dec == 8){
        return '8';
    }else if(dec == 9){
        return '9';
    }else{
        return '0';
    }

}

pub fn binarytoUsize(slice: [3]u8) usize {
    var result: usize = 0;
    for (slice) |bit| {
        result = result * 2 + (bit-48);
    }
    return result;
}
