const std = @import("std");
const interop = @import("../interop.zig");
const termbox = interop.termbox;

pub fn tb_get_cell(x: c_int, y: c_int, back: c_int, cell: *termbox.tb_cell) c_int {
    if (back == 0) {
        return termbox.TB_ERR;
    }

    const width = termbox.tb_width();
    const height = termbox.tb_height();

    if (x < 0 or x >= width or y < 0 or y >= height) {
        return termbox.TB_ERR_OUT_OF_BOUNDS;
    }

    const buffer = termbox.tb_cell_buffer();
    if (buffer == null) {
        return termbox.TB_ERR_NOT_INIT;
    }

    const index = y * width + x;
    cell.* = buffer[@intCast(index)];

    return termbox.TB_OK;
}
