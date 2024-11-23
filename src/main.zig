const ParseError = error{
    InvalidChar,
    InvalidLength,
    DuplicateKing,
    TooManyPieces,
    OutOfRange,
};

const PieceType = enum(u3) {
    none = 0,
    k = 6,
    q = 5,
    r = 4,
    b = 3,
    n = 2,
    p = 1,

    pub fn toChar(self: PieceType, color: Color) u8 {
        return @as(u8, switch (self) {
            .none => '.',
            .k => switch (color) {
                .black => 'k',
                .white => 'K',
            },
            .q => switch (color) {
                .black => 'q',
                .white => 'Q',
            },
            .r => switch (color) {
                .black => 'r',
                .white => 'R',
            },
            .b => switch (color) {
                .black => 'b',
                .white => 'B',
            },
            .n => switch (color) {
                .black => 'n',
                .white => 'N',
            },
            .p => switch (color) {
                .black => 'p',
                .white => 'P',
            },
        });
    }
    pub fn parse(ch: u8) ParseError!struct { PieceType, Color } {
        return switch (ch) {
            'K' => .{ .k, .white },
            'k' => .{ .k, .black },
            'Q' => .{ .q, .white },
            'q' => .{ .q, .black },
            'R' => .{ .r, .white },
            'r' => .{ .r, .black },
            'B' => .{ .b, .white },
            'b' => .{ .b, .black },
            'N' => .{ .n, .white },
            'n' => .{ .n, .black },
            'P' => .{ .p, .white },
            'p' => .{ .p, .black },
            else => ParseError.InvalidChar,
        };
    }
};

const Color = enum(u1) {
    white = 0,
    black = 1,
    pub fn invert(self: Color) Color {
        return @enumFromInt(~@intFromEnum(self));
    }
    pub fn backRank(self: Color) u8 {
        return @as(u8, @bitCast(-@as(i8, @intFromEnum(self)))) & 0x70;
    }
    pub fn idBase(self: Color) u5 {
        return @as(u5, @intFromEnum(self)) << 4;
    }
    pub fn toChar(self: Color) u8 {
        return switch (self) {
            .white => 'w',
            .black => 'b',
        };
    }
    pub fn format(self: Color, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{c}", .{self.toChar()});
    }
    pub fn parse(ch: u8) ParseError!Color {
        return switch (ch) {
            'w' => .white,
            'b' => .black,
            else => ParseError.InvalidChar,
        };
    }
};

pub fn getColor(id: u5) Color {
    return @enumFromInt(id >> 4);
}

/// 0 = white, 1 = black
pub fn toIndex(id: u5) u1 {
    return @intFromEnum(getColor(id));
}

const Place = packed struct {
    id: u5,
    ptype: PieceType,
};

const empty_place = Place{
    .ptype = .none,
    .id = 0,
};

fn stringFromCoord(coord: u8) [2]u8 {
    return .{ 'a' + (coord & 0xF), '1' + (coord >> 4) };
}

fn coordFromString(str: [2]u8) ParseError!u8 {
    if (str[0] < 'a' or str[0] > 'h') return ParseError.InvalidChar;
    if (str[1] < '1' or str[1] > '8') return ParseError.InvalidChar;
    return (str[0] - 'a') + ((str[1] - '1') << 4);
}

test stringFromCoord {
    for (0..256) |i| {
        const coord: u8 = @truncate(i);
        if (isValidCoord(coord)) {
            try std.testing.expectEqual(coord, try coordFromString(stringFromCoord(coord)));
        }
    }
}

fn compressCoord(coord: u8) u6 {
    assert(isValidCoord(coord));
    return @truncate((coord + (coord & 7)) >> 1);
}

fn uncompressCoord(comp: u6) u8 {
    return @as(u8, comp & 0b111000) + @as(u8, comp);
}

test compressCoord {
    for (0..256) |i| {
        const coord: u8 = @truncate(i);
        if (isValidCoord(coord)) {
            try std.testing.expectEqual(coord, uncompressCoord(compressCoord(coord)));
        }
    }
}

fn bitFromCoord(coord: u8) u64 {
    return @as(u64, 1) << compressCoord(coord);
}

fn isValidCoord(coord: u8) bool {
    return (coord & 0x88) == 0;
}

const wk_castle_mask = bitFromCoord(0x04) | bitFromCoord(0x07);
const wq_castle_mask = bitFromCoord(0x04) | bitFromCoord(0x00);
const bk_castle_mask = bitFromCoord(0x74) | bitFromCoord(0x77);
const bq_castle_mask = bitFromCoord(0x74) | bitFromCoord(0x70);
const any_castle_mask = wk_castle_mask | wq_castle_mask | bk_castle_mask | bq_castle_mask;

const castle_masks = [2][2]u64{
    [2]u64{ wk_castle_mask, wq_castle_mask },
    [2]u64{ bk_castle_mask, bq_castle_mask },
};

const State = struct {
    /// bitboard of locations which pieces have been moved from
    castle: u64,
    /// enpassant square coordinate (if invalid then no enpassant square valid)
    enpassant: u8,
    /// for 50 move rule (in half-moves)
    no_capture_clock: u8,
    /// current move number (in half-moves)
    ply: u16,
    /// Zorbrist hash for position
    hash: u64,

    pub fn format(self: State, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        // castling state
        var hasCastle = false;
        if (self.castle & wk_castle_mask == 0) {
            try writer.print("K", .{});
            hasCastle = true;
        }
        if (self.castle & wq_castle_mask == 0) {
            try writer.print("Q", .{});
            hasCastle = true;
        }
        if (self.castle & bk_castle_mask == 0) {
            try writer.print("k", .{});
            hasCastle = true;
        }
        if (self.castle & bq_castle_mask == 0) {
            try writer.print("q", .{});
            hasCastle = true;
        }
        if (!hasCastle) try writer.print("-", .{});
        if (isValidCoord(self.enpassant)) {
            try writer.print(" {s} ", .{stringFromCoord(self.enpassant)});
        } else {
            try writer.print(" - ", .{});
        }
        // move counts
        try writer.print("{} {}", .{ self.no_capture_clock, (self.ply >> 1) + 1 });
    }
    pub fn parseParts(active_color: Color, castle_str: []const u8, enpassant_str: []const u8, no_capture_clock_str: []const u8, ply_str: []const u8) !State {
        var result: State = .{
            .castle = ~@as(u64, 0),
            .enpassant = 0xFF,
            .no_capture_clock = undefined,
            .ply = undefined,
            .hash = undefined,
        };
        if (!std.mem.eql(u8, castle_str, "-")) {
            var i: usize = 0;
            while (i < castle_str.len and castle_str[i] != ' ') : (i += 1) {
                switch (castle_str[i]) {
                    'K', 'H' => result.castle &= ~wk_castle_mask,
                    'Q', 'A' => result.castle &= ~wq_castle_mask,
                    'k', 'h' => result.castle &= ~bk_castle_mask,
                    'q', 'a' => result.castle &= ~bq_castle_mask,
                    else => return ParseError.InvalidChar,
                }
            }
        }
        if (!std.mem.eql(u8, enpassant_str, "-")) {
            if (enpassant_str.len != 2) return ParseError.InvalidLength;
            result.enpassant = try coordFromString(enpassant_str[0..2].*);
        }
        result.no_capture_clock = try std.fmt.parseUnsigned(u8, no_capture_clock_str, 10);
        if (result.no_capture_clock > 200) return ParseError.OutOfRange;
        result.ply = try std.fmt.parseUnsigned(u16, ply_str, 10);
        if (result.ply < 1 or result.ply > 10000) return ParseError.OutOfRange;
        result.ply = (result.ply - 1) * 2 + @intFromEnum(active_color);
        return result;
    }
};

const MoveType = enum {
    normal,
    castle,
};

const MoveCode = struct {
    code: u16,
    pub fn isPromotion(self: MoveCode) bool {
        return self.code & 7 != 0;
    }
    pub fn src(self: MoveCode) u8 {
        return uncompressCoord(@truncate(self.code >> 9));
    }
    pub fn dest(self: MoveCode) u8 {
        return uncompressCoord(@truncate(self.code >> 3));
    }
    pub fn make(src_ptype: PieceType, src_coord: u8, dest_ptype: PieceType, dest_coord: u8) MoveCode {
        return .{
            .code = @as(u16, compressCoord(src_coord)) << 9 |
                @as(u16, compressCoord(dest_coord)) << 3 |
                if (src_ptype != dest_ptype) @as(u16, @intFromEnum(dest_ptype)) else 0,
        };
    }
    pub fn format(self: MoveCode, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        const ptype: PieceType = @enumFromInt(self.code & 7);
        try writer.print("{c}{c}{c}{c}", .{
            'a' + @as(u8, @truncate(self.code >> 9 & 7)),
            '1' + @as(u8, @truncate(self.code >> 12 & 7)),
            'a' + @as(u8, @truncate(self.code >> 3 & 7)),
            '1' + @as(u8, @truncate(self.code >> 6 & 7)),
        });
        if (ptype != .none) try writer.print("{c}", .{ptype.toChar(.black)});
    }
    pub fn parse(str: []const u8) ParseError!MoveCode {
        var result: u16 = 0;
        if (str.len < 4 or str.len > 5) return ParseError.InvalidLength;
        if (str[0] < 'a' or str[0] > 'h') return ParseError.InvalidChar;
        result |= @as(u16, str[0] - 'a') << 9;
        if (str[1] < '1' or str[1] > '8') return ParseError.InvalidChar;
        result |= @as(u16, str[1] - '1') << 12;
        if (str[2] < 'a' or str[2] > 'h') return ParseError.InvalidChar;
        result |= @as(u16, str[2] - 'a') << 3;
        if (str[3] < '1' or str[3] > '8') return ParseError.InvalidChar;
        result |= @as(u16, str[3] - '1') << 6;
        if (str.len > 4) {
            const ptype, _ = try PieceType.parse(str[4]);
            result |= @intFromEnum(ptype);
        }
        return .{ .code = result };
    }
};

const Move = struct {
    code: MoveCode,
    id: u5,
    src_coord: u8,
    src_ptype: PieceType,
    dest_coord: u8,
    dest_ptype: PieceType,
    capture_coord: u8,
    capture_place: Place,
    state: State,
    mtype: MoveType,

    pub fn format(self: Move, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{}", .{self.code});
    }
};

const MoveList = struct {
    moves: [256]Move = undefined,
    size: u8 = 0,

    pub fn sort(self: *MoveList, pv: MoveCode) void {
        var sort_scores: [256]u32 = undefined;
        for (0..self.size) |i| {
            const m = self.moves[i];
            if (m.code.code == pv.code) {
                sort_scores[i] = std.math.maxInt(u32);
                continue;
            }
            if (m.capture_place != empty_place) {
                sort_scores[i] = 100000 + @as(u32, @intFromEnum(m.capture_place.ptype)) - @as(u32, @intFromEnum(m.src_ptype));
            } else {
                sort_scores[i] = 0;
            }
        }
        const Context = struct {
            ml: *MoveList,
            order: []u32,

            pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
                return ctx.order[a] > ctx.order[b];
            }

            pub fn swap(ctx: @This(), a: usize, b: usize) void {
                std.mem.swap(Move, &ctx.ml.moves[a], &ctx.ml.moves[b]);
                std.mem.swap(u32, &ctx.order[a], &ctx.order[b]);
            }
        };
        std.sort.heapContext(0, self.size, Context{ .ml = self, .order = &sort_scores });
    }

    const HasCapture = enum { capture, no_capture };

    pub fn add(self: *MoveList, state: State, ptype: PieceType, id: u5, src: u8, dest: u8) void {
        self.moves[self.size] = .{
            .code = MoveCode.make(ptype, src, ptype, dest),
            .id = id,
            .src_coord = src,
            .src_ptype = ptype,
            .dest_coord = dest,
            .dest_ptype = ptype,
            .capture_coord = dest,
            .capture_place = empty_place,
            .state = .{
                .castle = state.castle | bitFromCoord(src),
                .enpassant = 0xFF,
                .no_capture_clock = state.no_capture_clock + 1,
                .ply = state.ply + 1,
                .hash = state.hash ^
                    zhashPiece(getColor(id), ptype, src) ^
                    zhashPiece(getColor(id), ptype, dest) ^
                    state.enpassant ^
                    0xFF ^
                    zhashCastle(state.castle) ^
                    zhashCastle((state.castle | bitFromCoord(src))),
            },
            .mtype = .normal,
        };
        self.size += 1;
    }

    pub fn addPawnOne(self: *MoveList, state: State, ptype: PieceType, id: u5, src: u8, dest: u8, capture_place: Place, comptime has_capture: HasCapture) void {
        assert((has_capture == .capture) != (capture_place == empty_place));
        self.moves[self.size] = .{
            .code = MoveCode.make(ptype, src, ptype, dest),
            .id = id,
            .src_coord = src,
            .src_ptype = ptype,
            .dest_coord = dest,
            .dest_ptype = ptype,
            .capture_coord = dest,
            .capture_place = capture_place,
            .state = .{ .castle = state.castle, .enpassant = 0xFF, .no_capture_clock = 0, .ply = state.ply + 1, .hash = state.hash ^
                zhashPiece(getColor(id), ptype, src) ^
                zhashPiece(getColor(id), ptype, dest) ^
                switch (has_capture) {
                .capture => zhashPiece(getColor(id).invert(), capture_place.ptype, dest),
                .no_capture => 0,
            } ^
                state.enpassant ^
                0xFF },
            .mtype = .normal,
        };
        self.size += 1;
    }

    pub fn addPawnTwo(self: *MoveList, state: State, ptype: PieceType, id: u5, src: u8, dest: u8, enpassant: u8) void {
        self.moves[self.size] = .{
            .code = MoveCode.make(ptype, src, ptype, dest),
            .id = id,
            .src_coord = src,
            .src_ptype = ptype,
            .dest_coord = dest,
            .dest_ptype = ptype,
            .capture_coord = dest,
            .capture_place = empty_place,
            .state = .{ .castle = state.castle, .enpassant = enpassant, .no_capture_clock = 0, .ply = state.ply + 1, .hash = state.hash ^
                zhashPiece(getColor(id), ptype, src) ^
                zhashPiece(getColor(id), ptype, dest) ^
                state.enpassant ^
                enpassant },
            .mtype = .normal,
        };
        self.size += 1;
    }

    pub fn addPawnPromotion(self: *MoveList, state: State, src_ptype: PieceType, id: u5, src: u8, dest: u8, capture_place: Place, dest_ptype: PieceType, comptime has_capture: HasCapture) void {
        assert((has_capture == .capture) != (capture_place == empty_place));
        self.moves[self.size] = .{
            .code = MoveCode.make(src_ptype, src, dest_ptype, dest),
            .id = id,
            .src_coord = src,
            .src_ptype = src_ptype,
            .dest_coord = dest,
            .dest_ptype = dest_ptype,
            .capture_coord = dest,
            .capture_place = capture_place,
            .state = .{
                .castle = state.castle | bitFromCoord(dest),
                .enpassant = 0xFF,
                .no_capture_clock = 0,
                .ply = state.ply + 1,
                .hash = state.hash ^
                    zhashPiece(getColor(id), src_ptype, src) ^
                    zhashPiece(getColor(id), dest_ptype, dest) ^
                    switch (has_capture) {
                    .capture => zhashPiece(getColor(id).invert(), capture_place.ptype, dest),
                    .no_capture => 0,
                } ^
                    state.enpassant ^
                    0xFF ^
                    zhashCastle(state.castle) ^
                    zhashCastle((state.castle | bitFromCoord(dest))),
            },
            .mtype = .normal,
        };
        self.size += 1;
    }

    pub fn addCapture(self: *MoveList, state: State, ptype: PieceType, id: u5, src: u8, dest: u8, capture_place: Place) void {
        assert(getColor(id).invert() == getColor(capture_place.id));
        self.moves[self.size] = .{
            .code = MoveCode.make(ptype, src, ptype, dest),
            .id = id,
            .src_coord = src,
            .src_ptype = ptype,
            .dest_coord = dest,
            .dest_ptype = ptype,
            .capture_coord = dest,
            .capture_place = capture_place,
            .state = .{
                .castle = state.castle | bitFromCoord(src) | bitFromCoord(dest),
                .enpassant = 0xFF,
                .no_capture_clock = 0,
                .ply = state.ply + 1,
                .hash = state.hash ^
                    zhashPiece(getColor(id), ptype, src) ^
                    zhashPiece(getColor(id), ptype, dest) ^
                    zhashPiece(getColor(id).invert(), capture_place.ptype, dest) ^
                    state.enpassant ^
                    0xFF ^
                    zhashCastle(state.castle) ^
                    zhashCastle((state.castle | bitFromCoord(src) | bitFromCoord(dest))),
            },
            .mtype = .normal,
        };
        self.size += 1;
    }

    pub fn addEnpassant(self: *MoveList, state: State, ptype: PieceType, id: u5, src: u8, capture_coord: u8, capture_place: Place) void {
        assert(isValidCoord(state.enpassant));
        assert(getColor(id).invert() == getColor(capture_place.id));
        self.moves[self.size] = .{
            .code = MoveCode.make(ptype, src, ptype, state.enpassant),
            .id = id,
            .src_coord = src,
            .src_ptype = ptype,
            .dest_coord = state.enpassant,
            .dest_ptype = ptype,
            .capture_coord = capture_coord,
            .capture_place = capture_place,
            .state = .{ .castle = state.castle, .enpassant = 0xFF, .no_capture_clock = 0, .ply = state.ply + 1, .hash = state.hash ^
                zhashPiece(getColor(id), ptype, src) ^
                zhashPiece(getColor(id), ptype, state.enpassant) ^
                zhashPiece(getColor(id).invert(), capture_place.ptype, capture_coord) ^
                state.enpassant ^
                0xFF },
            .mtype = .normal,
        };
        self.size += 1;
    }

    pub fn addCastle(self: *MoveList, state: State, rook_id: u5, src_rook: u8, dest_rook: u8, src_king: u8, dest_king: u8) void {
        self.moves[self.size] = .{
            .code = MoveCode.make(.k, src_king, .k, dest_king),
            .id = rook_id,
            .src_coord = src_rook,
            .src_ptype = .r,
            .dest_coord = dest_rook,
            .dest_ptype = .r,
            .capture_coord = dest_rook,
            .capture_place = empty_place,
            .state = .{
                .castle = state.castle | bitFromCoord(src_rook) | bitFromCoord(src_king),
                .enpassant = 0xFF,
                .no_capture_clock = state.no_capture_clock + 1,
                .ply = state.ply + 1,
                .hash = state.hash ^
                    zhashPiece(getColor(rook_id), .k, src_king) ^
                    zhashPiece(getColor(rook_id), .k, dest_king) ^
                    zhashPiece(getColor(rook_id), .r, src_rook) ^
                    zhashPiece(getColor(rook_id), .r, dest_rook) ^
                    state.enpassant ^
                    0xFF ^
                    zhashCastle(state.castle) ^
                    zhashCastle((state.castle | bitFromCoord(src_rook) | bitFromCoord(src_king))),
            },
            .mtype = .castle,
        };
        self.size += 1;
    }
};

const Prng = struct {
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
};

const zhash_pieces: [2 * 8 * 0x80]u64 = blk: {
    @setEvalBranchQuota(1000000);
    var prng = Prng.init();
    var result: [2 * 8 * 0x80]u64 = undefined;
    for (&result) |*hash| hash.* = prng.next();
    break :blk result;
};

pub fn zhashPiece(color: Color, ptype: PieceType, coord: u8) u64 {
    const index = @as(usize, @intFromEnum(ptype)) << 8 | @as(usize, @intFromEnum(color)) << 7 | @as(usize, coord);
    return zhash_pieces[index];
}

pub fn zhashCastle(castle: u64) u64 {
    return std.math.rotl(u64, castle & any_castle_mask, 16);
}

const Board = struct {
    pieces: [32]PieceType,
    where: [32]u8,
    board: [128]Place,
    state: State,
    active_color: Color,
    zhistory: [1024]u64,

    pub fn emptyBoard() Board {
        return comptime blk: {
            var result: Board = .{
                .pieces = [1]PieceType{.none} ** 32,
                .where = undefined,
                .board = [1]Place{empty_place} ** 128,
                .state = .{
                    .castle = 0,
                    .enpassant = 0xff,
                    .no_capture_clock = 0,
                    .ply = 0,
                    .hash = undefined,
                },
                .active_color = .white,
                .zhistory = undefined,
            };
            result.state.hash = result.calcHashSlow();
            result.zhistory[result.state.ply] = result.state.hash;
            break :blk result;
        };
    }

    pub fn defaultBoard() Board {
        return comptime blk: {
            var result = emptyBoard();
            result.place(0x01, .r, 0x00);
            result.place(0x03, .n, 0x01);
            result.place(0x05, .b, 0x02);
            result.place(0x07, .q, 0x03);
            result.place(0x00, .k, 0x04);
            result.place(0x06, .b, 0x05);
            result.place(0x04, .n, 0x06);
            result.place(0x02, .r, 0x07);
            result.place(0x08, .p, 0x10);
            result.place(0x09, .p, 0x11);
            result.place(0x0A, .p, 0x12);
            result.place(0x0B, .p, 0x13);
            result.place(0x0C, .p, 0x14);
            result.place(0x0D, .p, 0x15);
            result.place(0x0E, .p, 0x16);
            result.place(0x0F, .p, 0x17);
            result.place(0x11, .r, 0x70);
            result.place(0x13, .n, 0x71);
            result.place(0x15, .b, 0x72);
            result.place(0x17, .q, 0x73);
            result.place(0x10, .k, 0x74);
            result.place(0x16, .b, 0x75);
            result.place(0x14, .n, 0x76);
            result.place(0x12, .r, 0x77);
            result.place(0x18, .p, 0x60);
            result.place(0x19, .p, 0x61);
            result.place(0x1A, .p, 0x62);
            result.place(0x1B, .p, 0x63);
            result.place(0x1C, .p, 0x64);
            result.place(0x1D, .p, 0x65);
            result.place(0x1E, .p, 0x66);
            result.place(0x1F, .p, 0x67);
            result.zhistory[result.state.ply] = result.state.hash;
            break :blk result;
        };
    }

    fn place(self: *Board, id: u5, ptype: PieceType, coord: u8) void {
        assert(self.board[coord] == empty_place and self.pieces[id] == .none);
        self.pieces[id] = ptype;
        self.where[id] = coord;
        self.board[coord] = Place{ .ptype = ptype, .id = id };
        self.state.hash ^= zhashPiece(getColor(id), ptype, coord);
    }

    fn move(self: *Board, m: Move) State {
        const result = self.state;
        switch (m.mtype) {
            .normal => {
                if (m.capture_place != empty_place) {
                    assert(self.pieces[m.capture_place.id] == m.capture_place.ptype);
                    assert(self.board[m.capture_coord] == m.capture_place);
                    self.pieces[m.capture_place.id] = .none;
                    self.board[m.capture_coord] = empty_place;
                }
                assert(self.board[m.src_coord] == Place{ .ptype = m.src_ptype, .id = m.id });
                self.board[m.src_coord] = empty_place;
                self.board[m.dest_coord] = Place{ .ptype = m.dest_ptype, .id = m.id };
                self.where[m.id] = m.dest_coord;
                self.pieces[m.id] = m.dest_ptype;
            },
            .castle => {
                self.board[m.code.src()] = empty_place;
                self.board[m.src_coord] = empty_place;
                self.board[m.code.dest()] = Place{ .ptype = .k, .id = m.id & 0x10 };
                self.board[m.dest_coord] = Place{ .ptype = .r, .id = m.id };
                self.where[m.id & 0x10] = m.code.dest();
                self.where[m.id] = m.dest_coord;
            },
        }
        self.state = m.state;
        self.active_color = self.active_color.invert();
        self.zhistory[m.state.ply] = m.state.hash;
        assert(self.state.hash == self.calcHashSlow());
        return result;
    }

    fn unmove(self: *Board, m: Move, old_state: State) void {
        switch (m.mtype) {
            .normal => {
                self.board[m.dest_coord] = empty_place;
                if (m.capture_place != empty_place) {
                    self.pieces[m.capture_place.id] = m.capture_place.ptype;
                    self.board[m.capture_coord] = m.capture_place;
                }
                self.board[m.src_coord] = Place{ .ptype = m.src_ptype, .id = m.id };
                self.where[m.id] = m.src_coord;
                self.pieces[m.id] = m.src_ptype;
            },
            .castle => {
                self.board[m.code.dest()] = empty_place;
                self.board[m.dest_coord] = empty_place;
                self.board[m.code.src()] = Place{ .ptype = .k, .id = m.id & 0x10 };
                self.board[m.src_coord] = Place{ .ptype = .r, .id = m.id };
                self.where[m.id & 0x10] = m.code.src();
                self.where[m.id] = m.src_coord;
            },
        }
        self.state = old_state;
        self.active_color = self.active_color.invert();
    }

    pub fn format(self: Board, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        var blanks: u32 = 0;
        for (0..64) |i| {
            const j = (i + (i & 0o70)) ^ 0x70;
            const p = self.board[j];
            if (p == empty_place) {
                blanks += 1;
            } else {
                if (blanks != 0) {
                    try writer.print("{}", .{blanks});
                    blanks = 0;
                }
                try writer.print("{c}", .{p.ptype.toChar(getColor(p.id))});
            }
            if (i % 8 == 7) {
                if (blanks != 0) {
                    try writer.print("{}", .{blanks});
                    blanks = 0;
                }
                if (i != 63) try writer.print("/", .{});
            }
        }
        try writer.print(" {} {}", .{ self.active_color, self.state });
    }

    pub fn parseParts(board_str: []const u8, color_str: []const u8, castle_str: []const u8, enpassant_str: []const u8, no_capture_clock_str: []const u8, ply_str: []const u8) !Board {
        var result = Board.emptyBoard();

        {
            var coord: u8 = 0;
            var id: [2]u8 = .{ 1, 1 };
            var i: usize = 0;
            while (coord < 64 and i < board_str.len) : (i += 1) {
                const ch = board_str[i];
                if (ch == '/') continue;
                if (ch >= '1' and ch <= '8') {
                    coord += ch - '0';
                    continue;
                }
                const ptype, const color = try PieceType.parse(ch);
                if (ptype == .k) {
                    if (result.pieces[color.idBase()] != .none) return ParseError.DuplicateKing;
                    result.place(color.idBase(), .k, uncompressCoord(@truncate(coord)) ^ 0x70);
                } else {
                    if (id[@intFromEnum(color)] > 0xf) return ParseError.TooManyPieces;
                    const current_id: u5 = @truncate(color.idBase() + id[@intFromEnum(color)]);
                    result.place(current_id, ptype, uncompressCoord(@truncate(coord)) ^ 0x70);
                    id[@intFromEnum(color)] += 1;
                }
                coord += 1;
            }
            if (coord != 64 or i != board_str.len) return ParseError.InvalidLength;
        }

        if (color_str.len != 1) return ParseError.InvalidLength;
        result.active_color = try Color.parse(color_str[0]);

        result.state = try State.parseParts(result.active_color, castle_str, enpassant_str, no_capture_clock_str, ply_str);
        result.state.hash = result.calcHashSlow();

        return result;
    }

    fn calcHashSlow(self: *const Board) u64 {
        var result: u64 = 0;
        for (0..32) |i| {
            const ptype = self.pieces[i];
            const coord = self.where[i];
            if (ptype != .none) result ^= zhashPiece(getColor(@truncate(i)), ptype, coord);
        }
        result ^= self.state.enpassant;
        result ^= zhashCastle(self.state.castle);
        return result;
    }

    fn debugPrint(self: *const Board) void {
        for (0..64) |i| {
            const j = (i + (i & 0o70)) ^ 0x70;
            const p = self.board[j];
            std.debug.print("{c}", .{p.ptype.toChar(getColor(p.id))});
            if (i % 8 == 7) std.debug.print("\n", .{});
        }
        std.debug.print("{} {}\n", .{ self.active_color, self.state });
    }
};

fn generateSliderMoves(board: *Board, moves: *MoveList, ptype: PieceType, id: u5, src: u8, dirs: anytype) void {
    assert(board.where[id] == src and board.board[src] == Place{ .ptype = ptype, .id = id });
    for (dirs) |dir| {
        var dest: u8 = src +% dir;
        while (isValidCoord(dest)) : (dest +%= dir) {
            if (board.board[dest].ptype != .none) {
                if (getColor(board.board[dest].id) != board.active_color) {
                    moves.addCapture(board.state, ptype, id, src, dest, board.board[dest]);
                }
                break;
            }
            moves.add(board.state, ptype, id, src, dest);
        }
    }
}

fn generateStepperMoves(board: *Board, moves: *MoveList, ptype: PieceType, id: u5, src: u8, dirs: anytype) void {
    assert(board.where[id] == src and board.board[src] == Place{ .ptype = ptype, .id = id });
    for (dirs) |dir| {
        const dest = src +% dir;
        if (isValidCoord(dest)) {
            if (board.board[dest].ptype == .none) {
                moves.add(board.state, ptype, id, src, dest);
            } else if (getColor(board.board[dest].id) != board.active_color) {
                moves.addCapture(board.state, ptype, id, src, dest, board.board[dest]);
            }
        }
    }
}

fn generatePawnMovesMayPromote(board: *Board, moves: *MoveList, isrc: u8, id: u5, src: u8, dest: u8, comptime has_capture: MoveList.HasCapture) void {
    assert(board.where[id] == src and board.board[src] == Place{ .ptype = .p, .id = id });
    if ((isrc & 0xF0) == 0x60) {
        // promotion
        moves.addPawnPromotion(board.state, .p, id, src, dest, board.board[dest], .q, has_capture);
        moves.addPawnPromotion(board.state, .p, id, src, dest, board.board[dest], .r, has_capture);
        moves.addPawnPromotion(board.state, .p, id, src, dest, board.board[dest], .b, has_capture);
        moves.addPawnPromotion(board.state, .p, id, src, dest, board.board[dest], .n, has_capture);
    } else {
        moves.addPawnOne(board.state, .p, id, src, dest, board.board[dest], has_capture);
    }
}

fn invertIfBlack(color: Color) u8 {
    return @as(u8, @bitCast(-@as(i8, @intFromEnum(color)))) & 0x70;
}

fn getPawnCaptures(color: Color, src: u8) [2]u8 {
    const invert = invertIfBlack(color);
    const isrc = src ^ invert;
    return [2]u8{ (isrc + 0x0F) ^ invert, (isrc + 0x11) ^ invert };
}

const diag_dir = [4]u8{ 0xEF, 0xF1, 0x0F, 0x11 };
const ortho_dir = [4]u8{ 0xF0, 0xFF, 0x01, 0x10 };
const all_dir = diag_dir ++ ortho_dir;
const knight_dir = [8]u8{ 0xDF, 0xE1, 0xEE, 0x0E, 0xF2, 0x12, 0x1F, 0x21 };

fn makeMoveByCode(board: *Board, code: MoveCode) bool {
    const p = board.board[code.src()];
    if (p == empty_place) return false;

    var moves = MoveList{};
    generateMovesForPiece(board, &moves, p.id);
    for (moves.moves) |m| {
        if (std.meta.eql(m.code, code)) {
            _ = board.move(m);
            return true;
        }
    }
    return false;
}

fn generateMovesForPiece(board: *Board, moves: *MoveList, id: u5) void {
    const src = board.where[id];
    switch (board.pieces[id]) {
        .none => {},
        .k => {
            generateStepperMoves(board, moves, .k, id, src, all_dir);

            const rank: u8 = board.active_color.backRank();
            if (board.where[id] == rank | 4) {
                const castle_k, const castle_q = castle_masks[@intFromEnum(board.active_color)];
                if (castle_k & board.state.castle == 0 and board.board[rank | 5] == empty_place and board.board[rank | 6] == empty_place) {
                    if (!isAttacked(board, rank | 4, board.active_color) and !isAttacked(board, rank | 5, board.active_color) and !isAttacked(board, rank | 6, board.active_color)) {
                        assert(board.board[rank | 7].ptype == .r and getColor(board.board[rank | 7].id) == board.active_color);
                        moves.addCastle(board.state, board.board[rank | 7].id, rank | 7, rank | 5, rank | 4, rank | 6);
                    }
                }
                if (castle_q & board.state.castle == 0 and board.board[rank | 1] == empty_place and board.board[rank | 2] == empty_place and board.board[rank | 3] == empty_place) {
                    if (!isAttacked(board, rank | 2, board.active_color) and !isAttacked(board, rank | 3, board.active_color) and !isAttacked(board, rank | 4, board.active_color)) {
                        assert(board.board[rank | 0].ptype == .r and getColor(board.board[rank | 0].id) == board.active_color);
                        moves.addCastle(board.state, board.board[rank | 0].id, rank | 0, rank | 3, rank | 4, rank | 2);
                    }
                }
            }
        },
        .q => generateSliderMoves(board, moves, .q, id, src, all_dir),
        .r => generateSliderMoves(board, moves, .r, id, src, ortho_dir),
        .b => generateSliderMoves(board, moves, .b, id, src, diag_dir),
        .n => generateStepperMoves(board, moves, .n, id, src, knight_dir),
        .p => {
            const invert = invertIfBlack(board.active_color);
            const isrc = src ^ invert;
            const onestep = (isrc + 0x10) ^ invert;
            const twostep = (isrc + 0x20) ^ invert;
            const captures = getPawnCaptures(board.active_color, src);

            if ((isrc & 0xF0) == 0x10 and board.board[onestep].ptype == .none and board.board[twostep].ptype == .none) {
                moves.addPawnTwo(board.state, .p, id, src, twostep, onestep);
            }

            for (captures) |capture| {
                if (!isValidCoord(capture)) continue;
                if (capture == board.state.enpassant) {
                    const capture_coord = ((capture ^ invert) - 0x10) ^ invert;
                    moves.addEnpassant(board.state, .p, id, src, capture_coord, board.board[capture_coord]);
                } else if (board.board[capture].ptype != .none and getColor(board.board[capture].id) != board.active_color) {
                    generatePawnMovesMayPromote(board, moves, isrc, id, src, capture, .capture);
                }
            }

            if (board.board[onestep].ptype == .none) {
                generatePawnMovesMayPromote(board, moves, isrc, id, src, onestep, .no_capture);
            }
        },
    }
}

fn generateMoves(board: *Board, moves: *MoveList) void {
    const id_base = board.active_color.idBase();
    for (0..16) |id_index| {
        const id: u5 = @truncate(id_base + id_index);
        generateMovesForPiece(board, moves, id);
    }
}

fn isVisibleBySlider(board: *Board, comptime dirs: anytype, src: u8, dest: u8) bool {
    const lut = comptime blk: {
        var l = [1]u8{0} ** 256;
        for (dirs) |dir| {
            for (1..8) |i| {
                l[@as(u8, @truncate(dir *% i))] = dir;
            }
        }
        break :blk l;
    };
    const vector = dest -% src;
    const dir = lut[vector];
    if (dir == 0) return false;
    var t = src +% dir;
    while (t != dest) : (t +%= dir)
        if (board.board[t] != empty_place)
            return false;
    return true;
}

fn isAttacked(board: *Board, target: u8, friendly: Color) bool {
    const enemy_color = friendly.invert();
    const id_base = enemy_color.idBase();
    for (0..16) |id_index| {
        const id: u5 = @truncate(id_base + id_index);
        const enemy = board.where[id];
        switch (board.pieces[id]) {
            .none => {},
            .k => for (all_dir) |dir| if (target == enemy +% dir) return true,
            .q => if (isVisibleBySlider(board, all_dir, enemy, target)) return true,
            .r => if (isVisibleBySlider(board, ortho_dir, enemy, target)) return true,
            .b => if (isVisibleBySlider(board, diag_dir, enemy, target)) return true,
            .n => for (knight_dir) |dir| if (target == enemy +% dir) return true,
            .p => for (getPawnCaptures(enemy_color, enemy)) |capture| if (target == capture) return true,
        }
    }
    return false;
}

pub fn perft(board: *Board, depth: usize) usize {
    if (depth == 0) return 1;
    var result: usize = 0;
    var moves = MoveList{};
    generateMoves(board, &moves);
    for (0..moves.size) |i| {
        const m = moves.moves[i];
        const old_state = board.move(m);
        if (!isAttacked(board, board.where[board.active_color.invert().idBase()], board.active_color.invert())) {
            result += perft(board, depth - 1);
        }
        board.unmove(m, old_state);
    }
    return result;
}

pub fn divide(output: anytype, board: *Board, depth: usize) !void {
    if (depth == 0) return;
    var result: usize = 0;
    var moves = MoveList{};
    var timer = try std.time.Timer.start();
    generateMoves(board, &moves);
    for (0..moves.size) |i| {
        const m = moves.moves[i];
        const old_state = board.move(m);
        if (!isAttacked(board, board.where[board.active_color.invert().idBase()], board.active_color.invert())) {
            const p = perft(board, depth - 1);
            result += p;
            try output.print("{}: {}\n", .{ m, p });
        }
        board.unmove(m, old_state);
    }
    const elapsed: f64 = @floatFromInt(timer.read());
    try output.print("Nodes searched (depth {}): {}\n", .{ depth, result });
    try output.print("Search completed in {d:.1}ms\n", .{elapsed / std.time.ns_per_ms});
}

const rand = std.crypto.random;
pub fn eval(board: *Board) i32 {
    // detect repetition
    {
        const zcurrent = board.state.hash;

        var i: u16 = board.state.ply - board.state.no_capture_clock;
        i += @intFromEnum(board.active_color.invert());
        i &= ~@as(u16, 1);
        i += @intFromEnum(board.active_color);

        while (i + 4 <= board.state.ply) : (i += 2) {
            if (board.zhistory[i] == zcurrent) {
                return 0;
            }
        }
    }
    // detect 50 move rule
    if (board.state.no_capture_clock >= 100) {
        // TODO: detect if this move is checkmate
        return 0;
    }

    var score: i32 = 0;
    for (0..16) |w| {
        score += switch (board.pieces[w]) {
            .none => 0,
            .k => 1000000,
            .q => 1000,
            .r => 500,
            .b => 310,
            .n => 300,
            .p => 100,
        };
    }
    for (16..32) |b| {
        score += switch (board.pieces[b]) {
            .none => 0,
            .k => -1000000,
            .q => -1000,
            .r => -500,
            .b => -310,
            .n => -300,
            .p => -100,
        };
    }
    score += rand.intRangeAtMostBiased(i32, -20, 20);
    return switch (board.active_color) {
        .white => score,
        .black => -score,
    };
}

const Bound = enum { lower, exact, upper };
const TTEntry = struct {
    hash: u64,
    best_move: MoveCode,
    depth: u8,
    bound: Bound,
    score: i32,
    pub fn empty() TTEntry {
        return .{
            .hash = 0,
            .best_move = .{ .code = 0 },
            .depth = undefined,
            .bound = undefined,
            .score = undefined,
        };
    }
};
test {
    comptime assert(@sizeOf(TTEntry) == 16);
}

const tt_size = 0x1000000;
var tt: [tt_size]TTEntry = [_]TTEntry{TTEntry.empty()} ** tt_size;

pub fn search(board: *Board, alpha: i32, beta: i32, depth: i32) i32 {
    if (depth <= 0) return eval(board);

    const tte = tt[board.state.hash % tt_size];

    var moves = MoveList{};
    generateMoves(board, &moves);
    moves.sort(tte.best_move);

    const no_moves = -std.math.maxInt(i32);
    var best_score: i32 = no_moves;
    var best_move: MoveCode = tte.best_move;

    for (0..moves.size) |i| {
        const m = moves.moves[i];
        const old_state = board.move(m);
        defer board.unmove(m, old_state);
        if (!isAttacked(board, board.where[board.active_color.invert().idBase()], board.active_color.invert())) {
            const child_score = -search(board, -beta, -@max(alpha, best_score), depth - 1);
            if (child_score > best_score) {
                best_score = child_score;
                best_move = m.code;
            }
            if (best_score > beta) break;
        }
    }
    if (best_score == no_moves and !isAttacked(board, board.where[board.active_color.idBase()], board.active_color)) {
        best_score = 0;
    }
    if (best_score < -1073741824) return best_score + 1;

    tt[board.state.hash % tt_size] = .{
        .hash = board.state.hash,
        .best_move = best_move,
        .depth = @intCast(@min(0, depth)),
        .score = best_score,
        .bound = if (best_score >= beta)
            .lower
        else if (@max(alpha, best_score) == alpha)
            .upper
        else
            .exact,
    };

    return best_score;
}

pub fn bestmove(board: *Board, depth: i32) struct { ?Move, i32 } {
    var moves = MoveList{};
    generateMoves(board, &moves);
    var bestmove_i: usize = 0;
    var bestmove_score: i32 = std.math.minInt(i32);
    var valid_move_count: usize = 0;
    for (0..moves.size) |i| {
        const m = moves.moves[i];
        const old_state = board.move(m);
        defer board.unmove(m, old_state);
        if (!isAttacked(board, board.where[board.active_color.invert().idBase()], board.active_color.invert())) {
            const score = -search(board, -std.math.maxInt(i32), -@max(bestmove_score, -std.math.maxInt(i32)), depth);
            if (score > bestmove_score) {
                bestmove_score = score;
                bestmove_i = i;
            }
            valid_move_count += 1;
        }
    }
    if (valid_move_count == 0) return .{ null, bestmove_score };
    return .{ moves.moves[bestmove_i], bestmove_score };
}

const TimeControl = struct {
    wtime: ?u64 = null,
    btime: ?u64 = null,
    winc: ?u64 = null,
    binc: ?u64 = null,
    movestogo: ?u64 = null,
};

pub fn uciGo(output: anytype, board: *Board, tc: TimeControl) !void {
    var timer = try std.time.Timer.start();
    const margin = 1000;
    const movestogo = tc.movestogo orelse 30;
    assert(tc.wtime != null and tc.btime != null);
    const time_remaining = switch (board.active_color) {
        .white => tc.wtime.?,
        .black => tc.btime.?,
    };
    const deadline = (@max(time_remaining, margin) - margin) * 1_000_000 / movestogo; // nanoseconds
    var depth: i32 = 1;
    var rootmove: ?Move = null;
    try output.print("info string pos {}\n", .{board});
    while (deadline / 2 > timer.read() or depth < 2) : (depth += 1) {
        rootmove, const score = bestmove(board, depth);
        try output.print("info string depth {} move {any} score {} time {}\n", .{ depth, rootmove, score, timer.read() / 1_000_000 });
        if (rootmove == null) break;
    }
    if (rootmove) |rm| {
        try output.print("bestmove {}\n", .{rm});
    } else {
        try output.print("info string Error: No moves found in position\n", .{});
    }
}

pub fn main() !void {
    var input = std.io.getStdIn().reader();
    var output = std.io.getStdOut().writer();

    var board = Board.defaultBoard();

    var buffer: [2048]u8 = undefined;
    while (try input.readUntilDelimiterOrEof(&buffer, '\n')) |line| {
        var it = std.mem.tokenizeAny(u8, line, " \t\r\n");
        if (it.next()) |command| {
            if (std.mem.eql(u8, command, "position")) {
                const pos_type = it.next() orelse "startpos";
                if (std.mem.eql(u8, pos_type, "startpos")) {
                    board = Board.defaultBoard();
                } else if (std.mem.eql(u8, pos_type, "fen")) {
                    const board_str = it.next() orelse "";
                    const color = it.next() orelse "";
                    const castling = it.next() orelse "";
                    const enpassant = it.next() orelse "";
                    const no_capture_clock = it.next() orelse "";
                    const ply = it.next() orelse "";
                    board = Board.parseParts(board_str, color, castling, enpassant, no_capture_clock, ply) catch {
                        try output.print("info string Error: Invalid FEN for position command\n", .{});
                        continue;
                    };
                } else {
                    try output.print("info string Error: Invalid position type '{s}' for position command\n", .{pos_type});
                    continue;
                }
                if (it.next()) |moves_str| {
                    if (!std.mem.eql(u8, moves_str, "moves")) {
                        try output.print("info string Error: Unexpected token '{s}' in position command\n", .{moves_str});
                        continue;
                    }
                    while (it.next()) |move_str| {
                        const code = MoveCode.parse(move_str) catch {
                            try output.print("info string Error: Invalid movecode '{s}'\n", .{move_str});
                            break;
                        };
                        if (!makeMoveByCode(&board, code)) {
                            try output.print("info string Error: Illegal move '{s}' in position {}\n", .{ move_str, board });
                            break;
                        }
                    }
                }
            } else if (std.mem.eql(u8, command, "go")) {
                var tc = TimeControl{};
                while (it.next()) |part| {
                    if (std.mem.eql(u8, part, "wtime")) {
                        const str = it.next() orelse break;
                        tc.wtime = std.fmt.parseUnsigned(u64, str, 10) catch continue;
                    } else if (std.mem.eql(u8, part, "btime")) {
                        const str = it.next() orelse break;
                        tc.btime = std.fmt.parseUnsigned(u64, str, 10) catch continue;
                    } else if (std.mem.eql(u8, part, "winc")) {
                        const str = it.next() orelse break;
                        tc.winc = std.fmt.parseUnsigned(u64, str, 10) catch continue;
                    } else if (std.mem.eql(u8, part, "binc")) {
                        const str = it.next() orelse break;
                        tc.binc = std.fmt.parseUnsigned(u64, str, 10) catch continue;
                    } else if (std.mem.eql(u8, part, "movestogo")) {
                        const str = it.next() orelse break;
                        tc.movestogo = std.fmt.parseUnsigned(u64, str, 10) catch continue;
                    }
                }
                try uciGo(output, &board, tc);
            } else if (std.mem.eql(u8, command, "isready")) {
                try output.print("readyok\n", .{});
            } else if (std.mem.eql(u8, command, "ucinewgame")) {
                @memset(&tt, TTEntry.empty());
            } else if (std.mem.eql(u8, command, "uci")) {
                try output.print("{s}\n", .{
                    \\id name Bannou 0.2
                    \\id author 87 (87flowers.com)
                    \\uciok
                });
            } else if (std.mem.eql(u8, command, "debug")) {
                _ = it.next();
                // TODO: set debug mode based on next argument
            } else if (std.mem.eql(u8, command, "quit")) {
                return;
            } else if (std.mem.eql(u8, command, "d")) {
                board.debugPrint();
            } else if (std.mem.eql(u8, command, "l.move")) {
                while (it.next()) |move_str| {
                    const code = MoveCode.parse(move_str) catch {
                        try output.print("info string Error: Invalid movecode '{s}'\n", .{move_str});
                        break;
                    };
                    if (!makeMoveByCode(&board, code)) {
                        try output.print("info string Error: Illegal move '{s}' in position {}\n", .{ move_str, board });
                        break;
                    }
                }
            } else if (std.mem.eql(u8, command, "l.perft")) {
                const depth = std.fmt.parseUnsigned(usize, it.next() orelse "1", 10) catch {
                    try output.print("info string Error: Invalid argument to l.perft\n", .{});
                    continue;
                };
                if (it.next() != null) try output.print("info string Warning: Unexpected extra arguments to l.perft\n", .{});
                try divide(output, &board, depth);
            } else if (std.mem.eql(u8, command, "l.bestmove")) {
                const str = it.next() orelse break;
                const depth = std.fmt.parseInt(i32, str, 10) catch continue;
                try output.print("{any}\n", .{bestmove(&board, depth)});
            } else if (std.mem.eql(u8, command, "l.eval")) {
                try output.print("{}\n", .{eval(&board)});
            } else if (std.mem.eql(u8, command, "l.history")) {
                for (board.zhistory[0 .. board.state.ply + 1], 0..) |h, i| {
                    try output.print("{}: {X}\n", .{ i, h });
                }
            } else if (std.mem.eql(u8, command, "l.auto")) {
                const str = it.next() orelse break;
                const depth = std.fmt.parseInt(i32, str, 10) catch continue;
                const bm = bestmove(&board, depth);
                try output.print("{any}\n", .{bm});
                if (bm[0]) |m| {
                    _ = makeMoveByCode(&board, m.code);
                } else {
                    try output.print("No valid move.\n", .{});
                }
                board.debugPrint();
            } else {
                try output.print("info string Error: Unknown command '{s}'\n", .{command});
                continue;
            }
        }
    }
}

test "simple test" {}

const std = @import("std");
const assert = std.debug.assert;
