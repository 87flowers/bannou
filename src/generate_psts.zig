const Case = struct {
    board: Board,
    result: f64,
    should_filter: bool,
};

fn parseResult(str: []const u8) ?f64 {
    if (std.mem.eql(u8, str, "0-1")) {
        return -1.0;
    } else if (std.mem.eql(u8, str, "1-0")) {
        return 1.0;
    } else if (std.mem.eql(u8, str, "1/2-1/2")) {
        return 0.0;
    } else {
        return null;
    }
}

fn parseCase(str: []const u8) ?Case {
    var it = std.mem.tokenizeAny(u8, str, " \t\r\n");
    const board_str = it.next() orelse return null;
    const color = it.next() orelse return null;
    const castling = it.next() orelse return null;
    const enpassant = it.next() orelse return null;
    const no_capture_clock = it.next() orelse return null;
    const ply = it.next() orelse return null;
    _ = it.next() orelse return null; // bar
    _ = it.next() orelse return null; // bestmove
    const should_filter = it.next() orelse return null;
    _ = it.next() orelse return null; // eval
    const result_str = it.next() orelse return null;
    if (it.next() != null) return null;
    return .{
        .board = Board.parseParts(board_str, color, castling, enpassant, no_capture_clock, ply) catch return null,
        .result = parseResult(result_str) orelse return null,
        .should_filter = std.mem.eql(u8, should_filter, "true"),
    };
}

const Feature = struct {
    index: usize,
    weight: f64,
};

const FeatureList = struct {
    result: f64,
    len: usize = 0,
    features: [64]Feature = undefined,

    fn add(self: *FeatureList, feature: Feature) void {
        self.features[self.len] = feature;
        self.len += 1;
    }
};

fn phaseFromCase(case: *const Case) f64 {
    const result = eval.phase(&case.board);
    return @as(f64, @floatFromInt(result)) / 24.0;
}

// convert centipawn to win probability
fn rescaleEval(cp: f64) f64 {
    const p = 1 / (1 + @exp(-cp / 91.02392266268372));
    return 2 * p - 1;
}

const pst_index = 0;
const pst_size = 6 << 7;
const tempo_index = pst_index + pst_size;
const tempo_size = 1;
const bishop_pair_index = tempo_index + tempo_size;
const bishop_pair_size = 2;
const coefficients_size = bishop_pair_index + bishop_pair_size;
test {
    comptime assert(coefficients_size == pst_size + tempo_size + bishop_pair_size);
}

fn featuresFromCase(case: *const Case) ?FeatureList {
    if (case.should_filter) return null;

    var features = FeatureList{ .result = case.result };

    const mg_phase = phaseFromCase(case);
    const eg_phase = 1.0 - mg_phase;

    var piece_count: [2][7]usize = @splat(@splat(0));

    for (0..32) |id| {
        const color = Color.fromId(@intCast(id));
        const ptype = case.board.pieces[id];
        if (ptype == .none) continue;
        const where = coord.compress(case.board.where[id] ^ color.toRankInvertMask());
        const index: usize =
            (@as(usize, @intFromEnum(ptype) - 1) << 7) +
            (@as(usize, where) << 1);
        const sign: f64 = switch (color) {
            .white => 1,
            .black => -1,
        };

        piece_count[@intFromEnum(color)][@intFromEnum(ptype)] += 1;

        assert(index < (6 << 7));

        features.add(.{ .index = pst_index + index + 0, .weight = mg_phase * sign });
        features.add(.{ .index = pst_index + index + 1, .weight = eg_phase * sign });
    }

    {
        const sign: f64 = switch (case.board.active_color) {
            .white => 1,
            .black => -1,
        };

        features.add(.{ .index = tempo_index + 0, .weight = mg_phase * sign });
    }

    {
        for (0.., [2]f64{ 1, -1 }) |side, sign| {
            if (piece_count[side][@intFromEnum(PieceType.b)] >= 2) {
                features.add(.{ .index = bishop_pair_index + 0, .weight = mg_phase * sign });
                features.add(.{ .index = bishop_pair_index + 1, .weight = eg_phase * sign });
            }
        }
    }

    return features;
}

pub fn printCoefficients(coefficients: []f64) void {
    for ([_]PieceType{ .p, .n, .b, .r, .q, .k }, 0..) |ptype, ptypei| {
        for ([_][]const u8{ "mg", "eg" }, 0..) |phase, phasei| {
            std.debug.print("const {c}_{s} = [_]i16{{\n", .{ ptype.toChar(.black), phase });
            for (0..64) |where| {
                if (where % 8 == 0) std.debug.print("    ", .{});
                const index = pst_index + (ptypei << 7) + (where << 1) + phasei;
                std.debug.print("{}, ", .{@as(i32, @intFromFloat(@round(coefficients[index])))});
                if (where % 8 == 7) std.debug.print("\n", .{});
            }
            std.debug.print("}};\n\n", .{});
        }
    }
    {
        std.debug.print("const tempo = {};\n\n", .{@as(i32, @intFromFloat(@round(coefficients[tempo_index])))});
    }
}

fn caseGradient(features: []const Feature, coefficients: []const f64, gradient: []f64) struct { f64, []const Feature } {
    const len = features[0].index;
    const expected_result = features[0].weight;

    var evaluation: f64 = 0;
    for (1..len + 1) |i| {
        evaluation += features[i].weight * coefficients[features[i].index];
    }
    const err = rescaleEval(evaluation) - expected_result;

    for (1..len + 1) |i| {
        gradient[features[i].index] += features[i].weight * err;
    }
    return .{ err, features[len + 1 ..] };
}

const DataSet = struct {
    data: std.ArrayList(Feature),

    fn init(allocator: std.mem.Allocator) DataSet {
        return .{ .data = std.ArrayList(Feature).init(allocator) };
    }

    fn deinit(self: *DataSet) void {
        self.data.deinit();
    }

    fn addFeatureList(self: *DataSet, fl: FeatureList) !void {
        try self.data.append(.{ .index = fl.len, .weight = fl.result });
        try self.data.appendSlice(fl.features[0..fl.len]);
    }

    fn calcGradient(self: *DataSet, gradient: []f64, coefficients: []const f64) f64 {
        @memset(gradient, 0);

        var total_sq_err: f64 = 0;
        var count: usize = 0;
        var features: []const Feature = self.data.items[0..];
        while (features.len > 0) {
            const err, features = caseGradient(features, coefficients, gradient);
            total_sq_err += err * err;
            count += 1;
        }

        for (gradient) |*g| g.* /= @floatFromInt(count);

        return total_sq_err / @as(f64, @floatFromInt(count));
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var dataset = DataSet.init(allocator);
    defer dataset.deinit();

    var args = try std.process.argsWithAllocator(allocator);
    _ = args.skip();

    while (args.next()) |fname| {
        std.debug.print("Loading {s}:\n", .{fname});
        var f = try std.fs.cwd().openFile(fname, .{});
        defer f.close();
        var stream = std.compress.gzip.decompressor(f.reader());
        var input = stream.reader();

        var count: usize = 0;
        var buffer: [1024]u8 = undefined;
        while (try input.readUntilDelimiterOrEof(&buffer, '\n')) |line| {
            count += 1;
            const case = parseCase(line) orelse {
                std.debug.print("malformed case detected near line {}: {s}\n", .{ count, line });
                continue;
            };
            const features = featuresFromCase(&case) orelse continue;
            try dataset.addFeatureList(features);
            if (count & 0xfff == 0) std.debug.print("{}\r", .{count});
        }
        std.debug.print("{} [done]\n", .{count});
    }

    var timer = try std.time.Timer.start();

    var coefficients = [1]f64{0} ** coefficients_size;
    var gradient = [1]f64{0} ** coefficients_size;
    var momentum = [1]f64{0} ** coefficients_size;
    var rmsprop = [1]f64{0} ** coefficients_size;

    var best_epoch: usize = 0;
    var best_mse = std.math.inf(f64);
    var best_coefficients = coefficients;

    var i: usize = 0;
    while (best_epoch + 500 > i) : (i += 1) {
        const mse = dataset.calcGradient(&gradient, &coefficients);
        std.debug.print("epoch {} mse {} time {} ms", .{ i, mse, timer.lap() / std.time.ns_per_ms });
        if (mse < best_mse and i > 10) {
            best_mse = mse;
            best_epoch = i;
            best_coefficients = coefficients;
            std.debug.print(" *", .{});
        }
        std.debug.print("\n", .{});

        const alpha = 100 * @exp(-@as(f64, @floatFromInt(i)) / 1000);
        const beta1 = 0.99;
        const beta2 = 0.999;
        const epsilon = 1e-9;
        for (&momentum, gradient) |*m, g| m.* = beta1 * m.* + (1 - beta1) * g;
        for (&rmsprop, gradient) |*v, g| v.* = beta2 * v.* + (1 - beta2) * g * g;
        const m_bias = 1 / (1 - std.math.pow(f64, beta1, @floatFromInt(i + 1)));
        const v_bias = 1 / (1 - std.math.pow(f64, beta1, @floatFromInt(i + 1)));
        for (&coefficients, momentum, rmsprop) |*c, m, v| c.* -= alpha * m * m_bias / @sqrt(v * v_bias + epsilon);
    }

    for (best_coefficients) |c| std.debug.print("{} ", .{c});
    std.debug.print("\n", .{});
    printCoefficients(&best_coefficients);
}

const std = @import("std");
const assert = std.debug.assert;
const coord = @import("coord.zig");
const eval = @import("eval.zig");
const Color = @import("common.zig").Color;
const Board = @import("Board.zig");
const PieceType = @import("common.zig").PieceType;
