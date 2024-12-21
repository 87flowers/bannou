pub fn genParityMatrix(comptime n: u4, bm: Matrix(n)) Matrix(n) {
    var result = bm;
    for (0..rowBits(n)) |j| {
        const i = rowBits(n) - j - 1;
        for (0..j) |k| {
            const mask = @as(Row(n), 1) << @intCast(i);
            const bit = result[k] & mask;
            if (bit != 0) result[k] ^= result[j] & ~mask;
        }
    }
    return result;
}

pub fn genBasisMatrix(comptime n: u4, m: usize) Matrix(n) {
    const min_polys = polynomial.generateMinPolys(n);
    const generators = polynomial.generateGenerators(n, min_polys);

    var use_gs = std.BoundedArray(Row(n), 1 << n + 2){};
    use_gs.appendAssumeCapacity(0);
    use_gs.appendAssumeCapacity(1);
    for (generators.slice()) |g| {
        use_gs.appendAssumeCapacity(@intCast(g));
        if (bitWidth(g) >= m) break;
    }
    std.mem.reverse(Row(n), use_gs.slice());

    var result: Matrix(n) = undefined;
    var g_index: usize = 0;
    for (0..rowBits(n)) |i| {
        while (i > @ctz(@bitReverse(use_gs.get(g_index)))) g_index += 1;
        result[i] = @bitReverse(use_gs.get(g_index)) >> @intCast(i);
    }
    return result;
}

fn rowBits(comptime n: u4) usize {
    return (1 << n) - 1;
}

pub fn Row(comptime n: u4) type {
    return std.meta.Int(.unsigned, rowBits(n));
}

pub fn Matrix(comptime n: u4) type {
    return [rowBits(n)]Row(n);
}

const std = @import("std");
const bitWidth = @import("bit.zig").bitWidth;
const polynomial = @import("polynomial.zig");
