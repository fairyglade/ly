const std = @import("std");

var data_directory: []const u8 = undefined;
var exe_name: []const u8 = undefined;
const ly_version = std.SemanticVersion{ .major = 1, .minor = 0, .patch = 0, .build = "dev" };

pub fn build(b: *std.Build) void {
    data_directory = b.option([]const u8, "data_directory", "Specify a default data directory (default is /etc/ly)") orelse "/etc/ly";
    exe_name = b.option([]const u8, "name", "Specify installed executable file name (default is ly)") orelse "ly";

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "data_directory", data_directory);
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
    installexe_step.makeFn = ExeInstaller(true).make;
    installexe_step.dependOn(b.getInstallStep());

    const installnoconf_step = b.step("installnoconf", "Install Ly without its configuration file");
    installnoconf_step.makeFn = ExeInstaller(false).make;
    installnoconf_step.dependOn(b.getInstallStep());

    const installsystemd_step = b.step("installsystemd", "Install the Ly systemd service");
    installsystemd_step.makeFn = ServiceInstaller(.Systemd).make;
    installsystemd_step.dependOn(installexe_step);

    const installopenrc_step = b.step("installopenrc", "Install the Ly openrc service");
    installopenrc_step.makeFn = ServiceInstaller(.Openrc).make;
    installopenrc_step.dependOn(installexe_step);

    const installrunit_step = b.step("installrunit", "Install the Ly runit service");
    installrunit_step.makeFn = ServiceInstaller(.Runit).make;
    installrunit_step.dependOn(installexe_step);

    const uninstallall_step = b.step("uninstallall", "Uninstall Ly and all services");
    uninstallall_step.makeFn = uninstallall;
}

pub fn ExeInstaller(install_conf: bool) type {
    return struct {
        pub fn make(step: *std.Build.Step, progress: *std.Progress.Node) !void {
            _ = progress;
            try install_ly(step.owner.allocator, install_conf);
        }
    };
}

const InitSystem = enum {
    Systemd,
    Openrc,
    Runit,
};
pub fn ServiceInstaller(comptime init_system: InitSystem) type {
    return struct {
        pub fn make(step: *std.Build.Step, progress: *std.Progress.Node) !void {
            _ = progress;
            _ = step;
            switch (init_system) {
                .Openrc => {
                    var service_dir = std.fs.openDirAbsolute("/etc/init.d", .{}) catch unreachable;
                    defer service_dir.close();

                    try std.fs.cwd().copyFile("res/ly-openrc", service_dir, "ly", .{ .override_mode = 755 });
                },
                .Runit => {
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
                },
                .Systemd => {
                    var service_dir = std.fs.openDirAbsolute("/usr/lib/systemd/system", .{}) catch unreachable;
                    defer service_dir.close();

                    try std.fs.cwd().copyFile("res/ly.service", service_dir, "ly.service", .{ .override_mode = 644 });
                },
            }
        }
    };
}

fn install_ly(allocator: std.mem.Allocator, install_config: bool) !void {
    std.fs.makeDirAbsolute(data_directory) catch {
        std.debug.print("warn: {s} already exists as a directory.\n", .{data_directory});
    };

    const lang_path = try std.fmt.allocPrint(allocator, "{s}/lang", .{data_directory});
    defer allocator.free(lang_path);
    std.fs.makeDirAbsolute(lang_path) catch {
        std.debug.print("warn: {s} already exists as a directory.\n", .{lang_path});
    };

    var current_dir = std.fs.cwd();

    {
        var executable_dir = std.fs.openDirAbsolute("/usr/bin", .{}) catch unreachable;
        defer executable_dir.close();

        try current_dir.copyFile("zig-out/bin/ly", executable_dir, exe_name, .{});
    }

    {
        var config_dir = std.fs.openDirAbsolute(data_directory, .{}) catch unreachable;
        defer config_dir.close();

        if (install_config) {
            try current_dir.copyFile("res/config.ini", config_dir, "config.ini", .{});
        }
        try current_dir.copyFile("res/xsetup.sh", config_dir, "xsetup.sh", .{});
        try current_dir.copyFile("res/wsetup.sh", config_dir, "wsetup.sh", .{});
    }

    {
        var lang_dir = std.fs.openDirAbsolute(lang_path, .{}) catch unreachable;
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

pub fn uninstallall(step: *std.Build.Step, progress: *std.Progress.Node) !void {
    _ = progress;
    try std.fs.deleteTreeAbsolute(data_directory);
    const exe_path = try std.fmt.allocPrint(step.owner.allocator, "/usr/bin/{s}", .{exe_name});
    defer step.owner.allocator.free(exe_path);
    try std.fs.deleteFileAbsolute(exe_path);
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
