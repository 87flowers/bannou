pub const default_tt_size_mb = 16;

buckets: []Bucket,
allocator: std.mem.Allocator,

fn bucketsFromMb(mb: usize) usize {
    return mb * 1024 * 1024 / @sizeOf(Bucket);
}

pub fn init(allocator: std.mem.Allocator) !TT {
    const n = comptime bucketsFromMb(default_tt_size_mb);
    return .{
        .allocator = allocator,
        .buckets = try allocator.alloc(Bucket, n),
    };
}

pub fn deinit(self: *TT) void {
    self.allocator.free(self.buckets);
}

pub fn setHashSizeMb(self: *TT, mb: usize) !void {
    const n = bucketsFromMb(mb);
    if (n != self.buckets.len) {
        self.allocator.free(self.buckets);
        self.buckets = try self.allocator.alloc(Bucket, n);
    }
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
        // TT replacement policy: Don't let qs entries replace anything important.
        if (new_entry.depth == 0 and old_entry.depth > 0) return;
        bucket.entries[index] = new_entry;
    } else {
        const index = bucket.newIndex();
        bucket.metas[index] = h.meta;
        bucket.entries[index] = new_entry;
    }
}

inline fn decomposeHash(self: *TT, hash: Hash) struct { bucket_index: usize, meta: u8, fragment: Entry.Fragment } {
    const h: u128 = std.math.mulWide(u64, hash, self.buckets.len);
    return .{
        .bucket_index = @intCast(h >> 64),
        .meta = @truncate(h >> (64 - 8)),
        .fragment = @truncate(h >> (64 - 8 - @bitSizeOf(Entry.Fragment))),
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
