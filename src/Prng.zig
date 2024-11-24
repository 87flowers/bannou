state: [4]u64,

pub fn init() Prng {
    const key = [32]u8{
        'b', 'a', 'n', 'n', 'o', 'u', 'r', 'n',
        'g', 'h', 'a', 's', 'h', 'k', 'e', 'y',
        'I', 'A', 'M', 'A', 'C', 'H', 'E', 'S',
        'S', 'E', 'N', 'G', 'I', 'N', 'E', '!',
    };
    return .{ .state = .{
        std.mem.readInt(u64, key[0..8], .little),
        std.mem.readInt(u64, key[8..16], .little),
        std.mem.readInt(u64, key[16..24], .little),
        std.mem.readInt(u64, key[24..32], .little),
    } };
}

pub fn next(self: *Prng) u64 {
    const result = std.math.rotl(u64, self.state[0] +% self.state[3], 23) +% self.state[0];
    const t = self.state[1] << 17;
    self.state[2] ^= self.state[0];
    self.state[3] ^= self.state[1];
    self.state[1] ^= self.state[2];
    self.state[0] ^= self.state[3];
    self.state[2] ^= t;
    self.state[3] = std.math.rotl(u64, self.state[3], 45);
    return result;
}

const Prng = @This();
const std = @import("std");
