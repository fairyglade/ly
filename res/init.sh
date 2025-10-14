#!/bin/sh
# Styling options
local BOLD      = 0x01000000
local UNDERLINE = 0x02000000
local REVERSE   = 0x04000000
local ITALIC    = 0x08000000
local BLINK     = 0x10000000
local HI_BLACK  = 0x20000000
local BRIGHT    = 0x40000000
local DIM       = 0x80000000

# Common colors
local DEFAULT   = 0x00000000
local RED       = 0x00FF0000
local GREEN     = 0x0000FF00
local YELLOW    = 0x00FFFF00
local BLUE      = 0x000000FF
local MAGENTA   = 0x00FF00FF
local CYAN      = 0x0000FFFF
local WHITE     = 0x00FFFFFF

source lang/en.sh # From lang

# It'd be a good idea to condense multiple options into 1 command (e.g.
# animation settings)
ly set-config allow_empty_password true
ly set-config animation none
ly set-config animation_timeout_sec 0
ly set-config asterisk "*"
ly set-config auth_fails 10
ly set-config bg $DEFAULT
ly set-config bigclock_12hr false
ly set-config bigclock_seconds false
ly set-config blank_box true
ly set-config border_fg $WHITE
ly set-config box_title null
ly set-config clear_password false
ly set-config clock null
ly set-config cmatrix_fg $GREEN
ly set-config cmatrix_head_col $(($WHITE | $BOLD))
ly set-config cmatrix_min_codepoint 0x21
ly set-config cmatrix_max_codepoint = 0x7B
ly set-config colormix_col1 $RED
ly set-config colormix_col2 $BLUE
ly set-config colormix_col3 $HI_BLACK
ly set-config default_input login
ly set-config doom_fire_height 6
ly set-config doom_fire_spread 2
ly set-config doom_top_color 0x009F2707
ly set-config doom_middle_color 0x00C78F17
ly set-config doom_bottom_color $WHITE
ly set-config error_bg $DEFAULT
ly set-config error_fg $(($RED | $BOLD))
ly set-config fg $WHITE
ly set-config full_color true
ly set-config gameoflife_entropy_interval 10
ly set-config gameoflife_fg $GREEN
ly set-config gameoflife_frame_delay 6
ly set-config gameoflife_initial_density 0.4
ly set-config hide_borders false
ly set-config initial_info_text null
ly set-config input_len 34
ly set-config login_cmd null
ly set-config login_defs_path "/etc/login.defs"
ly set-config logout_cmd null
ly set-config ly_log "/var/log/ly.log"
ly set-config margin_box_h 2
ly set-config margin_box_v 1
ly set-config min_refresh_delta 5
ly set-config numlock false
ly set-config path "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ly set-config save true
ly set-config service_name ly
ly set-config session_log "ly-session.log"
ly set-config setup_cmd "$CONFIG_DIRECTORY/ly/setup.sh"
ly set-config text_in_center false
ly set-config vi_default_mode normal
ly set-config vi_mode false
ly set-config x_cmd "$PREFIX_DIRECTORY/bin/X"
ly set-config xauth_cmd "$PREFIX_DIRECTORY/bin/xauth"

# Replaces respective options
# X11 requires special support from the display manager, which is why a separate
# command is required
ly add-session "System shell" shell "/bin/sh"
ly add-x11-session xinitrc x11 "~/.xinitrc"

# ly add-session-dir custom "$CONFIG_DIRECTORY/ly/custom-sessions"
ly add-session-dir wayland "$PREFIX_DIRECTORY/share/wayland-sessions"
ly add-x11-session-dir x11 "$PREFIX_DIRECTORY/share/xsessions"

ly add-hud 0 0 "Ly version %VERSION" null null top left
ly add-hud 1 0 "F1 shutdown" F1 "/sbin/shutdown -a now" top left
ly add-hud 2 0 "F2 reboot" F2 "/sbin/shutdown -r now" top left
#ly add-hud 0 0 "F3 sleep" F3 null top left
ly add-hud 3 0 "F5 decrease brightness" F5 "$PREFIX_DIRECTORY/bin/brightnessctl -q s 10%-" top left
ly add-hud 4 0 "F6 increase brightness" F6 "$PREFIX_DIRECTORY/bin/brightnessctl -q s +10%" top left
ly add-hud 5 0 "%CLOCK" null null top right
