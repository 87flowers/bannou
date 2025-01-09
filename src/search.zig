pub fn Control(comptime config: struct {
    time: bool = false,
    depth: bool = false,
    nodes: bool = false,
    stats: bool = false,
}) type {
    return struct {
        timer: std.time.Timer,
        nodes: u64,
        time_limit: if (config.time) struct { soft_deadline: u64, hard_deadline: u64 } else void,
        depth_limit: if (config.depth) struct { target_depth: i32 } else void,
        nodes_limit: if (config.nodes) struct { target_nodes: i32 } else void,
        stats: if (config.stats) struct {
            nodes: u64 = 0,
            qnodes: u64 = 0,
            zw_nodes: u64 = 0,
            zw_qnodes: u64 = 0,
            nodes_in_nmr: u64 = 0,
            tt_prune: u64 = 0,
            tt_prune_while_in_nmr: u64 = 0,
            nmr_attempts: u64 = 0,
            nmr_attempts_while_in_nmr: u64 = 0,
            nmr_reductions: u64 = 0,
            nmr_prunes: u64 = 0,
            rfp_success: u64 = 0,
            rfp_success_while_in_nmr: u64 = 0,
        } else void,

        pub fn init(args: anytype) @This() {
            return .{
                .timer = std.time.Timer.start() catch @panic("timer unsupported on platform"),
                .nodes = 0,
                .time_limit = if (config.time) .{ .soft_deadline = args.soft_deadline, .hard_deadline = args.hard_deadline } else {},
                .depth_limit = if (config.depth) .{ .target_depth = args.target_depth } else {},
                .nodes_limit = if (config.nodes) .{ .target_nodes = args.target_nodes } else {},
                .stats = if (config.stats) .{} else {},
            };
        }

        pub fn reset(self: *@This()) void {
            _ = self.timer.lap();
            self.nodes = 0;
        }

        pub fn nodeVisited(self: *@This(), mode: SearchMode, is_pv_node: bool) void {
            self.nodes += 1;

            if (!config.stats) return;
            self.stats.nodes += 1;
            if (mode == .quiescence) self.stats.qnodes += 1;
            if (mode == .nullmove) self.stats.nodes_in_nmr += 1;
            if (!is_pv_node) self.stats.zw_nodes += 1;
            if (!is_pv_node and mode == .quiescence) self.stats.zw_qnodes += 1;
        }

        /// Returns true if we should terminate the search
        pub fn checkSoftTermination(self: *@This(), depth: i32) bool {
            if (config.time and self.time_limit.soft_deadline <= self.timer.read()) return true;
            if (config.depth and depth >= self.depth_limit.target_depth) return true;
            if (config.nodes and self.nodes >= self.nodes_limit.target_nodes) return true;
            return false;
        }

        /// Raises SearchError.EarlyTermination if we should terminate the search
        pub fn checkHardTermination(self: *@This(), comptime mode: SearchMode) SearchError!void {
            if (config.time and mode == .normal and self.time_limit.hard_deadline <= self.timer.read()) return SearchError.EarlyTermination;
            if (config.nodes and self.nodes >= self.nodes_limit.target_nodes) return SearchError.EarlyTermination;
        }

        pub fn trackTtPrune(self: *@This(), mode: SearchMode) void {
            if (!config.stats) return;
            self.stats.tt_prune += 1;
            if (mode == .nullmove) self.stats.tt_prune_while_in_nmr += 1;
        }

        pub fn trackRfp(self: *@This(), mode: SearchMode) void {
            if (!config.stats) return;
            self.stats.rfp_success += 1;
            if (mode == .nullmove) self.stats.rfp_success_while_in_nmr += 1;
        }

        pub fn trackNmrAttempt(self: *@This(), mode: SearchMode) void {
            if (!config.stats) return;
            self.stats.nmr_attempts += 1;
            if (mode == .nullmove) self.stats.nmr_attempts_while_in_nmr += 1;
        }

        pub fn trackNmrSuccess(self: *@This(), mode: SearchMode) void {
            if (!config.stats) return;
            if (mode == .nullmove) {
                self.stats.nmr_prunes += 1;
            } else {
                self.stats.nmr_reductions += 1;
            }
        }

        pub fn format(self: *@This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            const nps = self.nodes * std.time.ns_per_s / self.timer.read();
            try writer.print("time {} nodes {} nps {}", .{ self.timer.read() / std.time.ns_per_ms, self.nodes, nps });
        }

        pub fn printStats(self: *@This(), write: anytype) !void {
            if (!config.stats) return;
            try write.print("# nodes:                     {:>8}\n", .{self.stats.nodes});
            try write.print("# nodes_in_nmr:              {:>8}\n", .{self.stats.nodes_in_nmr});
            try write.print("# qnodes:                    {:>8} ({d:.2}%)\n", .{ self.stats.qnodes, percentage(self.stats.qnodes, self.stats.nodes) });
            try write.print("# zw_nodes:                  {:>8} ({d:.2}%)\n", .{ self.stats.zw_nodes, percentage(self.stats.zw_nodes, self.stats.nodes) });
            try write.print("# zw_qnodes:                 {:>8} ({d:.2}% q, {d:.2}% zw)\n", .{ self.stats.zw_qnodes, percentage(self.stats.zw_qnodes, self.stats.qnodes), percentage(self.stats.zw_qnodes, self.stats.zw_nodes) });
            try write.print("# tt_prune:                  {:>8}\n", .{self.stats.tt_prune});
            try write.print("# rfp_success:               {:>8}\n", .{self.stats.rfp_success});
            try write.print("# nmr_attempts:              {:>8}\n", .{self.stats.nmr_attempts});
            try write.print("# nmr_prunes:                {:>8} ({d:.2}%)\n", .{ self.stats.nmr_prunes, percentage(self.stats.nmr_prunes, self.stats.nmr_attempts) });
            try write.print("# nmr_reductions:            {:>8} ({d:.2}%)\n", .{ self.stats.nmr_reductions, percentage(self.stats.nmr_reductions, self.stats.nmr_attempts) });
            try write.print("# tt_prune_while_in_nmr:     {:>8}\n", .{self.stats.tt_prune_while_in_nmr});
            try write.print("# rfp_success_while_in_nmr:  {:>8}\n", .{self.stats.rfp_success_while_in_nmr});
            try write.print("# nmr_attempts_while_in_nmr: {:>8}\n", .{self.stats.nmr_attempts_while_in_nmr});
        }
    };
}

fn percentage(numerator: u64, denominator: u64) f32 {
    return @as(f32, 100) * @as(f32, @floatFromInt(numerator)) / @as(f32, @floatFromInt(denominator));
}

pub const TimeControl = Control(.{ .time = true });
pub const DepthControl = Control(.{ .depth = true });

fn search2(game: *Game, ctrl: anytype, pv: anytype, alpha: Score, beta: Score, ply: u32, depth: i32, comptime mode: SearchMode) SearchError!Score {
    return if (mode != .quiescence and depth <= 0)
        try search(game, ctrl, pv, alpha, beta, ply, depth, .quiescence)
    else if (mode == .firstply)
        try search(game, ctrl, pv, alpha, beta, ply, depth, .normal)
    else
        try search(game, ctrl, pv, alpha, beta, ply, depth, mode);
}

fn search(game: *Game, ctrl: anytype, pv: anytype, alpha: Score, beta: Score, ply: u32, depth_arg: i32, comptime mode: SearchMode) SearchError!Score {
    var depth = depth_arg;

    // Preconditions for optimizer to be aware of.
    if (mode != .quiescence) assert(depth > 0);
    if (mode == .quiescence) assert(depth <= 0);

    // Bottomed out
    if (ply >= common.max_search_ply) return if (game.board.isInCheck()) 0 else eval.eval(game);

    try ctrl.checkHardTermination(mode);

    // Are we on a PV node?
    const is_pv_node = beta != alpha + 1;

    const tte = game.ttLoad();

    if (!is_pv_node) {
        if (!tte.isEmpty()) {
            // Transposition Table Pruning
            if (tte.depth >= depth and switch (tte.bound) {
                .empty => false,
                .lower => tte.score >= beta,
                .exact => true,
                .upper => tte.score <= alpha,
            }) {
                ctrl.trackTtPrune(mode);
                pv.write(tte.move(), &.{});
                return tte.score;
            }

            // Transposition Table Extension (via Ciekce)
            if (mode == .normal and depth < 3 and tte.depth >= depth and !tte.move().isNone()) depth += 1;
        } else {
            // Internal Iterative Reductions
            if (mode == .normal and depth > 3) depth -= 1;
        }
    }

    // Static evaluation with TT replacement
    const first_static_eval = eval.eval(game);
    const static_eval = if (switch (tte.bound) {
        .empty => false,
        .lower => tte.score >= first_static_eval,
        .exact => true,
        .upper => tte.score <= first_static_eval,
    })
        tte.score
    else
        first_static_eval;

    var best_score: Score = eval.no_moves;
    var best_move: MoveCode = tte.move();

    // Stand-pat (for quiescence search)
    if (mode == .quiescence) {
        best_score = static_eval;
        if (static_eval >= beta) {
            pv.writeEmpty();
            return static_eval;
        }
    }

    const is_in_check = game.board.isInCheck();

    // Check extension
    if (is_in_check) depth += 1;

    // Pruning
    if (!is_pv_node and !is_in_check) {
        // Reverse futility pruning
        if (mode != .quiescence and static_eval -| depth * 100 > beta) {
            ctrl.trackRfp(mode);
            return static_eval;
        }

        // Null-move reduction and pruning
        if ((mode == .normal or mode == .nullmove) and depth > 2 and !game.prevMove().isNone()) {
            ctrl.trackNmrAttempt(mode);

            const old_state = game.moveNull();
            const nws_reduction = 4 + @divFloor(depth, 6);
            const null_score = -try search2(game, ctrl, line.Null{}, -beta, -beta +| 1, ply + 1, depth - nws_reduction, .normal);
            game.unmoveNull(old_state);

            if (null_score >= beta) {
                ctrl.trackNmrSuccess(mode);

                if (mode == .nullmove) {
                    // Failed high twice, actually prune
                    pv.writeEmpty();
                    // Do not return mate scores
                    return if (eval.isMateScore(null_score)) beta else null_score;
                }
                // Null-move reduction
                // This is the same as a normal search except:
                // - With a "pruneable" flag set (the .nullmove mode)
                // - Depth reduced by 1
                const nmr_reduction = 1 + @divFloor(depth, 6);
                return search(game, ctrl, line.Null{}, alpha, beta, ply, depth - nmr_reduction, .nullmove);
            }
        }
    }

    var moves = MoveList{};
    switch (mode) {
        .firstply, .normal, .nullmove => moves.generateMoves(&game.board, .any),
        .quiescence => moves.generateMoves(&game.board, .captures_only),
    }
    game.sortMoves(&moves, best_move);

    game.killerClearChild();

    var best_i: usize = undefined;
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

                // Late move reductions
                if (mode != .quiescence and quiets_visited > 2 and depth > 2) {
                    const log2 = std.math.log2;
                    const l2m = log2(moves_visited);
                    const l2d = log2(@as(u32, @intCast(depth)));
                    var reduction: i32 = @intCast((3 + l2m * l2d) / 4);
                    if (!m.isTactical()) {
                        // reduce quiets more on non-PV nodes
                        reduction += @intFromBool(!is_pv_node);
                    }
                    const r = std.math.clamp(reduction, 1, depth - 1);
                    if (r > 1) {
                        const lmr_score = -try search2(game, ctrl, &child_pv, -a - 1, -a, ply + 1, depth - r, mode);
                        if (lmr_score <= a) break :blk lmr_score;
                    }
                }

                // PVS Scout Search
                if (mode != .quiescence and moves_visited != 0 and is_pv_node) {
                    const scout_score = -try search2(game, ctrl, &child_pv, -a - 1, -a, ply + 1, depth - 1, mode);
                    if (scout_score <= a or scout_score >= beta) break :blk scout_score;
                }

                break :blk -try search2(game, ctrl, &child_pv, -beta, -a, ply + 1, depth - 1, mode);
            };

            ctrl.nodeVisited(mode, is_pv_node);
            moves_visited += 1;
            if (mode != .quiescence and !m.isTactical()) {
                quiets_visited += 1;
            }

            if (child_score > best_score) {
                best_score = child_score;
                best_move = m.code;
                best_i = i;
                pv.write(best_move, &child_pv);

                if (child_score >= beta) break;
            }
        }
    }

    // Record history
    if (best_score >= beta and mode != .quiescence) {
        game.recordHistory(depth, &moves, best_i);
    }

    if (best_score == eval.no_moves) {
        pv.writeEmpty();
        if (!is_in_check) {
            return eval.draw;
        } else {
            return eval.mated;
        }
    }
    if (best_score < 0 and eval.isMateScore(best_score)) best_score = best_score + 1;

    game.ttStore(.{
        .best_move = if (best_score > alpha)
            best_move
        else
            tte.move(),
        .depth = @intCast(std.math.clamp(depth, 0, 127)),
        .score = best_score,
        .bound = if (best_score >= beta)
            .lower
        else if (best_score <= alpha)
            .upper
        else
            .exact,
    });

    return best_score;
}

fn forDepth(game: *Game, ctrl: anytype, pv: anytype, depth: i32, prev_score: Score) SearchError!Score {
    const min_window = -std.math.maxInt(Score);
    const max_window = std.math.maxInt(Score);

    if (depth > 3) {
        // Aspiration windows
        var score = prev_score;
        var delta: Score = 25;
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

pub fn go(output: anytype, game: *Game, ctrl: anytype, pv: anytype) !Score {
    // comptime assert(@typeInfo(@TypeOf(ctrl)) == .pointer and @typeInfo(@TypeOf(pv)) == .pointer);
    var depth: i32 = 1;
    var score: Score = undefined;
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
    try ctrl.printStats(output);
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
const Score = @import("eval.zig").Score;
const TT = @import("TT.zig");
