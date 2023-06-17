const std = @import("std");

pub const c = @cImport({
    @cInclude("configator.h");
    @cInclude("dragonfail.h");
    @cInclude("termbox.h");

    @cInclude("draw.h");
    @cInclude("inputs.h");
    @cInclude("login.h");
    @cInclude("utils.h");
    @cInclude("config.h");
});

// Compile-time settings
const LY_VERSION = "0.7.0";
const MAX_AUTH_FAILS = 10;

// Main allocator for Ly
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub const allocator = gpa.allocator();

// Ly general and language configuration
pub var config: c.struct_config = undefined;
pub var lang: c.struct_lang = undefined;

comptime {
    @export(config, .{ .name = "config" });
    @export(lang, .{ .name = "lang" });
}

// Main function
pub fn main() !void {
    // Initialize structs
    var config_ptr = try allocator.create(c.struct_config);
    defer allocator.destroy(config_ptr);

    var lang_ptr = try allocator.create(c.struct_lang);
    defer allocator.destroy(lang_ptr);

    config = config_ptr.*;
    lang = lang_ptr.*;

    // Load configuration
    c.config_defaults();
    c.lang_defaults();

    // Initialize error library
    log_init(c.dgn_init());

    // Parse command line arguments
    var config_path: []const u8 = undefined;

    var process_args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, process_args);

    if (process_args.len > 1) {
        var first_arg = process_args[1];

        if (std.mem.eql(u8, first_arg, "--help") or std.mem.eql(u8, first_arg, "-h")) {
            std.debug.print("--help (-h)            | Shows this help message.\n", .{});
            std.debug.print("--version (-v)         | Shows the version of Ly.\n", .{});
            std.debug.print("--config (-c) <path>   | Overrides the configuration file path.\n", .{});
            std.debug.print("\n", .{});
            std.debug.print("If you want to configure Ly, please check the config file, usually located at /etc/ly/config.ini.\n", .{});
            std.os.exit(0);
            return;
        } else if (std.mem.eql(u8, first_arg, "--version") or std.mem.eql(u8, first_arg, "-v")) {
            std.debug.print("Ly version {s}.\n", .{LY_VERSION});
            std.os.exit(0);
            return;
        } else if (std.mem.eql(u8, first_arg, "--config") or std.mem.eql(u8, first_arg, "-c")) {
            if (process_args.len != 3) {
                std.debug.print("Invalid usage! Correct usage: 'ly --config <path>'.\n", .{});
                std.os.exit(1);
                return;
            }

            config_path = process_args[2];
        } else {
            std.debug.print("Invalid argument: '{s}'.\n", .{first_arg});
            std.os.exit(1);
            return;
        }
    }

    // Initialize inputs
    var desktop = try allocator.create(c.struct_desktop);
    defer allocator.destroy(desktop);

    var username = try allocator.create(c.struct_text);
    defer allocator.destroy(username);

    var password = try allocator.create(c.struct_text);
    defer allocator.destroy(password);

    c.input_desktop(desktop);
    c.input_text(username, config.max_login_len);
    c.input_text(password, config.max_password_len);

    if (c.dgn_catch() != 0) {
        c.config_free();
        c.lang_free();
        std.os.exit(1);
        return;
    }

    c.config_load(config_path.ptr);
    c.lang_load();

    c.desktop_load(desktop);
    c.load(desktop, username);

    // Start termbox
    _ = c.tb_init();
    _ = c.tb_select_output_mode(c.TB_OUTPUT_NORMAL);
    c.tb_clear();

    // Initialize visible elements
    var event = try allocator.create(c.struct_tb_event);
    defer allocator.destroy(event);

    var buffer = try allocator.create(c.struct_term_buf);
    defer allocator.destroy(buffer);

    // Place the cursor on the login field if there is no saved username
    // If there is, place the curser on the password field
    var active_input: u8 = 0;
    if (config.default_input == c.LOGIN_INPUT and username.text != username.end) {
        active_input = c.PASSWORD_INPUT;
    } else {
        active_input = config.default_input;
    }

    // Initialize drawing code
    c.draw_init(buffer);

    // draw_box() and position_input() are called because they need to be
    // called before the switch case for the cursor to be positioned correctly
    c.draw_box(buffer);
    c.position_input(buffer, desktop, username, password);

    switch (active_input) {
        c.SESSION_SWITCH => {
            c.handle_desktop(desktop, event);
        },
        c.LOGIN_INPUT => {
            c.handle_text(username, event);
        },
        c.PASSWORD_INPUT => {
            c.handle_text(password, event);
        },
        else => unreachable,
    }

    if (config.animate) {
        c.animate_init(buffer);

        if (c.dgn_catch() != 0) {
            config.animate = false;
            c.dgn_reset();
        }
    }

    // Initialize state information
    var err: c_int = 0;
    var run = true;
    var update = true;
    var reboot = false;
    var shutdown = false;
    var auth_fails: u8 = 0;

    c.switch_tty(buffer);

    // Main loop
    while (run) {
        if (update) {
            if (auth_fails < MAX_AUTH_FAILS) {
                switch (active_input) {
                    c.SESSION_SWITCH => {
                        c.handle_desktop(desktop, event);
                    },
                    c.LOGIN_INPUT => {
                        c.handle_text(username, event);
                    },
                    c.PASSWORD_INPUT => {
                        c.handle_text(password, event);
                    },
                    else => unreachable,
                }

                c.tb_clear();
                c.animate(buffer);
                c.draw_bigclock(buffer);
                c.draw_box(buffer);
                c.draw_clock(buffer);
                c.draw_labels(buffer);
                if (!config.hide_f1_commands) {
                    c.draw_f_commands();
                }
                c.draw_lock_state(buffer);
                c.position_input(buffer, desktop, username, password);
                c.draw_desktop(desktop);
                c.draw_input(username);
                c.draw_input_mask(password);
                update = config.animate;
            } else {
                std.time.sleep(10000000); // Sleep 0.01 seconds
                update = c.cascade(buffer, &auth_fails);
            }

            c.tb_present();
        }

        var timeout: c_int = -1;

        if (config.animate) {
            timeout = config.min_refresh_delta;
        } else {
            // TODO: Use the Zig standard library directly
            var time = try allocator.create(std.os.linux.timeval);
            defer allocator.destroy(time);

            _ = std.os.linux.gettimeofday(time, undefined);

            if (config.bigclock) {
                timeout = @intCast(c_int, (60 - @mod(time.tv_sec, 60)) * 1000 - @divTrunc(time.tv_usec, 1000) + 1);
            } else if (config.clock != undefined) {
                timeout = @intCast(c_int, 1000 - @divTrunc(time.tv_usec, 1000) + 1);
            }
        }

        if (timeout == -1) {
            err = c.tb_poll_event(event);
        } else {
            err = c.tb_peek_event(event, timeout);
        }

        if (err < 0) {
            continue;
        }

        if (event.type == c.TB_EVENT_KEY) {
            switch (event.key) {
                c.TB_KEY_F1 => {
                    shutdown = true;
                    run = false;
                },
                c.TB_KEY_F2 => {
                    reboot = true;
                    run = false;
                },
                c.TB_KEY_CTRL_C => {
                    run = false;
                },
                c.TB_KEY_CTRL_U => {
                    if (active_input > c.SESSION_SWITCH) {
                        switch (active_input) {
                            c.LOGIN_INPUT => {
                                c.input_text_clear(username);
                            },
                            c.PASSWORD_INPUT => {
                                c.input_text_clear(password);
                            },
                            else => unreachable,
                        }

                        update = true;
                    }
                },
                c.TB_KEY_CTRL_K, c.TB_KEY_ARROW_UP => {
                    if (active_input > c.SESSION_SWITCH) {
                        active_input -= 1;
                        update = true;
                    }
                },
                c.TB_KEY_CTRL_J, c.TB_KEY_ARROW_DOWN => {
                    if (active_input < c.PASSWORD_INPUT) {
                        active_input += 1;
                        update = true;
                    }
                },
                c.TB_KEY_TAB => {
                    active_input += 1;

                    if (active_input > c.PASSWORD_INPUT) {
                        active_input = c.SESSION_SWITCH;
                    }

                    update = true;
                },
                c.TB_KEY_ENTER => {
                    c.save(desktop, username);
                    c.auth(desktop, username, password, buffer);

                    if (c.dgn_catch() != 0) {
                        auth_fails += 1;

                        // Move focus back to password input
                        active_input = c.PASSWORD_INPUT;

                        if (c.dgn_output_code() != c.DGN_PAM) {
                            buffer.info_line = c.dgn_output_log();
                        }

                        if (config.blank_password) {
                            c.input_text_clear(password);
                        }

                        c.dgn_reset();
                    } else {
                        buffer.info_line = lang.logout;
                    }

                    c.load(desktop, username);

                    // Reset cursor to its normal state
                    _ = std.ChildProcess.exec(.{ .argv = &[_][]const u8{ "/usr/bin/tput", "cnorm" }, .allocator = allocator }) catch return;

                    update = true;
                },
                else => {
                    update = true;
                },
            }
        }
    }

    // Stop termbox
    c.tb_shutdown();

    // Free inputs
    c.input_desktop_free(desktop);
    c.input_text_free(username);
    c.input_text_free(password);
    c.free_hostname();

    // Unload configuration
    c.draw_free(buffer);
    c.lang_free();

    if (shutdown) {
        var shutdown_cmd = try std.fmt.allocPrint(allocator, "{s}", .{config.shutdown_cmd});
        // This will never be freed! But it's fine, we're shutting down the system anyway
        defer allocator.free(shutdown_cmd);

        c.config_free();

        std.process.execv(allocator, &[_][]const u8{ "/bin/sh", "-c", shutdown_cmd }) catch return;
    } else if (reboot) {
        var restart_cmd = try std.fmt.allocPrint(allocator, "{s}", .{config.restart_cmd});
        // This will never be freed! But it's fine, we're rebooting the system anyway
        defer allocator.free(restart_cmd);

        c.config_free();

        std.process.execv(allocator, &[_][]const u8{ "/bin/sh", "-c", restart_cmd }) catch return;
    } else {
        c.config_free();
    }
}

// Low-level error messages
fn log_init(log: [*c][*c]u8) void {
    log[c.DGN_OK] = lang.err_dgn_oob;
    log[c.DGN_NULL] = lang.err_null;
    log[c.DGN_ALLOC] = lang.err_alloc;
    log[c.DGN_BOUNDS] = lang.err_bounds;
    log[c.DGN_DOMAIN] = lang.err_domain;
    log[c.DGN_MLOCK] = lang.err_mlock;
    log[c.DGN_XSESSIONS_DIR] = lang.err_xsessions_dir;
    log[c.DGN_XSESSIONS_OPEN] = lang.err_xsessions_open;
    log[c.DGN_PATH] = lang.err_path;
    log[c.DGN_CHDIR] = lang.err_chdir;
    log[c.DGN_PWNAM] = lang.err_pwnam;
    log[c.DGN_USER_INIT] = lang.err_user_init;
    log[c.DGN_USER_GID] = lang.err_user_gid;
    log[c.DGN_USER_UID] = lang.err_user_uid;
    log[c.DGN_PAM] = lang.err_pam;
    log[c.DGN_HOSTNAME] = lang.err_hostname;
}
