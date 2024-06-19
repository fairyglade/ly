const std = @import("std");

const ly_version = std.SemanticVersion{ .major = 1, .minor = 0, .patch = 0, .build = "dev" };

pub fn build(b: *std.Build) void {
    const data_directory = b.option([]const u8, "data_directory", "Specify a default data directory (default is /etc/ly)");

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "data_directory", data_directory orelse "/etc/ly");
    const version_str = b.fmt("{d}.{d}.{d}-{s}", .{ ly_version.major, ly_version.minor, ly_version.patch, ly_version.build.? });

    build_options.addOption([]const u8, "version", version_str);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const c_args = [_][]const u8{
        "-std=c99",
        "-pedantic",
        "-g",
        "-Wall",
        "-Wextra",
        "-Werror=vla",
        "-Wno-unused-parameter",
        "-D_DEFAULT_SOURCE",
        "-D_POSIX_C_SOURCE=200809L",
        "-D_XOPEN_SOURCE",
    };

    const exe = b.addExecutable(.{
        .name = "ly",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const zigini = b.dependency("zigini", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("zigini", zigini.module("zigini"));

    exe.root_module.addOptions("build_options", build_options);

    const clap = b.dependency("clap", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("clap", clap.module("clap"));

    exe.linkSystemLibrary("pam");
    exe.linkSystemLibrary("xcb");
    exe.linkLibC();

    exe.addIncludePath(.{ .path = "dep/termbox_next/src" });

    exe.addCSourceFile(.{ .file = .{ .path = "dep/termbox_next/src/input.c" }, .flags = &c_args });
    exe.addCSourceFile(.{ .file = .{ .path = "dep/termbox_next/src/memstream.c" }, .flags = &c_args });
    exe.addCSourceFile(.{ .file = .{ .path = "dep/termbox_next/src/ringbuffer.c" }, .flags = &c_args });
    exe.addCSourceFile(.{ .file = .{ .path = "dep/termbox_next/src/term.c" }, .flags = &c_args });
    exe.addCSourceFile(.{ .file = .{ .path = "dep/termbox_next/src/termbox.c" }, .flags = &c_args });
    exe.addCSourceFile(.{ .file = .{ .path = "dep/termbox_next/src/utf8.c" }, .flags = &c_args });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const installexe_step = b.step("installexe", "Install Ly");
    installexe_step.makeFn = installexe;
    installexe_step.dependOn(b.getInstallStep());

    const installnoconf_step = b.step("installnoconf", "Install Ly without its configuration file");
    installnoconf_step.makeFn = installnoconf;
    installnoconf_step.dependOn(b.getInstallStep());

    const installsystemd_step = b.step("installsystemd", "Install the Ly systemd service");
    installsystemd_step.makeFn = installsystemd;
    installsystemd_step.dependOn(installexe_step);

    const installopenrc_step = b.step("installopenrc", "Install the Ly openrc service");
    installopenrc_step.makeFn = installopenrc;
    installopenrc_step.dependOn(installexe_step);

    const installrunit_step = b.step("installrunit", "Install the Ly runit service");
    installrunit_step.makeFn = installrunit;
    installrunit_step.dependOn(installexe_step);

    const uninstallall_step = b.step("uninstallall", "Uninstall Ly and all services");
    uninstallall_step.makeFn = uninstallall;
}

fn installexe(self: *std.Build.Step, progress: *std.Progress.Node) !void {
    _ = progress;
    _ = self;

    try install_ly(true);
}

fn installnoconf(self: *std.Build.Step, progress: *std.Progress.Node) !void {
    _ = progress;
    _ = self;

    try install_ly(false);
}

fn installsystemd(self: *std.Build.Step, progress: *std.Progress.Node) !void {
    _ = progress;
    _ = self;

    var service_dir = std.fs.openDirAbsolute("/usr/lib/systemd/system", .{}) catch unreachable;
    defer service_dir.close();

    try std.fs.cwd().copyFile("res/ly@.service", service_dir, "ly@.service", .{ .override_mode = 644 });
}

fn installopenrc(self: *std.Build.Step, progress: *std.Progress.Node) !void {
    _ = progress;
    _ = self;

    var service_dir = std.fs.openDirAbsolute("/etc/init.d", .{}) catch unreachable;
    defer service_dir.close();

    try std.fs.cwd().copyFile("res/ly-openrc", service_dir, "ly", .{ .override_mode = 755 });
}

fn installrunit(self: *std.Build.Step, progress: *std.Progress.Node) !void {
    _ = progress;
    _ = self;

    var service_dir = std.fs.openDirAbsolute("/etc/sv", .{}) catch unreachable;
    defer service_dir.close();

    std.fs.makeDirAbsolute("/etc/sv/ly") catch {
        std.debug.print("warn: /etc/sv/ly already exists as a directory.\n", .{});
    };

    var ly_service_dir = std.fs.openDirAbsolute("/etc/sv/ly", .{}) catch unreachable;
    defer ly_service_dir.close();

    try std.fs.cwd().copyFile("res/ly-runit-service/conf", ly_service_dir, "conf", .{});
    try std.fs.cwd().copyFile("res/ly-runit-service/finish", ly_service_dir, "finish", .{});
    try std.fs.cwd().copyFile("res/ly-runit-service/run", ly_service_dir, "run", .{});
}

fn uninstallall(self: *std.Build.Step, progress: *std.Progress.Node) !void {
    _ = progress;
    _ = self;

    try std.fs.deleteTreeAbsolute("/etc/ly");
    try std.fs.deleteFileAbsolute("/usr/bin/ly");
    try std.fs.deleteFileAbsolute("/etc/pam.d/ly");
    std.fs.deleteFileAbsolute("/usr/lib/systemd/system/ly.service") catch {
        std.debug.print("warn: systemd service not found.\n", .{});
    };
    std.fs.deleteFileAbsolute("/etc/init.d/ly") catch {
        std.debug.print("warn: openrc service not found.\n", .{});
    };
    std.fs.deleteTreeAbsolute("/etc/sv/ly") catch {
        std.debug.print("warn: runit service not found.\n", .{});
    };
}

fn install_ly(install_config: bool) !void {
    std.fs.makeDirAbsolute("/etc/ly") catch {
        std.debug.print("warn: /etc/ly already exists as a directory.\n", .{});
    };

    std.fs.makeDirAbsolute("/etc/ly/lang") catch {
        std.debug.print("warn: /etc/ly/lang already exists as a directory.\n", .{});
    };

    var current_dir = std.fs.cwd();

    {
        var executable_dir = std.fs.openDirAbsolute("/usr/bin", .{}) catch unreachable;
        defer executable_dir.close();

        try current_dir.copyFile("zig-out/bin/ly", executable_dir, "ly", .{});
    }

    {
        var config_dir = std.fs.openDirAbsolute("/etc/ly", .{}) catch unreachable;
        defer config_dir.close();

        if (install_config) {
            try current_dir.copyFile("res/config.ini", config_dir, "config.ini", .{});
        }
        try current_dir.copyFile("res/xsetup.sh", config_dir, "xsetup.sh", .{});
        try current_dir.copyFile("res/wsetup.sh", config_dir, "wsetup.sh", .{});
    }

    {
        var lang_dir = std.fs.openDirAbsolute("/etc/ly/lang", .{}) catch unreachable;
        defer lang_dir.close();

        try current_dir.copyFile("res/lang/cat.ini", lang_dir, "cat.ini", .{});
        try current_dir.copyFile("res/lang/cs.ini", lang_dir, "cs.ini", .{});
        try current_dir.copyFile("res/lang/de.ini", lang_dir, "de.ini", .{});
        try current_dir.copyFile("res/lang/en.ini", lang_dir, "en.ini", .{});
        try current_dir.copyFile("res/lang/es.ini", lang_dir, "es.ini", .{});
        try current_dir.copyFile("res/lang/fr.ini", lang_dir, "fr.ini", .{});
        try current_dir.copyFile("res/lang/it.ini", lang_dir, "it.ini", .{});
        try current_dir.copyFile("res/lang/pl.ini", lang_dir, "pl.ini", .{});
        try current_dir.copyFile("res/lang/pt.ini", lang_dir, "pt.ini", .{});
        try current_dir.copyFile("res/lang/pt_BR.ini", lang_dir, "pt_BR.ini", .{});
        try current_dir.copyFile("res/lang/ro.ini", lang_dir, "ro.ini", .{});
        try current_dir.copyFile("res/lang/ru.ini", lang_dir, "ru.ini", .{});
        try current_dir.copyFile("res/lang/sr.ini", lang_dir, "sr.ini", .{});
        try current_dir.copyFile("res/lang/sv.ini", lang_dir, "sv.ini", .{});
        try current_dir.copyFile("res/lang/tr.ini", lang_dir, "tr.ini", .{});
        try current_dir.copyFile("res/lang/uk.ini", lang_dir, "uk.ini", .{});
    }

    {
        var pam_dir = std.fs.openDirAbsolute("/etc/pam.d", .{}) catch unreachable;
        defer pam_dir.close();

        try current_dir.copyFile("res/pam.d/ly", pam_dir, "ly", .{ .override_mode = 644 });
    }
}
