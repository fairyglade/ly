const std = @import("std");
const Translator = @import("translate_c").Translator;

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

    const translate_c_dep = b.dependency("translate_c", .{
        .target = target,
        .optimize = optimize,
    });

    const termbox2: Translator = .init(translate_c_dep, .{
        .c_source_file = termbox_dep.path("termbox2.h"),
        .target = target,
        .optimize = optimize,
    });
    termbox2.defineCMacro("TB_IMPL", null);
    // TODO 0.16.0: Workaround until Aro gets better...
    // https://codeberg.org/ziglang/translate-c/issues/319
    termbox2.defineCMacro("_XOPEN_SOURCE", "700");
    termbox2.defineCMacro("TB_OPT_ATTR_W", "32"); // Enable 24-bit color support + styling (32-bit)
    // TODO 0.16.0: Including <fcntl.h> with -OReleaseSafe causes
    // __attribute__(__error__()) to be called. Below
    // is the workaround.
    termbox2.defineCMacro("_FORTIFY_SOURCE", "0");
    // TODO 0.16.0: Needed for now
    if (target.result.os.tag == .freebsd) {
        termbox2.defineCMacro("__BSD_VISIBLE", "1");
    }
    mod.addImport("termbox2", termbox2.mod);

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
