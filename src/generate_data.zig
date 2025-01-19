const rand = std.crypto.random;

fn makeRandomMove(game: *Game) bool {
    var moves = MoveList{};
    moves.generateMoves(&game.board, .any);

    var has_legal_move = false;
    for (moves.moves[0..moves.size]) |m| {
        const old_state = game.move(m);
        defer game.unmove(m, old_state);
        if (game.board.isValid()) {
            has_legal_move = true;
            break;
        }
    }
    if (!has_legal_move) return false;

    for (0..15) |_| {
        const m = moves.moves[rand.intRangeAtMost(usize, 0, moves.size - 1)];
        const old_state = game.move(m);
        if (game.board.isValid()) return true;
        game.unmove(m, old_state);
    }
    return false;
}

fn playRandomMoves(game: *Game, n: usize) void {
    game.reset();
    for (0..n) |_| {
        const valid = makeRandomMove(game);
        if (!valid) {
            return playRandomMoves(game, n);
        }
    }
}

fn doSearch(game: *Game) !struct { Score, ?MoveCode } {
    var ctrl = search.Control(.{ .nodes = true }).init(.{ .soft_nodes = 5000, .hard_nodes = 500_000 });
    var pv = line.RootMove{};
    const score = try search.go(output.Null{}, game, &ctrl, &pv);
    return .{ score, pv.move };
}

fn playGame(game: *Game) !GameResult {
    playRandomMoves(game, 8);
    history.resize(0) catch unreachable;

    while (true) {
        const score, const move = try doSearch(game);
        history.appendAssumeCapacity(.{
            .board = game.board,
            .score = switch (game.board.active_color) {
                .white => score,
                .black => -score,
            },
            .is_bm_tactical = if (move) |m| game.board.isMoveCodeTactical(m) else false,
            .move = move orelse MoveCode.none,
        });
        if (move == null) return switch (score) {
            0 => .draw,
            eval.mated => switch (game.board.active_color) {
                .white => .black,
                .black => .white,
            },
            else => @panic("unknown game end state"),
        };
        if (game.board.is50MoveExpired()) return .draw;
        if (game.board.countRepetitions() >= 3) return .draw;
        _ = game.makeMoveByCode(move.?);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    g.tt = try TT.init(allocator);
    defer g.tt.deinit();
    g.reset();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    // skip program name
    _ = args.skip();

    const fname = args.next() orelse {
        std.debug.print("expected argument for output filename\n", .{});
        return;
    };

    const arg = args.next() orelse {
        std.debug.print("expected argument for target position count\n", .{});
        return;
    };
    const target_position_count = std.fmt.parseUnsigned(usize, arg, 10) catch {
        std.debug.print("target position count is not a valid number\n", .{});
        return;
    };

    var f = try std.fs.cwd().createFile(fname, .{});
    defer f.close();
    var stream = try std.compress.gzip.compressor(f.writer(), .{ .level = .fast });
    var out = stream.writer();

    std.debug.print("generating to file {s}\n", .{fname});

    var game_count: usize = 0;
    var position_count: usize = 0;
    while (position_count < target_position_count) {
        const result = try playGame(&g);
        game_count += 1;
        const result_str = switch (result) {
            .white => "1-0",
            .black => "0-1",
            .draw => "1/2-1/2",
        };
        std.debug.print("{} {s} {}             \r", .{ game_count, result_str, position_count });
        if (result == .draw) continue;
        for (history.slice()) |h| {
            try out.print("{} | {} {} {} {s}\n", .{
                h.board,
                h.move,
                h.shouldFilter(),
                h.score,
                result_str,
            });
            position_count += @intFromBool(!h.shouldFilter());
        }
    }
    std.debug.print("{} {} [done]\n", .{ game_count, position_count });

    try stream.finish();
}

var g: Game = undefined;
const HistoryArray = std.BoundedArray(History, common.max_game_ply);
var history: HistoryArray = HistoryArray.init(0) catch unreachable;

const History = struct {
    board: Board,
    score: Score,
    is_bm_tactical: bool,
    move: MoveCode,
    pub fn shouldFilter(self: *const History) bool {
        return self.board.state.ply < 16 or
            self.is_bm_tactical or
            self.board.isInCheck() or
            eval.isMateScore(self.score) or
            self.board.pieceCount() < 4;
    }
};
const GameResult = enum { white, black, draw };

const std = @import("std");
const assert = std.debug.assert;
const common = @import("common.zig");
const eval = @import("eval.zig");
const line = @import("line.zig");
const output = @import("output.zig");
const search = @import("search.zig");
const Board = @import("Board.zig");
const Game = @import("Game.zig");
const MoveCode = @import("MoveCode.zig");
const MoveList = @import("MoveList.zig");
const Score = @import("eval.zig").Score;
const TT = @import("TT.zig");
