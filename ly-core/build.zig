const std = @import("std");
const Translator = @import("translate_c").Translator;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const enable_x11_support = b.option(bool, "enable_x11_support", "Enable X11 support") orelse true;
    const mod = b.addModule("ly-core", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zigini = b.dependency("zigini", .{ .target = target, .optimize = optimize });
    mod.addImport("zigini", zigini.module("zigini"));

    const translate_c = b.dependency("translate_c", .{
        .target = target,
        .optimize = optimize,
    });

    addCImport(b, mod, translate_c, target, optimize, "pam", "#include <security/pam_appl.h>");
    addCImport(b, mod, translate_c, target, optimize, "utmp", "#include <utmpx.h>");
    if (enable_x11_support) {
        addCImport(b, mod, translate_c, target, optimize, "xcb", "#include <xcb/xcb.h>");
    }
    if (target.result.os.tag == .freebsd) {
        addCImport(b, mod, translate_c, target, optimize, "pwd",
            \\#include <pwd.h>
            \\#include <sys/types.h>
            \\#include <login_cap.h>
        );
    } else {
        addCImport(b, mod, translate_c, target, optimize, "pwd", "#include <pwd.h>");
    }
    addCImport(b, mod, translate_c, target, optimize, "stdlib", "#include <stdlib.h>");
    addCImport(b, mod, translate_c, target, optimize, "unistd", "#include <unistd.h>");
    addCImport(b, mod, translate_c, target, optimize, "grp", "#include <grp.h>");
    addCImport(b, mod, translate_c, target, optimize, "system_time", "#include <sys/time.h>");
    addCImport(b, mod, translate_c, target, optimize, "time", "#include <time.h>");

    if (target.result.os.tag == .linux) {
        addCImport(b, mod, translate_c, target, optimize, "kd", "#include <sys/kd.h>");
        addCImport(b, mod, translate_c, target, optimize, "vt", "#include <sys/vt.h>");
    } else if (target.result.os.tag == .freebsd) {
        addCImport(b, mod, translate_c, target, optimize, "kbio", "#include <sys/kbio.h>");
        addCImport(b, mod, translate_c, target, optimize, "consio", "#include <sys/consio.h>");
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}

fn addCImport(
    b: *std.Build,
    mod: *std.Build.Module,
    translate_c: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    comptime name: []const u8,
    comptime bytes: []const u8,
) void {
    const pam: Translator = .init(translate_c, .{
        .c_source_file = b.addWriteFiles().add(name ++ ".h", bytes),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport(name, pam.mod);
}
