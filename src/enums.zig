pub const Animation = enum {
    none,
    doom,
    matrix,
    colormix,
    gameoflife,
    metaballs
};

pub const DisplayServer = enum {
    wayland,
    shell,
    xinitrc,
    x11,
    custom,
};

pub const Input = enum {
    info_line,
    session,
    login,
    password,
};

pub const ViMode = enum {
    normal,
    insert,
};

pub const Bigclock = enum {
    none,
    en,
    fa,
};
