const std = @import("std");

// We set both values to 0 by default so that, in case they aren't present in
// the login.defs for some reason, then only the root username will be shown
uid_min: std.posix.uid_t = 0,
uid_max: std.posix.uid_t = 0,
