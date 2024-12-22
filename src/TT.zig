const bucket_shift = 15;
const num_buckets = 1 << bucket_shift;

buckets: [num_buckets]Bucket,

pub fn clear(self: *TT) void {
    @memset(&self.buckets, std.mem.zeroes(Bucket));
}

pub fn load(self: *TT, hash: Hash) Entry {
    const h = decomposeHash(hash);
    const bucket: *Bucket = &self.buckets[h.bucket_index];
    const index = bucket.getIndex(h.meta) orelse return Entry.empty;
    const entry: Entry = bucket.entries[index];
    if (entry.fragment != h.fragment) return Entry.empty;
    return entry;
}

pub fn store(self: *TT, hash: Hash, depth: i8, best_move: MoveCode, bound: Bound, score: Score) void {
    const h = decomposeHash(hash);
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

fn decomposeHash(hash: Hash) struct { bucket_index: usize, meta: u8, fragment: Entry.Fragment } {
    return .{
        .bucket_index = hash % num_buckets,
        .meta = @truncate(hash >> bucket_shift),
        .fragment = @truncate(hash >> (bucket_shift + 8))
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
    pub const Fragment = u25;

    depth: i8,
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
