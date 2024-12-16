pub fn Vector(comptime T: type, comptime max_size: usize) type {
    return struct {
        items: [max_size]T = undefined,
        len: usize = 0,

        pub fn append(self: *@This(), item: T) void {
            self.items[self.len] = item;
            self.len += 1;
        }

        pub fn slice(self: *const @This()) []const T {
            return self.items[0..self.len];
        }

        pub fn mutSlice(self: *@This()) []T {
            return self.items[0..self.len];
        }

        pub fn contains(self: *const @This(), item: T) bool {
            return std.mem.containsAtLeast(T, self.slice(), 1, &.{item});
        }
    };
}

const std = @import("std");
