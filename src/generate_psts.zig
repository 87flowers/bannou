const Case = struct {
    board: Board,
    result: f64,
};

fn parseResult(str: []const u8) f64 {
    if (std.mem.eql(u8, str, "\"0-1\";")) {
        return -1.0;
    } else if (std.mem.eql(u8, str, "\"1-0\";")) {
        return 1.0;
    } else if (std.mem.eql(u8, str, "\"1/2-1/2\";")) {
        return 0.0;
    } else {
        @panic("failed parseResult");
    }
}

fn parseCase(str: []const u8) !Case {
    var it = std.mem.tokenizeAny(u8, str, " \t\r\n");
    const board_str = it.next() orelse @panic("failed parseCase");
    const color = it.next() orelse @panic("failed parseCase");
    const castling = it.next() orelse @panic("failed parseCase");
    const enpassant = it.next() orelse @panic("failed parseCase");
    _ = it.next() orelse @panic("failed parseCase");
    const result_str = it.next() orelse @panic("failed parseCase");
    const no_capture_clock = "0";
    const ply = "1";
    if (it.next() != null) @panic("failed parseCase");
    return .{
        .board = try Board.parseParts(board_str, color, castling, enpassant, no_capture_clock, ply),
        .result = parseResult(result_str),
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
    const p = 1 / (1 + @exp(-cp / 400));
    return 2 * p - 1;
}

fn featuresFromCase(case: *const Case) FeatureList {
    var features = FeatureList{ .result = case.result };

    const mg_phase = phaseFromCase(case);
    const eg_phase = 1.0 - mg_phase;

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

        assert(index < (6 << 7));

        features.add(.{ .index = index + 0, .weight = mg_phase * sign });
        features.add(.{ .index = index + 1, .weight = eg_phase * sign });
    }

    return features;
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
    return .{ err, features[len + 1..] };
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();

    var dataset = DataSet.init(gpa.allocator());
    defer dataset.deinit();

    var args = std.process.args();
    _ = args.skip();

    while (args.next()) |fname| {
        std.debug.print("Loading EPD {s}:\n", .{fname});
        var f = try std.fs.openFileAbsolute(fname, .{});
        defer f.close();
        var stream = std.compress.gzip.decompressor(f.reader());
        var input = stream.reader();

        var count: usize = 0;
        var buffer: [1024]u8 = undefined;
        while (try input.readUntilDelimiterOrEof(&buffer, '\n')) |line| {
            const case = try parseCase(line);
            const features = featuresFromCase(&case);
            try dataset.addFeatureList(features);
            if (count & 0xfff == 0) std.debug.print("{}\r", .{count});
            count += 1;
        }
        std.debug.print("{} [done]\n", .{count});
    }

    var timer = try std.time.Timer.start();

    const coefficients_size = 6 << 7;
    var coefficients = [1]f64{0} ** coefficients_size;
    var gradient = [1]f64{0} ** coefficients_size;
    var momentum = [1]f64{0} ** coefficients_size;
    var rmsprop = [1]f64{0} ** coefficients_size;

    var best_epoch: usize = 0;
    var best_mse = std.math.inf(f64);
    var best_coefficients = coefficients;

    var i: usize = 0;
    while (best_epoch + 200 > i) : (i += 1) {
        const mse = dataset.calcGradient(&gradient, &coefficients);
        std.debug.print("epoch {} mse {} time {} ms", .{ i, mse, timer.lap() / std.time.ns_per_ms });
        if (mse < best_mse) {
            best_mse = mse;
            best_epoch = i;
            best_coefficients = coefficients;
            std.debug.print(" *", .{});
        }
        std.debug.print("\n", .{});

        const alpha = 100 * @exp(-@as(f64, @floatFromInt(i))/1000);
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
}

const std = @import("std");
const assert = std.debug.assert;
const coord = @import("coord.zig");
const eval = @import("eval.zig");
const Color = @import("common.zig").Color;
const Board = @import("Board.zig");
