pub const default_tt_size_mb = 4;

buckets: []Bucket,
allocator: std.mem.Allocator,

fn bucketsFromMb(mb: usize) usize {
    return mb * 1024 * 1024 / @sizeOf(Bucket);
}

pub fn init(allocator: std.mem.Allocator) !TT {
    const n = comptime bucketsFromMb(default_tt_size_mb);
    comptime assert(n == 1 << 15);
    return .{
        .allocator = allocator,
        .buckets = try allocator.alloc(Bucket, n),
    };
}

pub fn deinit(self: *TT) !void {
    self.allocator.free(self.buckets);
}

pub fn clear(self: *TT) void {
    @memset(self.buckets, std.mem.zeroes(Bucket));
}

pub fn load(self: *TT, hash: Hash) Entry {
    const h = self.decomposeHash(hash);
    const bucket: *Bucket = &self.buckets[h.bucket_index];
    const index = bucket.getIndex(h.meta) orelse return Entry.empty;
    const entry: Entry = bucket.entries[index];
    if (entry.fragment != h.fragment) return Entry.empty;
    return entry;
}

pub fn store(self: *TT, hash: Hash, depth: u7, best_move: MoveCode, bound: Bound, score: Score) void {
    const h = self.decomposeHash(hash);
    const bucket: *Bucket = &self.buckets[h.bucket_index];
    const new_entry = Entry{
        .fragment = h.fragment,
        .depth = depth,
        .raw_move_code = @intCast(best_move.code),
        .bound = bound,
        .score = score,
    };
    if (bucket.getIndex(h.meta)) |index| {
        assert(bucket.metas[index] == h.meta);
        const old_entry = bucket.entries[index];
        // TT replacement policy: Replace if hash doesn't match or if deeper or equal depth.
        if (old_entry.fragment == new_entry.fragment and old_entry.depth > new_entry.depth) return;
        bucket.entries[index] = new_entry;
    } else {
        const index = bucket.newIndex();
        bucket.metas[index] = h.meta;
        bucket.entries[index] = new_entry;
    }
}

inline fn decomposeHash(self: *TT, hash: Hash) struct { bucket_index: usize, meta: u8, fragment: Entry.Fragment } {
    const shift = std.math.log2(self.buckets.len);
    const rest = hash >> @intCast(shift);
    return .{
        .bucket_index = hash & (self.buckets.len - 1),
        .meta = @truncate(rest),
        .fragment = @truncate(rest >> 8),
    };
}

const Bucket = struct {
    const Metas = @Vector(16, u8);

    metas: Metas,
    entries: [14]Entry,

    fn getIndex(self: *Bucket, meta: u8) ?usize {
        const matches: u16 = @bitCast(self.metas == @as(Metas, @splat(meta)));
        const index = @ctz(matches);
        return if (index < self.entries.len) index else null;
    }

    fn newIndex(self: *Bucket) usize {
        const i = (self.metas[15] + 1) % 14;
        self.metas[15] = i;
        return i;
    }
};

test Bucket {
    comptime assert(@sizeOf(Bucket) == 128);
}

pub const Entry = packed struct(u64) {
    pub const Fragment = u26;

    depth: u7,
    raw_move_code: u15,
    bound: Bound,
    score: Score,
    fragment: Fragment,

    pub const empty: Entry = @bitCast(@as(u64, 0));
    pub fn isEmpty(entry: Entry) bool {
        return entry.bound == .empty;
    }

    pub fn move(entry: Entry) MoveCode {
        return .{ .code = entry.raw_move_code };
    }
};

pub const Bound = enum(u2) { empty = 0, lower, exact, upper };

const TT = @This();
const std = @import("std");
const assert = std.debug.assert;
const Hash = @import("zhash.zig").Hash;
const MoveCode = @import("MoveCode.zig");
const Score = @import("eval.zig").Score;
