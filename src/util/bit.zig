pub fn clmul(comptime T: type, a: T, b: T) T {
    comptime assert(@typeInfo(T) == .int and @typeInfo(T).int.signedness == .unsigned);
    const n = @bitSizeOf(T);
    var result: T = 0;
    for (0..n) |i| {
        result <<= 1;
        const bit: u1 = @truncate(b >> @intCast(n - i - 1));
        if (bit == 1) {
            result ^= a;
        }
    }
    return result;
}

pub fn clmod(comptime T: type, a: T, b: T) struct { T, T } {
    comptime assert(@typeInfo(T) == .int and @typeInfo(T).int.signedness == .unsigned);
    const n = @bitSizeOf(T);
    const lim = @clz(b);
    var quotient: T = 0;
    var rem = a;
    for (0..lim + 1) |i| {
        const bit: u1 = @truncate(rem >> @intCast(n - i - 1));
        quotient <<= 1;
        if (bit == 1) {
            rem ^= b << @intCast(lim - i);
            quotient |= 1;
        }
    }
    return .{ quotient, rem };
}

pub fn bitWidth(x: anytype) usize {
    comptime assert(@typeInfo(@TypeOf(x)) == .int and @typeInfo(@TypeOf(x)).int.signedness == .unsigned);
    return @bitSizeOf(@TypeOf(x)) - @clz(x);
}

const std = @import("std");
const assert = std.debug.assert;
