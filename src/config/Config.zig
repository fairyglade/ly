const build_options = @import("build_options");
const enums = @import("../enums.zig");

const Animation = enums.Animation;
const Input = enums.Input;

animation: Animation = .none,
asterisk: u8 = '*',
bg: u8 = 0,
bigclock: bool = false,
blank_box: bool = true,
border_fg: u8 = 8,
box_title: ?[]const u8 = null,
clear_password: bool = false,
clock: ?[:0]const u8 = null,
console_dev: [:0]const u8 = "/dev/console",
default_input: Input = .login,
fg: u8 = 8,
cmatrix_fg: u8 = 3,
hide_borders: bool = false,
hide_key_hints: bool = false,
initial_info_text: ?[]const u8 = null,
input_len: u8 = 34,
lang: []const u8 = "en",
load: bool = true,
margin_box_h: u8 = 2,
margin_box_v: u8 = 1,
max_desktop_len: u8 = 100,
max_login_len: u8 = 255,
max_password_len: u8 = 255,
mcookie_cmd: [:0]const u8 = "/usr/bin/mcookie",
min_refresh_delta: u16 = 5,
numlock: bool = false,
path: ?[:0]const u8 = "/sbin:/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin",
restart_cmd: []const u8 = "/sbin/shutdown -r now",
restart_key: []const u8 = "F2",
save: bool = true,
save_file: []const u8 = "/etc/ly/save",
service_name: [:0]const u8 = "ly",
shutdown_cmd: []const u8 = "/sbin/shutdown -a now",
shutdown_key: []const u8 = "F1",
sleep_cmd: ?[]const u8 = null,
sleep_key: []const u8 = "F3",
term_reset_cmd: [:0]const u8 = "/usr/bin/tput reset",
term_restore_cursor_cmd: []const u8 = "/usr/bin/tput cnorm",
tty: u8 = build_options.tty,
vi_mode: bool = false,
wayland_cmd: []const u8 = build_options.data_directory ++ "/wsetup.sh",
waylandsessions: []const u8 = "/usr/share/wayland-sessions",
x_cmd: []const u8 = "/usr/bin/X",
xinitrc: ?[]const u8 = "~/.xinitrc",
x_cmd_setup: []const u8 = build_options.data_directory ++ "/xsetup.sh",
xauth_cmd: []const u8 = "/usr/bin/xauth",
xsessions: []const u8 = "/usr/share/xsessions",
brightness_down_key: []const u8 = "F5",
brightness_up_key: []const u8 = "F6",
brightnessctl: []const u8 = "/usr/bin/brightnessctl",
brightness_change: []const u8 = "10",
