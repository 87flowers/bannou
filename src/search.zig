pub fn Control(comptime limit: struct {
    time: bool = false,
    depth: bool = false,
    nodes: bool = false,
}) type {
    return struct {
        timer: std.time.Timer,
        nodes: u64,
        time_limit: if (limit.time) struct { soft_deadline: u64, hard_deadline: u64 } else void,
        depth_limit: if (limit.depth) struct { target_depth: i32 } else void,
        nodes_limit: if (limit.nodes) struct { target_nodes: i32 } else void,

        pub fn init(args: anytype) @This() {
            return .{
                .timer = std.time.Timer.start() catch @panic("timer unsupported on platform"),
                .nodes = 0,
                .time_limit = if (limit.time) .{ .soft_deadline = args.soft_deadline, .hard_deadline = args.hard_deadline } else {},
                .depth_limit = if (limit.depth) .{ .target_depth = args.target_depth } else {},
                .nodes_limit = if (limit.nodes) .{ .target_nodes = args.target_nodes } else {},
            };
        }

        pub fn nodeVisited(self: *@This()) void {
            self.nodes += 1;
        }

        /// Returns true if we should terminate the search
        pub fn checkSoftTermination(self: *@This(), depth: i32) bool {
            if (limit.time and self.time_limit.soft_deadline <= self.timer.read()) return true;
            if (limit.depth and depth >= self.depth_limit.target_depth) return true;
            if (limit.nodes and self.nodes >= self.nodes_limit.target_nodes) return true;
            return false;
        }

        /// Raises SearchError.EarlyTermination if we should terminate the search
        pub fn checkHardTermination(self: *@This(), comptime mode: SearchMode, depth: i32) SearchError!void {
            if (limit.time and mode == .normal and depth > 3 and self.time_limit.hard_deadline <= self.timer.read()) return SearchError.EarlyTermination;
            if (limit.nodes and self.nodes >= self.nodes_limit.target_nodes) return SearchError.EarlyTermination;
        }

        pub fn format(self: *@This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            const nps = self.nodes * std.time.ns_per_s / self.timer.read();
            try writer.print("time {} nodes {} nps {}", .{ self.timer.read() / std.time.ns_per_ms, self.nodes, nps });
        }
    };
}

pub const TimeControl = Control(.{ .time = true });
pub const DepthControl = Control(.{ .depth = true });

fn search2(game: *Game, ctrl: anytype, pv: anytype, alpha: i32, beta: i32, depth: i32, comptime mode: SearchMode) SearchError!i32 {
    return if (mode != .quiescence and depth <= 0)
        try search(game, ctrl, pv, alpha, beta, depth, .quiescence)
    else if (mode == .firstply)
        try search(game, ctrl, pv, alpha, beta, depth, .normal)
    else
        try search(game, ctrl, pv, alpha, beta, depth, mode);
}

fn search(game: *Game, ctrl: anytype, pv: anytype, alpha: i32, beta: i32, depth: i32, comptime mode: SearchMode) SearchError!i32 {
    // Preconditions for optimizer to be aware of.
    if (mode != .quiescence) assert(depth > 0);
    if (mode == .quiescence) assert(depth <= 0);

    try ctrl.checkHardTermination(mode, depth);

    const tte = game.ttLoad();
    if (tte.hash == game.board.state.hash) {
        if (tte.depth >= depth) {
            const pass = switch (tte.bound) {
                .lower => tte.score >= beta,
                .exact => false,
                .upper => tte.score <= alpha,
            };
            if (pass) {
                pv.write(tte.best_move, &.{});
                return tte.score;
            }
        }
    }

    const no_moves = -std.math.maxInt(i32);
    var best_score: i32 = switch (mode) {
        .firstply, .normal, .nullmove => no_moves,
        .quiescence => eval.eval(game),
    };
    var best_move: MoveCode = tte.best_move;

    // Check stand-pat score for beta cut-off (avoid move generation)
    if (mode == .quiescence and best_score >= beta) {
        pv.writeEmpty();
        return best_score;
    }

    // Null-move pruning
    if (mode == .normal and !game.board.isInCheck() and depth > 4) {
        const old_state = game.board.moveNull();
        defer game.board.unmoveNull(old_state);
        const null_score = -try search2(game, ctrl, line.Null{}, -beta, -beta + 1, depth - 3, .nullmove);
        if (null_score >= beta) {
            pv.writeEmpty();
            return null_score;
        }
    }

    var moves = MoveList{};
    switch (mode) {
        .firstply, .normal, .nullmove => moves.generateMoves(&game.board, .any),
        .quiescence => moves.generateMoves(&game.board, .captures_only),
    }
    moves.sortWithPv(tte.best_move);

    for (0..moves.size) |i| {
        const m = moves.moves[i];
        const old_state = game.board.move(m);
        ctrl.nodeVisited();
        defer game.board.unmove(m, old_state);
        if (game.board.isValid()) {
            var child_pv = pv.newChild();
            const child_score = if (game.board.isRepeatedPosition() or game.board.is50MoveExpired())
                0
            else
                -try search2(game, ctrl, &child_pv, -beta, -@max(alpha, best_score), depth - 1, mode);
            if (child_score > best_score) {
                best_score = child_score;
                best_move = m.code;
                pv.write(best_move, &child_pv);
                if (child_score >= beta) break;
            }
        }
    }

    if (best_score == no_moves) {
        pv.writeEmpty();
        if (!game.board.isInCheck()) {
            return 0;
        } else {
            return no_moves + 1;
        }
    }
    if (best_score < -1073741824) best_score = best_score + 1;

    if (tte.hash != game.board.state.hash or tte.depth <= depth) {
        game.ttStore(.{
            .hash = game.board.state.hash,
            .best_move = best_move,
            .depth = @intCast(@max(0, depth)),
            .score = best_score,
            .bound = if (best_score >= beta)
                .lower
            else if (best_score <= alpha)
                .upper
            else
                .exact,
        });
    }

    return best_score;
}

fn forDepth(game: *Game, ctrl: anytype, pv: anytype, depth: i32, prev_score: i32) SearchError!i32 {
    const min_window = -std.math.maxInt(i32);
    const max_window = std.math.maxInt(i32);

    if (depth > 3) {
        // Aspiration window
        const delta = 100;
        const lower = @max(min_window, prev_score -| delta);
        const upper = @min(max_window, prev_score +| delta);
        const aspiration_score = try search(game, ctrl, pv, lower, upper, depth, .firstply);
        if (lower < aspiration_score and aspiration_score < upper) return aspiration_score;
    }

    // Full window
    return try search(game, ctrl, pv, min_window, max_window, depth, .firstply);
}

pub fn go(output: anytype, game: *Game, ctrl: anytype, pv: anytype) !i32 {
    comptime assert(@typeInfo(@TypeOf(ctrl)) == .pointer and @typeInfo(@TypeOf(pv)) == .pointer);
    var depth: i32 = 1;
    var score: i32 = undefined;
    var current_pv = pv.new();
    while (depth < common.max_search_ply) : (depth += 1) {
        score = forDepth(game, ctrl, &current_pv, depth, score) catch {
            try output.print("info depth {} score cp {} {} pv {} string [search terminated]\n", .{ depth, score, ctrl, pv });
            break;
        };
        pv.copyFrom(&current_pv);
        try output.print("info depth {} score cp {} {} pv {}\n", .{ depth, score, ctrl, pv });
        if (ctrl.checkSoftTermination(depth)) break;
    }
    return score;
}

const SearchError = error{EarlyTermination};
const SearchMode = enum { firstply, normal, nullmove, quiescence };

const std = @import("std");
const assert = std.debug.assert;
const common = @import("common.zig");
const eval = @import("eval.zig");
const line = @import("line.zig");
const Game = @import("Game.zig");
const MoveCode = @import("MoveCode.zig");
const MoveList = @import("MoveList.zig");
