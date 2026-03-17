const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("ly-ui", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ly_core = b.dependency("ly_core", .{ .target = target, .optimize = optimize });
    mod.addImport("ly-core", ly_core.module("ly-core"));

    const termbox_dep = b.dependency("termbox2", .{
        .target = target,
        .optimize = optimize,
    });

    const translate_c = b.addTranslateC(.{
        .root_source_file = termbox_dep.path("termbox2.h"),
        .target = target,
        .optimize = optimize,
    });
    translate_c.defineCMacroRaw("TB_IMPL");
    translate_c.defineCMacro("TB_OPT_ATTR_W", "32"); // Enable 24-bit color support + styling (32-bit)
    const termbox2 = translate_c.addModule("termbox2");
    mod.addImport("termbox2", termbox2);

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
