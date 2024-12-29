pub fn toZhash(row: bch.Row(9)) u64 {
    return @bitReverse(@as(u64, @truncate(row)));
}

pub fn main() !void {
    var output = std.io.getStdOut().writer();

    const bm = bch.genBasisMatrix(9, 64);
    const pm = bch.genParityMatrix(9, bm);

    const Hash = u64;
    try output.print("pub const Hash = u64;\n\n", .{});

    try output.print("const piece_table = [12 * 128]Hash{{\n", .{});
    for (0..12) |pc| {
        const ptype = pc >> 1;
        const color = pc & 1;
        const ptype_label = [_][]const u8{ "Pawn", "Knight", "Bishop", "Rook", "Queen", "King" };
        const color_label = [_][]const u8{ "White", "Black" };
        try output.print("    // {s} {s}\n", .{ color_label[color], ptype_label[ptype] });
        for (0..64) |where| {
            if (where % 8 == 0) {
                try output.print("    ", .{});
            }

            const pm_index = ptype * 64 + where;
            const hb: Hash = toZhash(pm[6 * 64 + where]);
            const hp: Hash = toZhash(pm[pm_index]);

            const h = hp ^ (if (color == 1) hb else 0);

            try output.print("0x{X:016}, ", .{h});

            if (where % 8 == 7) {
                try output.print("0, 0, 0, 0, 0, 0, 0, 0,\n", .{});
            }
        }
    }
    try output.print("}};\n", .{});

    try output.print("\n", .{});

    try output.print("const enpassant_table = [16]Hash{{\n", .{});
    try output.print("    ", .{});
    for (0..8) |i| {
        const h: Hash = toZhash(pm[7 * 64 + i]);
        try output.print("0x{X:016}, ", .{h});
    }
    try output.print("0, 0, 0, 0, 0, 0, 0, 0,\n", .{});
    try output.print("}};\n", .{});

    try output.print("\n", .{});

    try output.print("const base_castle_table = [4]Hash{{\n", .{});
    for (0..4) |i| {
        const h: Hash = toZhash(pm[7 * 64 + 8 + i]);
        try output.print("    0x{X:016},\n", .{h});
    }
    try output.print("}};\n", .{});

    try output.print("\n", .{});

    const bh: Hash = toZhash(pm[7 * 64 + 8 + 4 + 0]);
    try output.print("pub const move: Hash = 0x{X:016};\n", .{bh});
}

const std = @import("std");
const bch = @import("util/bch.zig");
const coord = @import("coord.zig");
