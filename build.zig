const std = @import("std");
const builtin = @import("builtin");

const PatchMap = std.StringHashMap([]const u8);

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
var config_directory: []const u8 = undefined;
var prefix_directory: []const u8 = undefined;
var executable_name: []const u8 = undefined;
var default_tty_str: []const u8 = undefined;

const ProgressNode = if (current_zig.minor == 12) *std.Progress.Node else std.Progress.Node;

pub fn build(b: *std.Build) !void {
    dest_directory = b.option([]const u8, "dest_directory", "Specify a destination directory for installation") orelse "";
    config_directory = b.option([]const u8, "config_directory", "Specify a default config directory (default is /etc). This path gets embedded into the binary") orelse "/etc";
    prefix_directory = b.option([]const u8, "prefix_directory", "Specify a default prefix directory (default is /usr)") orelse "/usr";
    executable_name = b.option([]const u8, "name", "Specify installed executable file name (default is ly)") orelse "ly";

    const bin_directory = try b.allocator.dupe(u8, config_directory);
    config_directory = try std.fs.path.join(b.allocator, &[_][]const u8{ dest_directory, config_directory });

    const build_options = b.addOptions();
    const version_str = try getVersionStr(b, "ly", ly_version);
    const enable_x11_support = b.option(bool, "enable_x11_support", "Enable X11 support (default is on)") orelse true;
    const default_tty = b.option(u8, "default_tty", "Set the TTY (default is 2)") orelse 2;

    default_tty_str = try std.fmt.allocPrint(b.allocator, "{d}", .{default_tty});

    build_options.addOption([]const u8, "config_directory", bin_directory);
    build_options.addOption([]const u8, "prefix_directory", prefix_directory);
    build_options.addOption([]const u8, "version", version_str);
    build_options.addOption(u8, "tty", default_tty);
    build_options.addOption(bool, "enable_x11_support", enable_x11_support);

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
    if (enable_x11_support) exe.linkSystemLibrary("xcb");
    exe.linkLibC();

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("include/termbox2.h"),
        .target = target,
        .optimize = optimize,
    });
    translate_c.defineCMacroRaw("TB_IMPL");
    const termbox2 = translate_c.addModule("termbox2");
    exe.root_module.addImport("termbox2", termbox2);

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

    const installs6_step = b.step("installs6", "Install the Ly s6 service");
    installs6_step.makeFn = ServiceInstaller(.S6).make;
    installs6_step.dependOn(installexe_step);

    const installdinit_step = b.step("installdinit", "Install the Ly dinit service");
    installdinit_step.makeFn = ServiceInstaller(.Dinit).make;
    installdinit_step.dependOn(installexe_step);

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
    S6,
    Dinit,
};

pub fn ServiceInstaller(comptime init_system: InitSystem) type {
    return struct {
        pub fn make(step: *std.Build.Step, _: ProgressNode) !void {
            const allocator = step.owner.allocator;

            var patch_map = PatchMap.init(allocator);
            defer patch_map.deinit();

            try patch_map.put("$DEFAULT_TTY", default_tty_str);
            try patch_map.put("$CONFIG_DIRECTORY", config_directory);
            try patch_map.put("$PREFIX_DIRECTORY", prefix_directory);
            try patch_map.put("$EXECUTABLE_NAME", executable_name);

            switch (init_system) {
                .Systemd => {
                    const service_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_directory, prefix_directory, "/lib/systemd/system" });
                    std.fs.cwd().makePath(service_path) catch {};
                    var service_dir = std.fs.cwd().openDir(service_path, .{}) catch unreachable;
                    defer service_dir.close();

                    const patched_service = try patchFile(allocator, "res/ly.service", patch_map);
                    try installText(patched_service, service_dir, service_path, "ly.service", .{ .mode = 0o644 });
                },
                .Openrc => {
                    const service_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_directory, config_directory, "/init.d" });
                    std.fs.cwd().makePath(service_path) catch {};
                    var service_dir = std.fs.cwd().openDir(service_path, .{}) catch unreachable;
                    defer service_dir.close();

                    const patched_service = try patchFile(allocator, "res/ly-openrc", patch_map);
                    try installText(patched_service, service_dir, service_path, executable_name, .{ .mode = 0o755 });
                },
                .Runit => {
                    const service_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_directory, config_directory, "/sv/ly" });
                    std.fs.cwd().makePath(service_path) catch {};
                    var service_dir = std.fs.cwd().openDir(service_path, .{}) catch unreachable;
                    defer service_dir.close();

                    const supervise_path = try std.fs.path.join(allocator, &[_][]const u8{ service_path, "supervise" });

                    const patched_conf = try patchFile(allocator, "res/ly-runit-service/conf", patch_map);
                    try installText(patched_conf, service_dir, service_path, "conf", .{});

                    try installFile("res/ly-runit-service/finish", service_dir, service_path, "finish", .{ .override_mode = 0o755 });

                    const patched_run = try patchFile(allocator, "res/ly-runit-service/run", patch_map);
                    try installText(patched_run, service_dir, service_path, "run", .{ .mode = 0o755 });

                    try std.fs.cwd().symLink("/run/runit/supervise.ly", supervise_path, .{});
                    std.debug.print("info: installed symlink /run/runit/supervise.ly\n", .{});
                },
                .S6 => {
                    const admin_service_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_directory, config_directory, "/s6/adminsv/default/contents.d" });
                    std.fs.cwd().makePath(admin_service_path) catch {};
                    var admin_service_dir = std.fs.cwd().openDir(admin_service_path, .{}) catch unreachable;
                    defer admin_service_dir.close();

                    const file = try admin_service_dir.createFile("ly-srv", .{});
                    file.close();

                    const service_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_directory, config_directory, "/s6/sv/ly-srv" });
                    std.fs.cwd().makePath(service_path) catch {};
                    var service_dir = std.fs.cwd().openDir(service_path, .{}) catch unreachable;
                    defer service_dir.close();

                    const patched_run = try patchFile(allocator, "res/ly-s6/run", patch_map);
                    try installText(patched_run, service_dir, service_path, "run", .{ .mode = 0o755 });

                    try installFile("res/ly-s6/type", service_dir, service_path, "type", .{});
                },
                .Dinit => {
                    const service_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_directory, config_directory, "/dinit.d" });
                    std.fs.cwd().makePath(service_path) catch {};
                    var service_dir = std.fs.cwd().openDir(service_path, .{}) catch unreachable;
                    defer service_dir.close();

                    const patched_service = try patchFile(allocator, "res/ly-dinit", patch_map);
                    try installText(patched_service, service_dir, service_path, "ly", .{});
                },
            }
        }
    };
}

fn install_ly(allocator: std.mem.Allocator, install_config: bool) !void {
    const ly_config_directory = try std.fs.path.join(allocator, &[_][]const u8{ config_directory, "/ly" });

    std.fs.cwd().makePath(ly_config_directory) catch {
        std.debug.print("warn: {s} already exists as a directory.\n", .{ly_config_directory});
    };

    const ly_lang_path = try std.fs.path.join(allocator, &[_][]const u8{ config_directory, "/ly/lang" });
    std.fs.cwd().makePath(ly_lang_path) catch {
        std.debug.print("warn: {s} already exists as a directory.\n", .{config_directory});
    };

    {
        const exe_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_directory, prefix_directory, "/bin" });
        if (!std.mem.eql(u8, dest_directory, "")) {
            std.fs.cwd().makePath(exe_path) catch {
                std.debug.print("warn: {s} already exists as a directory.\n", .{exe_path});
            };
        }

        var executable_dir = std.fs.cwd().openDir(exe_path, .{}) catch unreachable;
        defer executable_dir.close();

        try installFile("zig-out/bin/ly", executable_dir, exe_path, executable_name, .{});
    }

    {
        var config_dir = std.fs.cwd().openDir(ly_config_directory, .{}) catch unreachable;
        defer config_dir.close();

        if (install_config) {
            var patch_map = PatchMap.init(allocator);
            defer patch_map.deinit();

            try patch_map.put("$DEFAULT_TTY", default_tty_str);
            try patch_map.put("$CONFIG_DIRECTORY", config_directory);
            try patch_map.put("$PREFIX_DIRECTORY", prefix_directory);

            const patched_config = try patchFile(allocator, "res/config.ini", patch_map);
            try installText(patched_config, config_dir, ly_config_directory, "config.ini", .{});
        }

        {
            var patch_map = PatchMap.init(allocator);
            defer patch_map.deinit();

            try patch_map.put("$CONFIG_DIRECTORY", config_directory);

            const patched_setup = try patchFile(allocator, "res/setup.sh", patch_map);
            try installText(patched_setup, config_dir, ly_config_directory, "setup.sh", .{ .mode = 0o755 });
        }
    }

    {
        var lang_dir = std.fs.cwd().openDir(ly_lang_path, .{}) catch unreachable;
        defer lang_dir.close();

        try installFile("res/lang/cat.ini", lang_dir, ly_lang_path, "cat.ini", .{});
        try installFile("res/lang/cs.ini", lang_dir, ly_lang_path, "cs.ini", .{});
        try installFile("res/lang/de.ini", lang_dir, ly_lang_path, "de.ini", .{});
        try installFile("res/lang/en.ini", lang_dir, ly_lang_path, "en.ini", .{});
        try installFile("res/lang/es.ini", lang_dir, ly_lang_path, "es.ini", .{});
        try installFile("res/lang/fr.ini", lang_dir, ly_lang_path, "fr.ini", .{});
        try installFile("res/lang/it.ini", lang_dir, ly_lang_path, "it.ini", .{});
        try installFile("res/lang/pl.ini", lang_dir, ly_lang_path, "pl.ini", .{});
        try installFile("res/lang/pt.ini", lang_dir, ly_lang_path, "pt.ini", .{});
        try installFile("res/lang/pt_BR.ini", lang_dir, ly_lang_path, "pt_BR.ini", .{});
        try installFile("res/lang/ro.ini", lang_dir, ly_lang_path, "ro.ini", .{});
        try installFile("res/lang/ru.ini", lang_dir, ly_lang_path, "ru.ini", .{});
        try installFile("res/lang/sr.ini", lang_dir, ly_lang_path, "sr.ini", .{});
        try installFile("res/lang/sv.ini", lang_dir, ly_lang_path, "sv.ini", .{});
        try installFile("res/lang/tr.ini", lang_dir, ly_lang_path, "tr.ini", .{});
        try installFile("res/lang/uk.ini", lang_dir, ly_lang_path, "uk.ini", .{});
    }

    {
        const pam_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_directory, config_directory, "/pam.d" });
        if (!std.mem.eql(u8, dest_directory, "")) {
            std.fs.cwd().makePath(pam_path) catch {
                std.debug.print("warn: {s} already exists as a directory.\n", .{pam_path});
            };
        }

        var pam_dir = std.fs.cwd().openDir(pam_path, .{}) catch unreachable;
        defer pam_dir.close();

        try installFile("res/pam.d/ly", pam_dir, pam_path, "ly", .{ .override_mode = 0o644 });
    }
}

pub fn uninstallall(step: *std.Build.Step, _: ProgressNode) !void {
    const allocator = step.owner.allocator;

    try deleteTree(allocator, config_directory, "/ly", "ly config directory not found");

    const exe_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_directory, prefix_directory, "/bin/", executable_name });
    var success = true;
    std.fs.cwd().deleteFile(exe_path) catch {
        std.debug.print("warn: ly executable not found\n", .{});
        success = false;
    };
    if (success) std.debug.print("info: deleted {s}\n", .{exe_path});

    try deleteFile(allocator, config_directory, "/pam.d/ly", "ly pam file not found");
    try deleteFile(allocator, prefix_directory, "/lib/systemd/system/ly.service", "systemd service not found");
    try deleteFile(allocator, config_directory, "/init.d/ly", "openrc service not found");
    try deleteTree(allocator, config_directory, "/sv/ly", "runit service not found");
    try deleteTree(allocator, config_directory, "/s6/sv/ly-srv", "s6 service not found");
    try deleteFile(allocator, config_directory, "/s6/adminsv/default/contents.d/ly-srv", "s6 admin service not found");
    try deleteFile(allocator, config_directory, "/dinit.d/ly", "dinit service not found");
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

fn installFile(
    source_file: []const u8,
    destination_directory: std.fs.Dir,
    destination_directory_path: []const u8,
    destination_file: []const u8,
    options: std.fs.Dir.CopyFileOptions,
) !void {
    try std.fs.cwd().copyFile(source_file, destination_directory, destination_file, options);
    std.debug.print("info: installed {s}/{s}\n", .{ destination_directory_path, destination_file });
}

fn patchFile(allocator: std.mem.Allocator, source_file: []const u8, patch_map: PatchMap) ![]const u8 {
    var file = try std.fs.cwd().openFile(source_file, .{});
    defer file.close();

    const reader = file.reader();
    var text = try reader.readAllAlloc(allocator, std.math.maxInt(u16));

    var iterator = patch_map.iterator();
    while (iterator.next()) |kv| {
        const new_text = try std.mem.replaceOwned(u8, allocator, text, kv.key_ptr.*, kv.value_ptr.*);
        allocator.free(text);
        text = new_text;
    }

    return text;
}

fn installText(
    text: []const u8,
    destination_directory: std.fs.Dir,
    destination_directory_path: []const u8,
    destination_file: []const u8,
    options: std.fs.File.CreateFlags,
) !void {
    var file = try destination_directory.createFile(destination_file, options);
    defer file.close();

    const writer = file.writer();
    try writer.writeAll(text);

    std.debug.print("info: installed {s}/{s}\n", .{ destination_directory_path, destination_file });
}

fn deleteFile(
    allocator: std.mem.Allocator,
    prefix: []const u8,
    file: []const u8,
    warning: []const u8,
) !void {
    const path = try std.fs.path.join(allocator, &[_][]const u8{ dest_directory, prefix, file });

    std.fs.cwd().deleteFile(path) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("warn: {s}\n", .{warning});
            return;
        }

        return err;
    };

    std.debug.print("info: deleted {s}\n", .{path});
}

fn deleteTree(
    allocator: std.mem.Allocator,
    prefix: []const u8,
    directory: []const u8,
    warning: []const u8,
) !void {
    const path = try std.fs.path.join(allocator, &[_][]const u8{ dest_directory, prefix, directory });

    var dir = std.fs.cwd().openDir(path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("warn: {s}\n", .{warning});
            return;
        }

        return err;
    };
    dir.close();

    try std.fs.cwd().deleteTree(path);

    std.debug.print("info: deleted {s}\n", .{path});
}
