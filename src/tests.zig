comptime {
    // root
    _ = @import("Board.zig");
    _ = @import("castle_mask.zig");
    _ = @import("cmd_bench.zig");
    _ = @import("cmd_perft.zig");
    _ = @import("common.zig");
    _ = @import("coord.zig");
    _ = @import("eval.zig");
    _ = @import("Game.zig");
    _ = @import("generate_psts.zig");
    _ = @import("generate_zhash.zig");
    _ = @import("line.zig");
    _ = @import("main.zig");
    _ = @import("Move.zig");
    _ = @import("MoveCode.zig");
    _ = @import("MoveList.zig");
    _ = @import("search.zig");
    _ = @import("State.zig");
    _ = @import("TTEntry.zig");
    _ = @import("zhash.zig");
    // util
    _ = @import("util/bch.zig");
    _ = @import("util/bit.zig");
    _ = @import("util/NullWriter.zig");
    _ = @import("util/polynomial.zig");
}
