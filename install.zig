const std = @import("std");

const PatchMap = std.StringHashMap([]const u8);
const InitSystem = enum {
    systemd,
    openrc,
    runit,
    s6,
    dinit,
    sysvinit,
    freebsd,
};
const InstallType = enum {
    installexe,
    installnoconf,
    uninstallexe,
    uninstallnoconf,
};

var dest_directory: []const u8 = undefined;
var config_directory: []const u8 = undefined;
var prefix_directory: []const u8 = undefined;
var executable_name: []const u8 = undefined;
var init_system: InitSystem = undefined;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var args = init.minimal.args.iterate();
    if (!args.skip()) return error.NoProgramName;

    const install_type = std.meta.stringToEnum(InstallType, args.next().?).?;
    dest_directory = args.next().?;
    config_directory = args.next().?;
    prefix_directory = args.next().?;
    executable_name = args.next().?;
    init_system = std.meta.stringToEnum(InitSystem, args.next().?).?;
    const default_tty_str = args.next().?;

    switch (install_type) {
        .installexe, .installnoconf => {
            var patch_map = PatchMap.init(allocator);
            defer patch_map.deinit();

            try patch_map.put("$DEFAULT_TTY", default_tty_str);
            try patch_map.put("$CONFIG_DIRECTORY", config_directory);
            try patch_map.put("$PREFIX_DIRECTORY", prefix_directory);
            try patch_map.put("$EXECUTABLE_NAME", executable_name);

            try installLy(allocator, io, patch_map, install_type == .installexe);
            try installService(allocator, io, patch_map);
        },
        .uninstallexe, .uninstallnoconf => {
            if (install_type == .uninstallexe) {
                try deleteTree(allocator, io, config_directory, "/ly", "ly config directory not found");
            }

            const exe_path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ prefix_directory, "/bin/", executable_name });
            defer allocator.free(exe_path);

            var success = true;
            std.Io.Dir.cwd().deleteFile(io, exe_path) catch {
                std.debug.print("warn: ly executable not found\n", .{});
                success = false;
            };
            if (success) std.debug.print("info: deleted {s}\n", .{exe_path});

            try deleteFile(allocator, io, config_directory, "/pam.d/ly", "ly pam file not found");

            switch (init_system) {
                .systemd => try deleteFile(allocator, io, prefix_directory, "/lib/systemd/system/ly@.service", "systemd service not found"),
                .openrc => try deleteFile(allocator, io, config_directory, "/init.d/ly", "openrc service not found"),
                .runit => try deleteTree(allocator, io, config_directory, "/sv/ly", "runit service not found"),
                .s6 => {
                    try deleteTree(allocator, io, config_directory, "/s6/sv/ly-srv", "s6 service not found");
                    try deleteFile(allocator, io, config_directory, "/s6/adminsv/default/contents.d/ly-srv", "s6 admin service not found");
                },
                .dinit => try deleteFile(allocator, io, config_directory, "/dinit.d/ly", "dinit service not found"),
                .sysvinit => try deleteFile(allocator, io, config_directory, "/init.d/ly", "sysvinit service not found"),
                .freebsd => try deleteFile(allocator, io, prefix_directory, "/bin/ly_wrapper", "freebsd wrapper not found"),
            }
        },
    }
}

fn installLy(allocator: std.mem.Allocator, io: std.Io, patch_map: PatchMap, install_config: bool) !void {
    const ly_config_directory = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, config_directory, "/ly" });
    defer allocator.free(ly_config_directory);

    std.Io.Dir.cwd().createDirPath(io, ly_config_directory) catch {
        std.debug.print("warn: {s} already exists as a directory.\n", .{ly_config_directory});
    };

    const ly_custom_sessions_directory = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, config_directory, "/ly/custom-sessions" });
    defer allocator.free(ly_custom_sessions_directory);

    std.Io.Dir.cwd().createDirPath(io, ly_custom_sessions_directory) catch {
        std.debug.print("warn: {s} already exists as a directory.\n", .{ly_custom_sessions_directory});
    };

    const ly_lang_path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, config_directory, "/ly/lang" });
    defer allocator.free(ly_lang_path);

    std.Io.Dir.cwd().createDirPath(io, ly_lang_path) catch {
        std.debug.print("warn: {s} already exists as a directory.\n", .{ly_lang_path});
    };

    {
        const exe_path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, prefix_directory, "/bin" });
        defer allocator.free(exe_path);

        std.Io.Dir.cwd().createDirPath(io, exe_path) catch {
            if (!std.mem.eql(u8, dest_directory, "")) {
                std.debug.print("warn: {s} already exists as a directory.\n", .{exe_path});
            }
        };

        var executable_dir = std.Io.Dir.cwd().openDir(io, exe_path, .{}) catch unreachable;
        defer executable_dir.close(io);

        try installFile(io, "zig-out/bin/ly", executable_dir, exe_path, executable_name, .{});
    }

    {
        var config_dir = std.Io.Dir.cwd().openDir(io, ly_config_directory, .{}) catch unreachable;
        defer config_dir.close(io);

        if (install_config) {
            const patched_config = try patchFile(allocator, io, "res/config.ini", patch_map);
            defer allocator.free(patched_config);

            try installText(io, patched_config, config_dir, ly_config_directory, "config.ini", .{});

            try installFile(io, "res/startup.sh", config_dir, ly_config_directory, "startup.sh", .{ .permissions = .fromMode(0o755) });
        }

        const patched_example_config = try patchFile(allocator, io, "res/config.ini", patch_map);
        defer allocator.free(patched_example_config);

        try installText(io, patched_example_config, config_dir, ly_config_directory, "config.ini.example", .{});

        const patched_setup = try patchFile(allocator, io, "res/setup.sh", patch_map);
        defer allocator.free(patched_setup);

        try installText(io, patched_setup, config_dir, ly_config_directory, "setup.sh", .{ .permissions = .fromMode(0o755) });

        try installFile(io, "res/example.dur", config_dir, ly_config_directory, "example.dur", .{ .permissions = .fromMode(0o755) });

        try installFile(io, "res/example.lua", config_dir, ly_config_directory, "example.lua", .{ .permissions = .fromMode(0o755) });
    }

    {
        var custom_sessions_dir = std.Io.Dir.cwd().openDir(io, ly_custom_sessions_directory, .{}) catch unreachable;
        defer custom_sessions_dir.close(io);

        const patched_readme = try patchFile(allocator, io, "res/custom-sessions/README", patch_map);
        defer allocator.free(patched_readme);

        try installText(io, patched_readme, custom_sessions_dir, ly_custom_sessions_directory, "README", .{});
    }

    {
        var lang_dir = std.Io.Dir.cwd().openDir(io, ly_lang_path, .{}) catch unreachable;
        defer lang_dir.close(io);

        const languages = [_][]const u8{
            "ar.ini",
            "bg.ini",
            "cat.ini",
            "cs.ini",
            "de.ini",
            "en.ini",
            "eo.ini",
            "es.ini",
            "fr.ini",
            "it.ini",
            "ja_JP.ini",
            "ku.ini",
            "lv.ini",
            "pl.ini",
            "pt.ini",
            "pt_BR.ini",
            "ro.ini",
            "ru.ini",
            "sr.ini",
            "sr_Cyrl.ini",
            "sv.ini",
            "tr.ini",
            "uk.ini",
            "zh_CN.ini",
            "zh_TW.ini",
        };

        inline for (languages) |language| {
            try installFile(io, "res/lang/" ++ language, lang_dir, ly_lang_path, language, .{});
        }
    }

    {
        const pam_path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, config_directory, "/pam.d" });
        defer allocator.free(pam_path);

        std.Io.Dir.cwd().createDirPath(io, pam_path) catch {
            if (!std.mem.eql(u8, dest_directory, "")) {
                std.debug.print("warn: {s} already exists as a directory.\n", .{pam_path});
            }
        };

        var pam_dir = std.Io.Dir.cwd().openDir(io, pam_path, .{}) catch unreachable;
        defer pam_dir.close(io);

        try installFile(io, if (init_system == .freebsd) "res/pam.d/ly-freebsd" else "res/pam.d/ly-linux", pam_dir, pam_path, "ly", .{ .permissions = .fromMode(0o644) });
        try installFile(io, if (init_system == .freebsd) "res/pam.d/ly-freebsd-autologin" else "res/pam.d/ly-linux-autologin", pam_dir, pam_path, "ly-autologin", .{ .permissions = .fromMode(0o644) });
    }
}

fn installService(allocator: std.mem.Allocator, io: std.Io, patch_map: PatchMap) !void {
    switch (init_system) {
        .systemd => {
            const service_path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, prefix_directory, "/lib/systemd/system" });
            defer allocator.free(service_path);

            std.Io.Dir.cwd().createDirPath(io, service_path) catch {};
            var service_dir = std.Io.Dir.cwd().openDir(io, service_path, .{}) catch unreachable;
            defer service_dir.close(io);

            const patched_service = try patchFile(allocator, io, "res/ly@.service", patch_map);
            defer allocator.free(patched_service);

            try installText(io, patched_service, service_dir, service_path, "ly@.service", .{ .permissions = .fromMode(0o644) });

            const patched_kmsconvt_service = try patchFile(allocator, io, "res/ly-kmsconvt@.service", patch_map);
            defer allocator.free(patched_kmsconvt_service);

            try installText(io, patched_kmsconvt_service, service_dir, service_path, "ly-kmsconvt@.service", .{ .permissions = .fromMode(0o644) });
        },
        .openrc => {
            const service_path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, config_directory, "/init.d" });
            defer allocator.free(service_path);

            std.Io.Dir.cwd().createDirPath(io, service_path) catch {};
            var service_dir = std.Io.Dir.cwd().openDir(io, service_path, .{}) catch unreachable;
            defer service_dir.close(io);

            const patched_service = try patchFile(allocator, io, "res/ly-openrc", patch_map);
            defer allocator.free(patched_service);

            try installText(io, patched_service, service_dir, service_path, executable_name, .{ .permissions = .fromMode(0o755) });
        },
        .runit => {
            const service_path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, config_directory, "/sv/ly" });
            defer allocator.free(service_path);

            std.Io.Dir.cwd().createDirPath(io, service_path) catch {};
            var service_dir = std.Io.Dir.cwd().openDir(io, service_path, .{}) catch unreachable;
            defer service_dir.close(io);

            const supervise_path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ service_path, "supervise" });
            defer allocator.free(supervise_path);

            const patched_conf = try patchFile(allocator, io, "res/ly-runit-service/conf", patch_map);
            defer allocator.free(patched_conf);

            try installText(io, patched_conf, service_dir, service_path, "conf", .{});

            try installFile(io, "res/ly-runit-service/finish", service_dir, service_path, "finish", .{ .permissions = .fromMode(0o755) });

            const patched_run = try patchFile(allocator, io, "res/ly-runit-service/run", patch_map);
            defer allocator.free(patched_run);

            try installText(io, patched_run, service_dir, service_path, "run", .{ .permissions = .fromMode(0o755) });

            std.Io.Dir.cwd().symLink(io, "/run/runit/supervise.ly", supervise_path, .{}) catch |err| {
                if (err == error.PathAlreadyExists) {
                    std.debug.print("warn: /run/runit/supervise.ly already exists as a symbolic link.\n", .{});
                } else {
                    return err;
                }
            };
            std.debug.print("info: installed symlink /run/runit/supervise.ly\n", .{});
        },
        .s6 => {
            const admin_service_path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, config_directory, "/s6/adminsv/default/contents.d" });
            std.Io.Dir.cwd().createDirPath(io, admin_service_path) catch {};
            defer allocator.free(admin_service_path);

            var admin_service_dir = std.Io.Dir.cwd().openDir(io, admin_service_path, .{}) catch unreachable;
            defer admin_service_dir.close(io);

            const file = try admin_service_dir.createFile(io, "ly-srv", .{});
            file.close(io);

            const service_path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, config_directory, "/s6/sv/ly-srv" });
            defer allocator.free(service_path);

            std.Io.Dir.cwd().createDirPath(io, service_path) catch {};
            var service_dir = std.Io.Dir.cwd().openDir(io, service_path, .{}) catch unreachable;
            defer service_dir.close(io);

            const patched_run = try patchFile(allocator, io, "res/ly-s6/run", patch_map);
            defer allocator.free(patched_run);

            try installText(io, patched_run, service_dir, service_path, "run", .{ .permissions = .fromMode(0o755) });

            try installFile(io, "res/ly-s6/type", service_dir, service_path, "type", .{});
        },
        .dinit => {
            const service_path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, config_directory, "/dinit.d" });
            defer allocator.free(service_path);

            std.Io.Dir.cwd().createDirPath(io, service_path) catch {};
            var service_dir = std.Io.Dir.cwd().openDir(io, service_path, .{}) catch unreachable;
            defer service_dir.close(io);

            const patched_service = try patchFile(allocator, io, "res/ly-dinit", patch_map);
            defer allocator.free(patched_service);

            try installText(io, patched_service, service_dir, service_path, "ly", .{});
        },
        .sysvinit => {
            const service_path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, config_directory, "/init.d" });
            defer allocator.free(service_path);

            std.Io.Dir.cwd().createDirPath(io, service_path) catch {};
            var service_dir = std.Io.Dir.cwd().openDir(io, service_path, .{}) catch unreachable;
            defer service_dir.close(io);

            const patched_service = try patchFile(allocator, io, "res/ly-sysvinit", patch_map);
            defer allocator.free(patched_service);

            try installText(io, patched_service, service_dir, service_path, "ly", .{ .permissions = .fromMode(0o755) });
        },
        .freebsd => {
            const exe_path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, prefix_directory, "/bin" });
            defer allocator.free(exe_path);

            var executable_dir = std.Io.Dir.cwd().openDir(io, exe_path, .{}) catch unreachable;
            defer executable_dir.close(io);

            const patched_wrapper = try patchFile(allocator, io, "res/ly-freebsd-wrapper", patch_map);
            defer allocator.free(patched_wrapper);

            try installText(io, patched_wrapper, executable_dir, exe_path, "ly_wrapper", .{ .permissions = .fromMode(0o755) });
        },
    }
}

fn installFile(
    io: std.Io,
    source_file: []const u8,
    destination_directory: std.Io.Dir,
    destination_directory_path: []const u8,
    destination_file: []const u8,
    options: std.Io.Dir.CopyFileOptions,
) !void {
    try std.Io.Dir.cwd().copyFile(source_file, destination_directory, destination_file, io, options);
    std.debug.print("info: installed {s}/{s}\n", .{ destination_directory_path, destination_file });
}

fn patchFile(allocator: std.mem.Allocator, io: std.Io, source_file: []const u8, patch_map: PatchMap) ![]const u8 {
    var file = try std.Io.Dir.cwd().openFile(io, source_file, .{});
    defer file.close(io);

    const stat = try file.stat(io);

    var buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &buffer);
    var text = try reader.interface.readAlloc(allocator, @intCast(stat.size));

    var iterator = patch_map.iterator();
    while (iterator.next()) |kv| {
        const new_text = try std.mem.replaceOwned(u8, allocator, text, kv.key_ptr.*, kv.value_ptr.*);
        allocator.free(text);
        text = new_text;
    }

    return text;
}

fn installText(
    io: std.Io,
    text: []const u8,
    destination_directory: std.Io.Dir,
    destination_directory_path: []const u8,
    destination_file: []const u8,
    options: std.Io.File.CreateFlags,
) !void {
    var file = try destination_directory.createFile(io, destination_file, options);
    defer file.close(io);

    var buffer: [1024]u8 = undefined;
    var writer = file.writer(io, &buffer);
    try writer.interface.writeAll(text);
    try writer.interface.flush();

    std.debug.print("info: installed {s}/{s}\n", .{ destination_directory_path, destination_file });
}

fn deleteFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    prefix: []const u8,
    file: []const u8,
    warning: []const u8,
) !void {
    const path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, prefix, file });
    defer allocator.free(path);

    std.Io.Dir.cwd().deleteFile(io, path) catch |err| {
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
    io: std.Io,
    prefix: []const u8,
    directory: []const u8,
    warning: []const u8,
) !void {
    const path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, prefix, directory });
    defer allocator.free(path);

    var dir = std.Io.Dir.cwd().openDir(io, path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("warn: {s}\n", .{warning});
            return;
        }

        return err;
    };
    dir.close(io);

    try std.Io.Dir.cwd().deleteTree(io, path);

    std.debug.print("info: deleted {s}\n", .{path});
}
