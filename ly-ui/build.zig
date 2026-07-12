const std = @import("std");
const Translator = @import("translate_c").Translator;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const enable_x11_support = b.option(bool, "enable_x11_support", "Enable X11 support") orelse true;
    const mod = b.addModule("ly-ui", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const fallback_uid_min = b.option(std.posix.uid_t, "fallback_uid_min", "Set the fallback minimum UID (default is 1000). This value gets embedded into the binary");
    const fallback_uid_max = b.option(std.posix.uid_t, "fallback_uid_max", "Set the fallback maximum UID (default is 60000). This value gets embedded into the binary");

    const ly_core = b.dependency("ly_core", .{
        .target = target,
        .optimize = optimize,
        .enable_x11_support = enable_x11_support,
        .fallback_uid_min = fallback_uid_min,
        .fallback_uid_max = fallback_uid_max,
    });
    mod.addImport("ly-core", ly_core.module("ly-core"));

    const termbox_dep = b.dependency("termbox2", .{
        .target = target,
        .optimize = optimize,
    });

    const translate_c_dep = b.dependency("translate_c", .{
        .target = target,
    });

    const termbox2: Translator = .init(translate_c_dep, .{
        .c_source_file = termbox_dep.path("termbox2.h"),
        .target = target,
        .optimize = optimize,
    });
    termbox2.defineCMacro("TB_IMPL", null);
    termbox2.defineCMacro("TB_OPT_ATTR_W", "32"); // Enable 24-bit color support + styling (32-bit)
    mod.addImport("termbox2", termbox2.mod);

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
