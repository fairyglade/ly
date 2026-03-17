const std = @import("std");
const Allocator = std.mem.Allocator;
const KeyList = std.ArrayList(Key);

const TerminalBuffer = @import("TerminalBuffer.zig");
const termbox = TerminalBuffer.termbox;

pub const Key = packed struct {
    ctrl: bool,
    shift: bool,
    alt: bool,

    f1: bool,
    f2: bool,
    f3: bool,
    f4: bool,
    f5: bool,
    f6: bool,
    f7: bool,
    f8: bool,
    f9: bool,
    f10: bool,
    f11: bool,
    f12: bool,

    insert: bool,
    delete: bool,
    home: bool,
    end: bool,
    pageup: bool,
    pagedown: bool,
    up: bool,
    down: bool,
    left: bool,
    right: bool,
    tab: bool,
    backspace: bool,
    enter: bool,

    @" ": bool,
    @"!": bool,
    @"`": bool,
    esc: bool,
    @"[": bool,
    @"\\": bool,
    @"]": bool,
    @"/": bool,
    _: bool,
    @"'": bool,
    @"\"": bool,
    @",": bool,
    @"-": bool,
    @".": bool,
    @"#": bool,
    @"$": bool,
    @"%": bool,
    @"&": bool,
    @"*": bool,
    @"(": bool,
    @")": bool,
    @"+": bool,
    @"=": bool,
    @":": bool,
    @";": bool,
    @"<": bool,
    @">": bool,
    @"?": bool,
    @"@": bool,
    @"^": bool,
    @"~": bool,
    @"{": bool,
    @"}": bool,
    @"|": bool,

    @"0": bool,
    @"1": bool,
    @"2": bool,
    @"3": bool,
    @"4": bool,
    @"5": bool,
    @"6": bool,
    @"7": bool,
    @"8": bool,
    @"9": bool,

    a: bool,
    b: bool,
    c: bool,
    d: bool,
    e: bool,
    f: bool,
    g: bool,
    h: bool,
    i: bool,
    j: bool,
    k: bool,
    l: bool,
    m: bool,
    n: bool,
    o: bool,
    p: bool,
    q: bool,
    r: bool,
    s: bool,
    t: bool,
    u: bool,
    v: bool,
    w: bool,
    x: bool,
    y: bool,
    z: bool,

    pub fn getEnabledPrintableAscii(self: Key) ?u8 {
        if (self.ctrl or self.alt) return null;

        inline for (std.meta.fields(Key)) |field| {
            if (field.name.len == 1 and std.ascii.isPrint(field.name[0]) and @field(self, field.name)) {
                if (self.shift) {
                    if (!std.ascii.isAlphanumeric(field.name[0])) return null;
                    return std.ascii.toUpper(field.name[0]);
                }

                return field.name[0];
            }
        }

        return null;
    }
};

pub fn getKeyList(allocator: Allocator, tb_event: termbox.tb_event) !KeyList {
    var keys: KeyList = .empty;
    var key = std.mem.zeroes(Key);

    if (tb_event.mod & termbox.TB_MOD_CTRL != 0) key.ctrl = true;
    if (tb_event.mod & termbox.TB_MOD_SHIFT != 0) key.shift = true;
    if (tb_event.mod & termbox.TB_MOD_ALT != 0) key.alt = true;

    if (tb_event.key == termbox.TB_KEY_BACK_TAB) {
        key.shift = true;
        key.tab = true;
    } else if (tb_event.key > termbox.TB_KEY_BACK_TAB) {
        const code = 0xFFFF - tb_event.key;

        switch (code) {
            0 => key.f1 = true,
            1 => key.f2 = true,
            2 => key.f3 = true,
            3 => key.f4 = true,
            4 => key.f5 = true,
            5 => key.f6 = true,
            6 => key.f7 = true,
            7 => key.f8 = true,
            8 => key.f9 = true,
            9 => key.f10 = true,
            10 => key.f11 = true,
            11 => key.f12 = true,
            12 => key.insert = true,
            13 => key.delete = true,
            14 => key.home = true,
            15 => key.end = true,
            16 => key.pageup = true,
            17 => key.pagedown = true,
            18 => key.up = true,
            19 => key.down = true,
            20 => key.left = true,
            21 => key.right = true,
            else => {},
        }
    } else if (tb_event.ch < 128) {
        const code = if (tb_event.ch == 0 and tb_event.key < 128) tb_event.key else tb_event.ch;

        switch (code) {
            0 => {
                key.ctrl = true;
                key.@"2" = true;
                try keys.append(allocator, key);

                key = std.mem.zeroes(Key);
                key.@"`" = true;
            },
            1 => {
                key.ctrl = true;
                key.a = true;
            },
            2 => {
                key.ctrl = true;
                key.b = true;
            },
            3 => {
                key.ctrl = true;
                key.c = true;
            },
            4 => {
                key.ctrl = true;
                key.d = true;
            },
            5 => {
                key.ctrl = true;
                key.e = true;
            },
            6 => {
                key.ctrl = true;
                key.f = true;
            },
            7 => {
                key.ctrl = true;
                key.g = true;
            },
            8 => {
                key.ctrl = true;
                key.h = true;
                try keys.append(allocator, key);

                key = std.mem.zeroes(Key);
                key.backspace = true;
            },
            9 => {
                key.ctrl = true;
                key.i = true;
                try keys.append(allocator, key);

                key = std.mem.zeroes(Key);
                key.tab = true;
            },
            10 => {
                key.ctrl = true;
                key.j = true;
            },
            11 => {
                key.ctrl = true;
                key.k = true;
            },
            12 => {
                key.ctrl = true;
                key.l = true;
            },
            13 => {
                key.ctrl = true;
                key.m = true;
                try keys.append(allocator, key);

                key = std.mem.zeroes(Key);
                key.enter = true;
            },
            14 => {
                key.ctrl = true;
                key.n = true;
            },
            15 => {
                key.ctrl = true;
                key.o = true;
            },
            16 => {
                key.ctrl = true;
                key.p = true;
            },
            17 => {
                key.ctrl = true;
                key.q = true;
            },
            18 => {
                key.ctrl = true;
                key.r = true;
            },
            19 => {
                key.ctrl = true;
                key.s = true;
            },
            20 => {
                key.ctrl = true;
                key.t = true;
            },
            21 => {
                key.ctrl = true;
                key.u = true;
            },
            22 => {
                key.ctrl = true;
                key.v = true;
            },
            23 => {
                key.ctrl = true;
                key.w = true;
            },
            24 => {
                key.ctrl = true;
                key.x = true;
            },
            25 => {
                key.ctrl = true;
                key.y = true;
            },
            26 => {
                key.ctrl = true;
                key.z = true;
            },
            27 => {
                key.ctrl = true;
                key.@"3" = true;
                try keys.append(allocator, key);

                key = std.mem.zeroes(Key);
                key.esc = true;
                try keys.append(allocator, key);

                key = std.mem.zeroes(Key);
                key.@"[" = true;
            },
            28 => {
                key.ctrl = true;
                key.@"4" = true;
                try keys.append(allocator, key);

                key = std.mem.zeroes(Key);
                key.@"\\" = true;
            },
            29 => {
                key.ctrl = true;
                key.@"5" = true;
                try keys.append(allocator, key);

                key = std.mem.zeroes(Key);
                key.@"]" = true;
            },
            30 => {
                key.ctrl = true;
                try keys.append(allocator, key);

                key = std.mem.zeroes(Key);
                key.@"6" = true;
            },
            31 => {
                key.ctrl = true;
                key.@"7" = true;
                try keys.append(allocator, key);

                key = std.mem.zeroes(Key);
                key.@"/" = true;
                try keys.append(allocator, key);

                key = std.mem.zeroes(Key);
                key._ = true;
            },
            32 => {
                key.@" " = true;
            },
            33 => {
                key = std.mem.zeroes(Key);
                key.@"!" = true;
            },
            34 => {
                key = std.mem.zeroes(Key);
                key.@"\"" = true;
            },
            35 => {
                key = std.mem.zeroes(Key);
                key.@"#" = true;
            },
            36 => {
                key = std.mem.zeroes(Key);
                key.@"$" = true;
            },
            37 => {
                key = std.mem.zeroes(Key);
                key.@"%" = true;
            },
            38 => {
                key = std.mem.zeroes(Key);
                key.@"&" = true;
            },
            39 => {
                key.@"'" = true;
            },
            40 => {
                key = std.mem.zeroes(Key);
                key.@"(" = true;
            },
            41 => {
                key = std.mem.zeroes(Key);
                key.@")" = true;
            },
            42 => {
                key = std.mem.zeroes(Key);
                key.@"*" = true;
            },
            43 => {
                key = std.mem.zeroes(Key);
                key.@"+" = true;
            },
            44 => {
                key.@"," = true;
            },
            45 => {
                key.@"-" = true;
            },
            46 => {
                key.@"." = true;
            },
            47 => {
                key.@"/" = true;
            },
            48 => {
                key.@"0" = true;
            },
            49 => {
                key.@"1" = true;
            },
            50 => {
                key.@"2" = true;
            },
            51 => {
                key.@"3" = true;
            },
            52 => {
                key.@"4" = true;
            },
            53 => {
                key.@"5" = true;
            },
            54 => {
                key.@"6" = true;
            },
            55 => {
                key.@"7" = true;
            },
            56 => {
                key.@"8" = true;
            },
            57 => {
                key.@"9" = true;
            },
            58 => {
                key.shift = true;
                key.@":" = true;
            },
            59 => {
                key.@";" = true;
            },
            60 => {
                key.shift = true;
                key.@"<" = true;
            },
            61 => {
                key.@"=" = true;
            },
            62 => {
                key.shift = true;
                key.@">" = true;
            },
            63 => {
                key.shift = true;
                key.@"?" = true;
            },
            64 => {
                key.shift = true;
                key.@"2" = true;
                try keys.append(allocator, key);

                key = std.mem.zeroes(Key);
                key.@"@" = true;
            },
            65 => {
                key.shift = true;
                key.a = true;
            },
            66 => {
                key.shift = true;
                key.b = true;
            },
            67 => {
                key.shift = true;
                key.c = true;
            },
            68 => {
                key.shift = true;
                key.d = true;
            },
            69 => {
                key.shift = true;
                key.e = true;
            },
            70 => {
                key.shift = true;
                key.f = true;
            },
            71 => {
                key.shift = true;
                key.g = true;
            },
            72 => {
                key.shift = true;
                key.h = true;
            },
            73 => {
                key.shift = true;
                key.i = true;
            },
            74 => {
                key.shift = true;
                key.j = true;
            },
            75 => {
                key.shift = true;
                key.k = true;
            },
            76 => {
                key.shift = true;
                key.l = true;
            },
            77 => {
                key.shift = true;
                key.m = true;
            },
            78 => {
                key.shift = true;
                key.n = true;
            },
            79 => {
                key.shift = true;
                key.o = true;
            },
            80 => {
                key.shift = true;
                key.p = true;
            },
            81 => {
                key.shift = true;
                key.q = true;
            },
            82 => {
                key.shift = true;
                key.r = true;
            },
            83 => {
                key.shift = true;
                key.s = true;
            },
            84 => {
                key.shift = true;
                key.t = true;
            },
            85 => {
                key.shift = true;
                key.u = true;
            },
            86 => {
                key.shift = true;
                key.v = true;
            },
            87 => {
                key.shift = true;
                key.w = true;
            },
            88 => {
                key.shift = true;
                key.x = true;
            },
            89 => {
                key.shift = true;
                key.y = true;
            },
            90 => {
                key.shift = true;
                key.z = true;
            },
            91 => {
                key.@"[" = true;
            },
            92 => {
                key.@"\\" = true;
            },
            93 => {
                key.@"]" = true;
            },
            94 => {
                key = std.mem.zeroes(Key);
                key.@"^" = true;
            },
            95 => {
                key.shift = true;
                key.@"-" = true;
                try keys.append(allocator, key);

                key = std.mem.zeroes(Key);
                key._ = true;
            },
            96 => {
                key.@"`" = true;
            },
            97 => {
                key.a = true;
            },
            98 => {
                key.b = true;
            },
            99 => {
                key.c = true;
            },
            100 => {
                key.d = true;
            },
            101 => {
                key.e = true;
            },
            102 => {
                key.f = true;
            },
            103 => {
                key.g = true;
            },
            104 => {
                key.h = true;
            },
            105 => {
                key.i = true;
            },
            106 => {
                key.j = true;
            },
            107 => {
                key.k = true;
            },
            108 => {
                key.l = true;
            },
            109 => {
                key.m = true;
            },
            110 => {
                key.n = true;
            },
            111 => {
                key.o = true;
            },
            112 => {
                key.p = true;
            },
            113 => {
                key.q = true;
            },
            114 => {
                key.r = true;
            },
            115 => {
                key.s = true;
            },
            116 => {
                key.t = true;
            },
            117 => {
                key.u = true;
            },
            118 => {
                key.v = true;
            },
            119 => {
                key.w = true;
            },
            120 => {
                key.x = true;
            },
            121 => {
                key.y = true;
            },
            122 => {
                key.z = true;
            },
            123 => {
                key.shift = true;
                key.@"{" = true;
            },
            124 => {
                key.shift = true;
                key.@"\\" = true;
                try keys.append(allocator, key);

                key = std.mem.zeroes(Key);
                key.@"|" = true;
            },
            125 => {
                key.shift = true;
                key.@"}" = true;
            },
            126 => {
                key.shift = true;
                key.@"`" = true;
                try keys.append(allocator, key);

                key = std.mem.zeroes(Key);
                key.@"~" = true;
            },
            127 => {
                key.ctrl = true;
                key.@"8" = true;
                try keys.append(allocator, key);

                key = std.mem.zeroes(Key);
                key.backspace = true;
            },
            else => {},
        }
    }

    try keys.append(allocator, key);

    return keys;
}
