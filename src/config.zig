const std = @import("std");
const ini = @import("ini");
const main = @import("main.zig");
const interop = @import("interop.zig");

const INI_CONFIG_PATH: []const u8 = "/etc/ly/";
const INI_CONFIG_MAX_SIZE: usize = 16 * 1024;

pub const LyConfig = struct {
    ly: struct {
        animate: bool,
        animation: u8,
        asterisk: u8,
        bg: u8,
        bigclock: bool,
        blank_box: bool,
        blank_password: bool,
        clock: []const u8,
        console_dev: []const u8,
        default_input: u8,
        fg: u8,
        hide_borders: bool,
        hide_f1_commands: bool,
        input_len: u8,
        lang: []const u8,
        load: bool,
        margin_box_h: u8,
        margin_box_v: u8,
        max_desktop_len: u8,
        max_login_len: u8,
        max_password_len: u8,
        mcookie_cmd: []const u8,
        min_refresh_delta: u16,
        path: []const u8,
        restart_cmd: []const u8,
        save: bool,
        save_file: []const u8,
        service_name: []const u8,
        shutdown_cmd: []const u8,
        term_reset_cmd: []const u8,
        tty: u8,
        wayland_cmd: []const u8,
        wayland_specifier: bool,
        waylandsessions: []const u8,
        x_cmd: []const u8,
        xinitrc: []const u8,
        x_cmd_setup: []const u8,
        xauth_cmd: []const u8,
        xsessions: []const u8,
    },
};

pub const LyLang = struct {
    ly: struct {
        capslock: []const u8,
        err_alloc: []const u8,
        err_bounds: []const u8,
        err_chdir: []const u8,
        err_console_dev: []const u8,
        err_dgn_oob: []const u8,
        err_domain: []const u8,
        err_hostname: []const u8,
        err_mlock: []const u8,
        err_null: []const u8,
        err_pam: []const u8,
        err_pam_abort: []const u8,
        err_pam_acct_expired: []const u8,
        err_pam_auth: []const u8,
        err_pam_authinfo_unavail: []const u8,
        err_pam_authok_reqd: []const u8,
        err_pam_buf: []const u8,
        err_pam_cred_err: []const u8,
        err_pam_cred_expired: []const u8,
        err_pam_cred_insufficient: []const u8,
        err_pam_cred_unavail: []const u8,
        err_pam_maxtries: []const u8,
        err_pam_perm_denied: []const u8,
        err_pam_session: []const u8,
        err_pam_sys: []const u8,
        err_pam_user_unknown: []const u8,
        err_path: []const u8,
        err_perm_dir: []const u8,
        err_perm_group: []const u8,
        err_perm_user: []const u8,
        err_pwnam: []const u8,
        err_user_gid: []const u8,
        err_user_init: []const u8,
        err_user_uid: []const u8,
        err_xsessions_dir: []const u8,
        err_xsessions_open: []const u8,
        f1: []const u8,
        f2: []const u8,
        login: []const u8,
        logout: []const u8,
        numlock: []const u8,
        password: []const u8,
        shell: []const u8,
        wayland: []const u8,
        xinitrc: []const u8,
    },
};

pub var ly_config: LyConfig = undefined;
pub var ly_lang: LyLang = undefined;

var config_buffer: []u8 = undefined;
var lang_buffer: []u8 = undefined;

var config_clock: [:0]u8 = undefined;
var config_console_dev: [:0]u8 = undefined;
var config_lang: [:0]u8 = undefined;
var config_mcookie_cmd: [:0]u8 = undefined;
var config_path: [:0]u8 = undefined;
var config_restart_cmd: [:0]u8 = undefined;
var config_save_file: [:0]u8 = undefined;
var config_service_name: [:0]u8 = undefined;
var config_shutdown_cmd: [:0]u8 = undefined;
var config_term_reset_cmd: [:0]u8 = undefined;
var config_wayland_cmd: [:0]u8 = undefined;
var config_waylandsessions: [:0]u8 = undefined;
var config_x_cmd: [:0]u8 = undefined;
var config_xinitrc: [:0]u8 = undefined;
var config_x_cmd_setup: [:0]u8 = undefined;
var config_xauth_cmd: [:0]u8 = undefined;
var config_xsessions: [:0]u8 = undefined;

var lang_capslock: [:0]u8 = undefined;
var lang_err_alloc: [:0]u8 = undefined;
var lang_err_bounds: [:0]u8 = undefined;
var lang_err_chdir: [:0]u8 = undefined;
var lang_err_console_dev: [:0]u8 = undefined;
var lang_err_dgn_oob: [:0]u8 = undefined;
var lang_err_domain: [:0]u8 = undefined;
var lang_err_hostname: [:0]u8 = undefined;
var lang_err_mlock: [:0]u8 = undefined;
var lang_err_null: [:0]u8 = undefined;
var lang_err_pam: [:0]u8 = undefined;
var lang_err_pam_abort: [:0]u8 = undefined;
var lang_err_pam_acct_expired: [:0]u8 = undefined;
var lang_err_pam_auth: [:0]u8 = undefined;
var lang_err_pam_authinfo_unavail: [:0]u8 = undefined;
var lang_err_pam_authok_reqd: [:0]u8 = undefined;
var lang_err_pam_buf: [:0]u8 = undefined;
var lang_err_pam_cred_err: [:0]u8 = undefined;
var lang_err_pam_cred_expired: [:0]u8 = undefined;
var lang_err_pam_cred_insufficient: [:0]u8 = undefined;
var lang_err_pam_cred_unavail: [:0]u8 = undefined;
var lang_err_pam_maxtries: [:0]u8 = undefined;
var lang_err_pam_perm_denied: [:0]u8 = undefined;
var lang_err_pam_session: [:0]u8 = undefined;
var lang_err_pam_sys: [:0]u8 = undefined;
var lang_err_pam_user_unknown: [:0]u8 = undefined;
var lang_err_path: [:0]u8 = undefined;
var lang_err_perm_dir: [:0]u8 = undefined;
var lang_err_perm_group: [:0]u8 = undefined;
var lang_err_perm_user: [:0]u8 = undefined;
var lang_err_pwnam: [:0]u8 = undefined;
var lang_err_user_gid: [:0]u8 = undefined;
var lang_err_user_init: [:0]u8 = undefined;
var lang_err_user_uid: [:0]u8 = undefined;
var lang_err_xsessions_dir: [:0]u8 = undefined;
var lang_err_xsessions_open: [:0]u8 = undefined;
var lang_f1: [:0]u8 = undefined;
var lang_f2: [:0]u8 = undefined;
var lang_login: [:0]u8 = undefined;
var lang_logout: [:0]u8 = undefined;
var lang_numlock: [:0]u8 = undefined;
var lang_password: [:0]u8 = undefined;
var lang_shell: [:0]u8 = undefined;
var lang_wayland: [:0]u8 = undefined;
var lang_xinitrc: [:0]u8 = undefined;

pub fn config_load(cfg_path: []const u8) !void {
    var file = try std.fs.cwd().openFile(if (cfg_path.len == 0) INI_CONFIG_PATH ++ "config.ini" else cfg_path, .{});
    defer file.close();

    config_buffer = try main.allocator.alloc(u8, INI_CONFIG_MAX_SIZE);

    var length = try file.readAll(config_buffer);

    ly_config = try ini.readToStruct(LyConfig, config_buffer[0..length]);

    config_clock = try interop.c_str(ly_config.ly.clock);
    config_console_dev = try interop.c_str(ly_config.ly.console_dev);
    config_lang = try interop.c_str(ly_config.ly.lang);
    config_mcookie_cmd = try interop.c_str(ly_config.ly.mcookie_cmd);
    config_path = try interop.c_str(ly_config.ly.path);
    config_restart_cmd = try interop.c_str(ly_config.ly.restart_cmd);
    config_save_file = try interop.c_str(ly_config.ly.save_file);
    config_service_name = try interop.c_str(ly_config.ly.service_name);
    config_shutdown_cmd = try interop.c_str(ly_config.ly.shutdown_cmd);
    config_term_reset_cmd = try interop.c_str(ly_config.ly.term_reset_cmd);
    config_wayland_cmd = try interop.c_str(ly_config.ly.wayland_cmd);
    config_waylandsessions = try interop.c_str(ly_config.ly.waylandsessions);
    config_x_cmd = try interop.c_str(ly_config.ly.x_cmd);
    config_xinitrc = try interop.c_str(ly_config.ly.xinitrc);
    config_x_cmd_setup = try interop.c_str(ly_config.ly.x_cmd_setup);
    config_xauth_cmd = try interop.c_str(ly_config.ly.xauth_cmd);
    config_xsessions = try interop.c_str(ly_config.ly.xsessions);

    main.c_config.animate = ly_config.ly.animate;
    main.c_config.animation = ly_config.ly.animation;
    main.c_config.asterisk = ly_config.ly.asterisk;
    main.c_config.bg = ly_config.ly.bg;
    main.c_config.bigclock = ly_config.ly.bigclock;
    main.c_config.blank_box = ly_config.ly.blank_box;
    main.c_config.blank_password = ly_config.ly.blank_password;
    main.c_config.clock = config_clock.ptr;
    main.c_config.console_dev = config_console_dev.ptr;
    main.c_config.default_input = ly_config.ly.default_input;
    main.c_config.fg = ly_config.ly.fg;
    main.c_config.hide_borders = ly_config.ly.hide_borders;
    main.c_config.hide_f1_commands = ly_config.ly.hide_f1_commands;
    main.c_config.input_len = ly_config.ly.input_len;
    main.c_config.lang = config_lang.ptr;
    main.c_config.load = ly_config.ly.load;
    main.c_config.margin_box_h = ly_config.ly.margin_box_h;
    main.c_config.margin_box_v = ly_config.ly.margin_box_v;
    main.c_config.max_desktop_len = ly_config.ly.max_desktop_len;
    main.c_config.max_login_len = ly_config.ly.max_login_len;
    main.c_config.max_password_len = ly_config.ly.max_password_len;
    main.c_config.mcookie_cmd = config_mcookie_cmd.ptr;
    main.c_config.min_refresh_delta = ly_config.ly.min_refresh_delta;
    main.c_config.path = config_path.ptr;
    main.c_config.restart_cmd = config_restart_cmd.ptr;
    main.c_config.save = ly_config.ly.save;
    main.c_config.save_file = config_save_file.ptr;
    main.c_config.service_name = config_service_name.ptr;
    main.c_config.shutdown_cmd = config_shutdown_cmd.ptr;
    main.c_config.term_reset_cmd = config_term_reset_cmd.ptr;
    main.c_config.tty = ly_config.ly.tty;
    main.c_config.wayland_cmd = config_wayland_cmd.ptr;
    main.c_config.wayland_specifier = ly_config.ly.wayland_specifier;
    main.c_config.waylandsessions = config_waylandsessions.ptr;
    main.c_config.x_cmd = config_x_cmd.ptr;
    main.c_config.xinitrc = config_xinitrc.ptr;
    main.c_config.x_cmd_setup = config_x_cmd_setup.ptr;
    main.c_config.xauth_cmd = config_xauth_cmd.ptr;
    main.c_config.xsessions = config_xsessions.ptr;
}

pub fn lang_load() !void {
    var path = try std.fmt.allocPrint(main.allocator, "{s}{s}.ini", .{ INI_CONFIG_PATH ++ "lang/", ly_config.ly.lang });
    defer main.allocator.free(path);

    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    lang_buffer = try main.allocator.alloc(u8, INI_CONFIG_MAX_SIZE);

    var length = try file.readAll(lang_buffer);

    ly_lang = try ini.readToStruct(LyLang, lang_buffer[0..length]);

    lang_capslock = try interop.c_str(ly_lang.ly.capslock);
    lang_err_alloc = try interop.c_str(ly_lang.ly.err_alloc);
    lang_err_bounds = try interop.c_str(ly_lang.ly.err_bounds);
    lang_err_chdir = try interop.c_str(ly_lang.ly.err_chdir);
    lang_err_console_dev = try interop.c_str(ly_lang.ly.err_console_dev);
    lang_err_dgn_oob = try interop.c_str(ly_lang.ly.err_dgn_oob);
    lang_err_domain = try interop.c_str(ly_lang.ly.err_domain);
    lang_err_hostname = try interop.c_str(ly_lang.ly.err_hostname);
    lang_err_mlock = try interop.c_str(ly_lang.ly.err_mlock);
    lang_err_null = try interop.c_str(ly_lang.ly.err_null);
    lang_err_pam = try interop.c_str(ly_lang.ly.err_pam);
    lang_err_pam_abort = try interop.c_str(ly_lang.ly.err_pam_abort);
    lang_err_pam_acct_expired = try interop.c_str(ly_lang.ly.err_pam_acct_expired);
    lang_err_pam_auth = try interop.c_str(ly_lang.ly.err_pam_auth);
    lang_err_pam_authinfo_unavail = try interop.c_str(ly_lang.ly.err_pam_authinfo_unavail);
    lang_err_pam_authok_reqd = try interop.c_str(ly_lang.ly.err_pam_authok_reqd);
    lang_err_pam_buf = try interop.c_str(ly_lang.ly.err_pam_buf);
    lang_err_pam_cred_err = try interop.c_str(ly_lang.ly.err_pam_cred_err);
    lang_err_pam_cred_expired = try interop.c_str(ly_lang.ly.err_pam_cred_expired);
    lang_err_pam_cred_insufficient = try interop.c_str(ly_lang.ly.err_pam_cred_insufficient);
    lang_err_pam_cred_unavail = try interop.c_str(ly_lang.ly.err_pam_cred_unavail);
    lang_err_pam_maxtries = try interop.c_str(ly_lang.ly.err_pam_maxtries);
    lang_err_pam_perm_denied = try interop.c_str(ly_lang.ly.err_pam_perm_denied);
    lang_err_pam_session = try interop.c_str(ly_lang.ly.err_pam_session);
    lang_err_pam_sys = try interop.c_str(ly_lang.ly.err_pam_sys);
    lang_err_pam_user_unknown = try interop.c_str(ly_lang.ly.err_pam_user_unknown);
    lang_err_path = try interop.c_str(ly_lang.ly.err_path);
    lang_err_perm_dir = try interop.c_str(ly_lang.ly.err_perm_dir);
    lang_err_perm_group = try interop.c_str(ly_lang.ly.err_perm_group);
    lang_err_perm_user = try interop.c_str(ly_lang.ly.err_perm_user);
    lang_err_pwnam = try interop.c_str(ly_lang.ly.err_pwnam);
    lang_err_user_gid = try interop.c_str(ly_lang.ly.err_user_gid);
    lang_err_user_init = try interop.c_str(ly_lang.ly.err_user_init);
    lang_err_user_uid = try interop.c_str(ly_lang.ly.err_user_uid);
    lang_err_xsessions_dir = try interop.c_str(ly_lang.ly.err_xsessions_dir);
    lang_err_xsessions_open = try interop.c_str(ly_lang.ly.err_xsessions_open);
    lang_f1 = try interop.c_str(ly_lang.ly.f1);
    lang_f2 = try interop.c_str(ly_lang.ly.f2);
    lang_login = try interop.c_str(ly_lang.ly.login);
    lang_logout = try interop.c_str(ly_lang.ly.logout);
    lang_numlock = try interop.c_str(ly_lang.ly.numlock);
    lang_password = try interop.c_str(ly_lang.ly.password);
    lang_shell = try interop.c_str(ly_lang.ly.shell);
    lang_wayland = try interop.c_str(ly_lang.ly.wayland);
    lang_xinitrc = try interop.c_str(ly_lang.ly.xinitrc);

    main.c_lang.capslock = lang_capslock.ptr;
    main.c_lang.err_alloc = lang_err_alloc.ptr;
    main.c_lang.err_bounds = lang_err_bounds.ptr;
    main.c_lang.err_chdir = lang_err_chdir.ptr;
    main.c_lang.err_console_dev = lang_err_console_dev.ptr;
    main.c_lang.err_dgn_oob = lang_err_dgn_oob.ptr;
    main.c_lang.err_domain = lang_err_domain.ptr;
    main.c_lang.err_hostname = lang_err_hostname.ptr;
    main.c_lang.err_mlock = lang_err_mlock.ptr;
    main.c_lang.err_null = lang_err_null.ptr;
    main.c_lang.err_pam = lang_err_pam.ptr;
    main.c_lang.err_pam_abort = lang_err_pam_abort.ptr;
    main.c_lang.err_pam_acct_expired = lang_err_pam_acct_expired.ptr;
    main.c_lang.err_pam_auth = lang_err_pam_auth.ptr;
    main.c_lang.err_pam_authinfo_unavail = lang_err_pam_authinfo_unavail.ptr;
    main.c_lang.err_pam_authok_reqd = lang_err_pam_authok_reqd.ptr;
    main.c_lang.err_pam_buf = lang_err_pam_buf.ptr;
    main.c_lang.err_pam_cred_err = lang_err_pam_cred_err.ptr;
    main.c_lang.err_pam_cred_expired = lang_err_pam_cred_expired.ptr;
    main.c_lang.err_pam_cred_insufficient = lang_err_pam_cred_insufficient.ptr;
    main.c_lang.err_pam_cred_unavail = lang_err_pam_cred_unavail.ptr;
    main.c_lang.err_pam_maxtries = lang_err_pam_maxtries.ptr;
    main.c_lang.err_pam_perm_denied = lang_err_pam_perm_denied.ptr;
    main.c_lang.err_pam_session = lang_err_pam_session.ptr;
    main.c_lang.err_pam_sys = lang_err_pam_sys.ptr;
    main.c_lang.err_pam_user_unknown = lang_err_pam_user_unknown.ptr;
    main.c_lang.err_path = lang_err_path.ptr;
    main.c_lang.err_perm_dir = lang_err_perm_dir.ptr;
    main.c_lang.err_perm_group = lang_err_perm_group.ptr;
    main.c_lang.err_perm_user = lang_err_perm_user.ptr;
    main.c_lang.err_pwnam = lang_err_pwnam.ptr;
    main.c_lang.err_user_gid = lang_err_user_gid.ptr;
    main.c_lang.err_user_init = lang_err_user_init.ptr;
    main.c_lang.err_user_uid = lang_err_user_uid.ptr;
    main.c_lang.err_xsessions_dir = lang_err_xsessions_dir.ptr;
    main.c_lang.err_xsessions_open = lang_err_xsessions_open.ptr;
    main.c_lang.f1 = lang_f1.ptr;
    main.c_lang.f2 = lang_f2.ptr;
    main.c_lang.login = lang_login.ptr;
    main.c_lang.logout = lang_logout.ptr;
    main.c_lang.numlock = lang_numlock.ptr;
    main.c_lang.password = lang_password.ptr;
    main.c_lang.shell = lang_shell.ptr;
    main.c_lang.wayland = lang_wayland.ptr;
    main.c_lang.xinitrc = lang_xinitrc.ptr;
}

pub fn config_free() void {
    interop.allocator.free(config_clock);
    interop.allocator.free(config_console_dev);
    interop.allocator.free(config_lang);
    interop.allocator.free(config_mcookie_cmd);
    interop.allocator.free(config_path);
    interop.allocator.free(config_restart_cmd);
    interop.allocator.free(config_save_file);
    interop.allocator.free(config_service_name);
    interop.allocator.free(config_shutdown_cmd);
    interop.allocator.free(config_term_reset_cmd);
    interop.allocator.free(config_wayland_cmd);
    interop.allocator.free(config_waylandsessions);
    interop.allocator.free(config_x_cmd);
    interop.allocator.free(config_xinitrc);
    interop.allocator.free(config_x_cmd_setup);
    interop.allocator.free(config_xauth_cmd);
    interop.allocator.free(config_xsessions);

    main.allocator.free(config_buffer);
}

pub fn lang_free() void {
    interop.allocator.free(lang_capslock);
    interop.allocator.free(lang_err_alloc);
    interop.allocator.free(lang_err_bounds);
    interop.allocator.free(lang_err_chdir);
    interop.allocator.free(lang_err_console_dev);
    interop.allocator.free(lang_err_dgn_oob);
    interop.allocator.free(lang_err_domain);
    interop.allocator.free(lang_err_hostname);
    interop.allocator.free(lang_err_mlock);
    interop.allocator.free(lang_err_null);
    interop.allocator.free(lang_err_pam);
    interop.allocator.free(lang_err_pam_abort);
    interop.allocator.free(lang_err_pam_acct_expired);
    interop.allocator.free(lang_err_pam_auth);
    interop.allocator.free(lang_err_pam_authinfo_unavail);
    interop.allocator.free(lang_err_pam_authok_reqd);
    interop.allocator.free(lang_err_pam_buf);
    interop.allocator.free(lang_err_pam_cred_err);
    interop.allocator.free(lang_err_pam_cred_expired);
    interop.allocator.free(lang_err_pam_cred_insufficient);
    interop.allocator.free(lang_err_pam_cred_unavail);
    interop.allocator.free(lang_err_pam_maxtries);
    interop.allocator.free(lang_err_pam_perm_denied);
    interop.allocator.free(lang_err_pam_session);
    interop.allocator.free(lang_err_pam_sys);
    interop.allocator.free(lang_err_pam_user_unknown);
    interop.allocator.free(lang_err_path);
    interop.allocator.free(lang_err_perm_dir);
    interop.allocator.free(lang_err_perm_group);
    interop.allocator.free(lang_err_perm_user);
    interop.allocator.free(lang_err_pwnam);
    interop.allocator.free(lang_err_user_gid);
    interop.allocator.free(lang_err_user_init);
    interop.allocator.free(lang_err_user_uid);
    interop.allocator.free(lang_err_xsessions_dir);
    interop.allocator.free(lang_err_xsessions_open);
    interop.allocator.free(lang_f1);
    interop.allocator.free(lang_f2);
    interop.allocator.free(lang_login);
    interop.allocator.free(lang_logout);
    interop.allocator.free(lang_numlock);
    interop.allocator.free(lang_password);
    interop.allocator.free(lang_shell);
    interop.allocator.free(lang_wayland);
    interop.allocator.free(lang_xinitrc);

    main.allocator.free(lang_buffer);
}
