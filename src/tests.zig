comptime {
    // root
    _ = @import("castle_mask.zig");
    _ = @import("cmd_perft.zig");
    _ = @import("common.zig");
    _ = @import("coord.zig");
    _ = @import("eval.zig");
    _ = @import("main.zig");
    _ = @import("search.zig");
    _ = @import("zhash.zig");
    _ = @import("Board.zig");
    _ = @import("Move.zig");
    _ = @import("MoveCode.zig");
    _ = @import("MoveList.zig");
    _ = @import("State.zig");
    _ = @import("TTEntry.zig");
    // util
    _ = @import("util/NullWriter.zig");
    _ = @import("util/Prng.zig");
}
