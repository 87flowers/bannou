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

fn search2(game: *Game, ctrl: anytype, pv: anytype, alpha: i32, beta: i32, ply: u32, depth: i32, comptime mode: SearchMode) SearchError!i32 {
    return if (mode != .quiescence and depth <= 0)
        try search(game, ctrl, pv, alpha, beta, ply, depth, .quiescence)
    else if (mode == .firstply)
        try search(game, ctrl, pv, alpha, beta, ply, depth, .normal)
    else
        try search(game, ctrl, pv, alpha, beta, ply, depth, mode);
}

fn search(game: *Game, ctrl: anytype, pv: anytype, alpha: i32, beta: i32, ply: u32, depth: i32, comptime mode: SearchMode) SearchError!i32 {
    // Preconditions for optimizer to be aware of.
    if (mode != .quiescence) assert(depth > 0);
    if (mode == .quiescence) assert(depth <= 0);

    try ctrl.checkHardTermination(mode, depth);

    // Are we on a PV node?
    const is_pv_node = beta != alpha + 1;

    const tte = game.ttLoad();
    const ttmatch = tte.hash == game.board.state.hash;
    const tthit = ttmatch and tte.depth >= depth;

    // Transposition Table Pruning
    if (!is_pv_node and tthit and switch (tte.bound) {
        .lower => tte.score >= beta,
        .exact => true,
        .upper => tte.score <= alpha,
    }) {
        pv.write(tte.best_move, &.{});
        return tte.score;
    }

    // Static evaluation with TT replacement
    const first_static_eval = eval.eval(game);
    const static_eval = if (tthit and switch (tte.bound) {
        .lower => tte.score >= first_static_eval,
        .exact => true,
        .upper => tte.score <= first_static_eval,
    })
        tte.score
    else
        first_static_eval;

    const no_moves = -std.math.maxInt(i32);
    var best_score: i32 = no_moves;
    var best_move: MoveCode = if (tthit) tte.best_move else MoveCode.none;

    // Stand-pat (for quiescence search)
    if (mode == .quiescence) {
        best_score = static_eval;
        if (static_eval >= beta) {
            pv.writeEmpty();
            return best_score;
        }
    }

    const is_in_check = game.board.isInCheck();

    // Reverse futility pruning
    if (!is_in_check and mode != .quiescence and static_eval -| depth * 100 > beta) {
        return static_eval;
    }

    // Null-move pruning
    if (!is_in_check and (mode == .normal or mode == .nullmove) and depth > 2 and !game.prevMove().isNone()) {
        const old_state = game.moveNull();
        const null_score = -try search2(game, ctrl, line.Null{}, -beta, -beta +| 1, ply + 1, depth - 4, .normal);
        game.unmoveNull(old_state);
        if (null_score >= beta) {
            if (mode == .nullmove) {
                // Failed high twice, prune
                pv.writeEmpty();
                // Do not return mate scores
                return if (isMateScore(null_score)) beta else null_score;
            }
            // Subtree verification search
            // This is the same as a normal search except:
            // - With a "pruneable" flag set (the .nullmove mode)
            // - Depth reduced by 1
            return search(game, ctrl, line.Null{}, alpha, beta, ply, depth - 1, .nullmove);
        }
    }

    var moves = MoveList{};
    switch (mode) {
        .firstply, .normal, .nullmove => moves.generateMoves(&game.board, .any),
        .quiescence => moves.generateMoves(&game.board, .captures_only),
    }
    game.sortMoves(&moves, tte.best_move, ply);

    var moves_visited: usize = 0;
    var quiets_visited: usize = 0;
    for (0..moves.size) |i| {
        const m = moves.moves[i];
        const old_state = game.move(m);
        defer game.unmove(m, old_state);
        if (game.board.isValid()) {
            // Late Move Pruning
            if (mode != .quiescence and !m.isTactical() and !is_pv_node) {
                const lmp_threshold = 2 + (depth << 2);
                if (!is_in_check and quiets_visited > lmp_threshold) {
                    break;
                }
            }

            var child_pv = pv.newChild();
            const child_score = blk: {
                if (game.board.isRepeatedPosition() or game.board.is50MoveExpired()) break :blk 0;

                const a = @max(alpha, best_score);

                // PVS Scout Search
                if (mode != .quiescence and moves_visited != 0 and is_pv_node) {
                    const scout_score = -try search2(game, ctrl, &child_pv, -a - 1, -a, ply + 1, depth - 1, mode);
                    if (scout_score <= a or scout_score >= beta) break :blk scout_score;
                }

                break :blk -try search2(game, ctrl, &child_pv, -beta, -a, ply + 1, depth - 1, mode);
            };

            ctrl.nodeVisited();
            moves_visited += 1;
            if (mode != .quiescence and !m.isTactical()) {
                quiets_visited += 1;
            }

            if (child_score > best_score) {
                best_score = child_score;
                best_move = m.code;
                pv.write(best_move, &child_pv);

                if (child_score >= beta) {
                    if (mode != .quiescence) {
                        // Record history
                        game.recordHistory(ply, depth, &moves, i);
                    }
                    break;
                }
            }
        }
    }

    if (best_score == no_moves) {
        pv.writeEmpty();
        if (!is_in_check) {
            return 0;
        } else {
            return no_moves + 1;
        }
    }
    if (best_score < 0 and isMateScore(best_score)) best_score = best_score + 1;

    if (!ttmatch or tte.depth <= depth) {
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
        // Aspiration windows
        var score = prev_score;
        var delta: i32 = 25;
        var lower = @max(min_window, prev_score -| delta);
        var upper = @min(max_window, prev_score +| delta);
        while (true) : (delta *= 2) {
            score = try search(game, ctrl, pv, lower, upper, 0, depth, .firstply);
            if (score <= lower) {
                lower = @max(min_window, score -| delta);
            } else if (score >= upper) {
                upper = @min(max_window, score +| delta);
            } else {
                return score;
            }
        }
    }

    // Full window
    return try search(game, ctrl, pv, min_window, max_window, 0, depth, .firstply);
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

fn isMateScore(score: i32) bool {
    return @abs(score) > 1073741824;
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
