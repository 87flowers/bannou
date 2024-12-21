/// represents polynomial of size 2^n
pub fn Gf2(comptime n: u4) type {
    const T = std.meta.Int(.unsigned, n);
    const primitive_polynomial: MinPoly(n) = switch (n) {
        3 => (1 << 3) + (1 << 1) + 1,
        4 => (1 << 4) + (1 << 1) + 1,
        5 => (1 << 5) + (1 << 2) + 1,
        6 => (1 << 6) + (1 << 1) + 1,
        7 => (1 << 7) + (1 << 1) + 1,
        8 => (1 << 8) + (1 << 4) + (1 << 3) + (1 << 2) + 1,
        9 => (1 << 9) + (1 << 4) + 1,
        10 => (1 << 10) + (1 << 3) + 1,
        11 => (1 << 11) + (1 << 2) + 1,
        12 => (1 << 12) + (1 << 6) + (1 << 4) + (1 << 1) + 1,
        13 => (1 << 13) + (1 << 4) + (1 << 3) + (1 << 1) + 1,
        14 => (1 << 14) + (1 << 8) + (1 << 6) + (1 << 1) + 1,
        15 => (1 << 15) + (1 << 1) + 1,
        else => unreachable,
    };
    const trunc_pp: T = @truncate(primitive_polynomial);
    return struct {
        const bit_count = n;
        value: T = 0,

        pub fn init(value: T) @This() {
            return .{ .value = value };
        }

        pub fn msb(a: @This()) u1 {
            return @truncate(a.value >> (n - 1));
        }

        pub fn add(a: @This(), b: @This()) @This() {
            return .{ .value = a.value ^ b.value };
        }

        pub fn double(a: @This()) @This() {
            return .{ .value = (a.value << 1) ^ (a.msb() * trunc_pp) };
        }

        pub fn mul(a: @This(), b: @This()) @This() {
            var result: @This() = .{};
            for (0..n) |i| {
                result = result.double();
                const bit: u1 = @truncate(b.value >> @intCast(n - i - 1));
                if (bit == 1) {
                    result = result.add(a);
                }
            }
            return result;
        }

        pub fn pow(a: @This(), e: usize) @This() {
            var result = @This().init(1);
            for (0..e) |_| {
                result = result.mul(a);
            }
            return result;
        }

        pub fn evalWithPoly(x: @This(), poly: anytype) @This() {
            comptime assert(@typeInfo(@TypeOf(poly)) == .int and @typeInfo(@TypeOf(poly)).int.signedness == .unsigned);

            var result = @This().init(0);
            var term = @This().init(1);
            var p = poly;
            while (p != 0) : (p >>= 1) {
                const bit: u1 = @truncate(p);
                if (bit == 1) {
                    result = result.add(term);
                }
                term = term.mul(x);
            }
            return result;
        }

        pub fn findMinPoly(x: @This()) MinPoly(n) {
            var poly: MinPoly(n) = 1;
            while (true) : (poly += 1) {
                if (x.evalWithPoly(poly).value == 0) {
                    return poly;
                }
            }
        }
    };
}

pub fn MinPoly(comptime n: u4) type {
    return std.meta.Int(.unsigned, n + 1);
}

pub fn MinPolys(comptime n: u4) type {
    return std.BoundedArray(MinPoly(n), 1 << n);
}

pub fn generateMinPolys(comptime n: u4) MinPolys(n) {
    const a = Gf2(n).init(2);
    var result = MinPolys(n){};
    for (1..1 << n - 1) |i| {
        const poly = a.pow(i).findMinPoly();
        if (!std.mem.containsAtLeast(@TypeOf(poly), result.slice(), 1, &.{poly})) {
            result.appendAssumeCapacity(poly);
        }
    }
    return result;
}

pub fn Generator(comptime n: u4) type {
    return std.meta.Int(.unsigned, 1 << n);
}

pub fn Generators(comptime n: u4) type {
    return std.BoundedArray(Generator(n), 1 << n);
}

pub fn generateGenerators(comptime n: u4, min_polys: MinPolys(n)) Generators(n) {
    assert(min_polys.len > 0);
    var result = Generators(n){};
    result.appendAssumeCapacity(min_polys.get(0));
    for (1..min_polys.len) |i| {
        const prev = result.get(i - 1);
        result.appendAssumeCapacity(clmul(Generator(n), prev, min_polys.get(i)));
    }
    return result;
}

const std = @import("std");
const assert = std.debug.assert;
const clmul = @import("bit.zig").clmul;
