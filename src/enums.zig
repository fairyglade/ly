pub const Animation = enum {
    none,
    doom,
    matrix,
};

pub const DisplayServer = enum {
    wayland,
    shell,
    xinitrc,
    x11,
};

pub const Input = enum {
    session,
    login,
    password,
};
