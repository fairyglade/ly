const std = @import("std");
const builtin = @import("builtin");

const min_zig_string = "0.12.0";
const current_zig = builtin.zig_version;

// Implementing zig version detection through compile time
comptime {
    const min_zig = std.SemanticVersion.parse(min_zig_string) catch unreachable;
    if (current_zig.order(min_zig) == .lt) {
        @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ current_zig, min_zig }));
    }
}

const ly_version = std.SemanticVersion{ .major = 1, .minor = 1, .patch = 0 };
var dest_directory: []const u8 = undefined;
var data_directory: []const u8 = undefined;
var default_tty: u8 = undefined;
var exe_name: []const u8 = undefined;

const ProgressNode = if (current_zig.minor == 12) *std.Progress.Node else std.Progress.Node;

pub fn build(b: *std.Build) !void {
    dest_directory = b.option([]const u8, "dest_directory", "Specify a destination directory for installation") orelse "";
    data_directory = b.option([]const u8, "data_directory", "Specify a default data directory (default is /etc/ly). This path gets embedded into the binary") orelse "/etc/ly";
    default_tty = b.option(u8, "default_tty", "set default TTY") orelse 2;

    exe_name = b.option([]const u8, "name", "Specify installed executable file name (default is ly)") orelse "ly";

    const bin_directory = try b.allocator.dupe(u8, data_directory);
    data_directory = try std.fs.path.join(b.allocator, &[_][]const u8{ dest_directory, data_directory });

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "data_directory", bin_directory);

    const version_str = try getVersionStr(b, "ly", ly_version);

    build_options.addOption([]const u8, "version", version_str);

    build_options.addOption(u8, "tty", default_tty);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "ly",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zigini = b.dependency("zigini", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("zigini", zigini.module("zigini"));

    exe.root_module.addOptions("build_options", build_options);

    const clap = b.dependency("clap", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("clap", clap.module("clap"));

    exe.addIncludePath(b.path("include"));
    exe.linkSystemLibrary("pam");
    exe.linkSystemLibrary("xcb");
    exe.linkLibC();

    // HACK: Only fails with ReleaseSafe, so we'll override it.
    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("include/termbox2.h"),
        .target = target,
        .optimize = if (optimize == .ReleaseSafe) .ReleaseFast else optimize,
    });
    translate_c.defineCMacroRaw("TB_IMPL");
    const termbox2 = translate_c.addModule("termbox2");
    exe.root_module.addImport("termbox2", termbox2);

    if (optimize == .ReleaseSafe) {
        std.debug.print("warn: termbox2 module is being built in ReleaseFast due to a bug.\n", .{});
    }

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
        pub fn make(step: *std.Build.Step, _: ProgressNode) !void {
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
        pub fn make(step: *std.Build.Step, _: ProgressNode) !void {
            const allocator = step.owner.allocator;
            switch (init_system) {
                .Openrc => {
                    const service_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_directory, "/etc/init.d" });
                    std.fs.cwd().makePath(service_path) catch {};
                    var service_dir = std.fs.cwd().openDir(service_path, .{}) catch unreachable;
                    defer service_dir.close();

                    try std.fs.cwd().copyFile("res/ly-openrc", service_dir, exe_name, .{ .override_mode = 0o755 });
                },
                .Runit => {
                    const service_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_directory, "/etc/sv/ly" });
                    std.fs.cwd().makePath(service_path) catch {};
                    var service_dir = std.fs.cwd().openDir(service_path, .{}) catch unreachable;
                    defer service_dir.close();

                    try std.fs.cwd().copyFile("res/ly-runit-service/conf", service_dir, "conf", .{});
                    try std.fs.cwd().copyFile("res/ly-runit-service/finish", service_dir, "finish", .{ .override_mode = 0o755 });
                    try std.fs.cwd().copyFile("res/ly-runit-service/run", service_dir, "run", .{ .override_mode = 0o755 });
                },
                .Systemd => {
                    const service_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_directory, "/usr/lib/systemd/system" });
                    std.fs.cwd().makePath(service_path) catch {};
                    var service_dir = std.fs.cwd().openDir(service_path, .{}) catch unreachable;
                    defer service_dir.close();

                    try std.fs.cwd().copyFile("res/ly.service", service_dir, "ly.service", .{ .override_mode = 0o644 });
                },
            }
        }
    };
}

fn install_ly(allocator: std.mem.Allocator, install_config: bool) !void {
    std.fs.cwd().makePath(data_directory) catch {
        std.debug.print("warn: {s} already exists as a directory.\n", .{data_directory});
    };

    const lang_path = try std.fs.path.join(allocator, &[_][]const u8{ data_directory, "/lang" });
    std.fs.cwd().makePath(lang_path) catch {
        std.debug.print("warn: {s} already exists as a directory.\n", .{data_directory});
    };

    var current_dir = std.fs.cwd();

    {
        const exe_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_directory, "/usr/bin" });
        if (!std.mem.eql(u8, dest_directory, "")) {
            std.fs.cwd().makePath(exe_path) catch {
                std.debug.print("warn: {s} already exists as a directory.\n", .{exe_path});
            };
        }

        var executable_dir = std.fs.cwd().openDir(exe_path, .{}) catch unreachable;
        defer executable_dir.close();

        try current_dir.copyFile("zig-out/bin/ly", executable_dir, exe_name, .{});
    }

    {
        var config_dir = std.fs.cwd().openDir(data_directory, .{}) catch unreachable;
        defer config_dir.close();

        if (install_config) {
            try current_dir.copyFile("res/config.ini", config_dir, "config.ini", .{});
        }
        try current_dir.copyFile("res/xsetup.sh", config_dir, "xsetup.sh", .{});
        try current_dir.copyFile("res/wsetup.sh", config_dir, "wsetup.sh", .{});
    }

    {
        var lang_dir = std.fs.cwd().openDir(lang_path, .{}) catch unreachable;
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
        const pam_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_directory, "/etc/pam.d" });
        if (!std.mem.eql(u8, dest_directory, "")) {
            std.fs.cwd().makePath(pam_path) catch {
                std.debug.print("warn: {s} already exists as a directory.\n", .{pam_path});
            };
        }

        var pam_dir = std.fs.cwd().openDir(pam_path, .{}) catch unreachable;
        defer pam_dir.close();

        try current_dir.copyFile("res/pam.d/ly", pam_dir, "ly", .{ .override_mode = 0o644 });
    }
}

pub fn uninstallall(step: *std.Build.Step, _: ProgressNode) !void {
    try std.fs.cwd().deleteTree(data_directory);
    const allocator = step.owner.allocator;

    const exe_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_directory, "/usr/bin/", exe_name });
    try std.fs.cwd().deleteFile(exe_path);

    const pam_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_directory, "/etc/pam.d/ly" });
    try std.fs.cwd().deleteFile(pam_path);

    const systemd_service_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_directory, "/usr/lib/systemd/system/ly.service" });
    std.fs.cwd().deleteFile(systemd_service_path) catch {
        std.debug.print("warn: systemd service not found.\n", .{});
    };

    const openrc_service_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_directory, "/etc/init.d/ly" });
    std.fs.cwd().deleteFile(openrc_service_path) catch {
        std.debug.print("warn: openrc service not found.\n", .{});
    };

    const runit_service_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_directory, "/etc/sv/ly" });
    std.fs.cwd().deleteTree(runit_service_path) catch {
        std.debug.print("warn: runit service not found.\n", .{});
    };
}

fn getVersionStr(b: *std.Build, name: []const u8, version: std.SemanticVersion) ![]const u8 {
    const version_str = b.fmt("{d}.{d}.{d}", .{ version.major, version.minor, version.patch });

    var status: u8 = undefined;
    const git_describe_raw = b.runAllowFail(&[_][]const u8{
        "git",
        "-C",
        b.build_root.path orelse ".",
        "describe",
        "--match",
        "*.*.*",
        "--tags",
    }, &status, .Ignore) catch {
        return version_str;
    };
    var git_describe = std.mem.trim(u8, git_describe_raw, " \n\r");
    git_describe = std.mem.trimLeft(u8, git_describe, "v");

    switch (std.mem.count(u8, git_describe, "-")) {
        0 => {
            if (!std.mem.eql(u8, version_str, git_describe)) {
                std.debug.print("{s} version '{s}' does not match git tag: '{s}'\n", .{ name, version_str, git_describe });
                std.process.exit(1);
            }
            return version_str;
        },
        2 => {
            // Untagged development build (e.g. 0.10.0-dev.2025+ecf0050a9).
            var it = std.mem.splitScalar(u8, git_describe, '-');
            const tagged_ancestor = std.mem.trimLeft(u8, it.first(), "v");
            const commit_height = it.next().?;
            const commit_id = it.next().?;

            const ancestor_ver = try std.SemanticVersion.parse(tagged_ancestor);
            if (version.order(ancestor_ver) != .gt) {
                std.debug.print("{s} version '{}' must be greater than tagged ancestor '{}'\n", .{ name, version, ancestor_ver });
                std.process.exit(1);
            }

            // Check that the commit hash is prefixed with a 'g' (a Git convention).
            if (commit_id.len < 1 or commit_id[0] != 'g') {
                std.debug.print("Unexpected `git describe` output: {s}\n", .{git_describe});
                return version_str;
            }

            // The version is reformatted in accordance with the https://semver.org specification.
            return b.fmt("{s}-dev.{s}+{s}", .{ version_str, commit_height, commit_id[1..] });
        },
        else => {
            std.debug.print("Unexpected `git describe` output: {s}\n", .{git_describe});
            return version_str;
        },
    }
}
