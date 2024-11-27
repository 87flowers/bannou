pub fn eval(game: *Game) i32 {
    var score: i32 = 0;
    for (0..16) |w| {
        score += switch (game.board.pieces[w]) {
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
        score += switch (game.board.pieces[b]) {
            .none => 0,
            .k => -1000000,
            .q => -1000,
            .r => -500,
            .b => -310,
            .n => -300,
            .p => -100,
        };
    }
    const fudge = @as(i32, @intCast(game.board.state.hash & 0x1f)) - 0xf;
    score += fudge;
    return switch (game.board.active_color) {
        .white => score,
        .black => -score,
    };
}

const Game = @import("Game.zig");
