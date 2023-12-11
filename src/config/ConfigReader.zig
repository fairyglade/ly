const std = @import("std");
const ini = @import("ini");
const Config = @import("Config.zig");
const Lang = @import("Lang.zig");

const Allocator = std.mem.Allocator;

pub const CONFIG_MAX_SIZE: u64 = 8 * 1024;

const ConfigReader = @This();

allocator: Allocator,
config_allocated: bool = false,
lang_allocated: bool = false,
config: []u8 = undefined,
lang: []u8 = undefined,

pub fn init(config_allocator: Allocator) ConfigReader {
    return .{
        .allocator = config_allocator,
    };
}

pub fn deinit(self: ConfigReader) void {
    if (self.config_allocated) self.allocator.free(self.config);
    if (self.lang_allocated) self.allocator.free(self.lang);
}

pub fn readConfig(self: *ConfigReader, path: []const u8) !Config {
    var file = std.fs.cwd().openFile(path, .{}) catch return Config.init();
    defer file.close();

    self.config = try file.readToEndAlloc(self.allocator, CONFIG_MAX_SIZE);
    self.config_allocated = true;

    return try ini.readToStruct(Config, self.config);
}

pub fn readLang(self: *ConfigReader, path: []const u8) !Lang {
    var file = std.fs.cwd().openFile(path, .{}) catch return Lang.init();
    defer file.close();

    self.lang = try file.readToEndAlloc(self.allocator, CONFIG_MAX_SIZE);
    self.lang_allocated = true;

    return try ini.readToStruct(Lang, self.lang);
}
