const p_mg = [_]i16{
    0,   0,   0,   0,   0,   0,   0,   0,
    16,  52,  41,  27,  36,  76,  102, 35,
    27,  56,  52,  49,  59,  52,  94,  42,
    25,  50,  55,  69,  72,  60,  58,  28,
    24,  60,  58,  75,  82,  65,  63,  24,
    30,  78,  57,  98,  98,  113, 32,  55,
    158, 143, 130, 186, 167, 89,  -19, 26,
    0,   0,   0,   0,   0,   0,   0,   0,
};

const p_eg = [_]i16{
    0,   0,   0,   0,   0,   0,   0,   0,
    208, 207, 199, 196, 193, 188, 190, 173,
    199, 197, 179, 180, 180, 183, 188, 175,
    214, 206, 183, 174, 173, 175, 206, 187,
    257, 233, 195, 192, 169, 190, 221, 219,
    332, 319, 311, 265, 256, 228, 351, 282,
    416, 433, 402, 334, 324, 404, 457, 404,
    0,   0,   0,   0,   0,   0,   0,   0,
};

const n_mg = [_]i16{
    195, 229, 231, 226, 235, 255, 236, 221,
    215, 224, 246, 250, 251, 261, 249, 245,
    234, 256, 259, 269, 270, 269, 274, 233,
    248, 260, 271, 272, 279, 278, 279, 260,
    262, 267, 292, 301, 287, 322, 278, 293,
    266, 290, 296, 334, 350, 347, 298, 259,
    229, 263, 290, 316, 300, 351, 233, 247,
    137, 191, 163, 230, 309, 63,  165, 142,
};

const n_eg = [_]i16{
    413, 376, 415, 437, 425, 414, 384, 350,
    402, 446, 454, 458, 452, 434, 444, 400,
    424, 454, 463, 497, 504, 469, 456, 418,
    438, 490, 509, 512, 501, 495, 480, 446,
    448, 488, 509, 509, 522, 498, 486, 446,
    441, 474, 505, 496, 485, 483, 490, 444,
    431, 448, 466, 479, 456, 448, 417, 435,
    335, 460, 482, 452, 434, 489, 444, 359,
};

const b_mg = [_]i16{
    233, 280, 264, 263, 275, 254, 273, 246,
    277, 283, 286, 270, 279, 291, 298, 280,
    276, 289, 282, 288, 279, 293, 288, 284,
    278, 286, 292, 309, 311, 290, 284, 283,
    264, 286, 300, 327, 320, 310, 298, 283,
    280, 286, 292, 326, 342, 337, 300, 311,
    247, 284, 289, 283, 302, 294, 292, 275,
    249, 252, 239, 208, 220, 120, 220, 274,
};

const b_eg = [_]i16{
    460, 444, 429, 485, 464, 457, 462, 472,
    454, 465, 482, 503, 501, 480, 473, 472,
    477, 497, 530, 527, 538, 510, 497, 468,
    468, 521, 540, 544, 524, 533, 507, 465,
    500, 524, 530, 531, 538, 507, 516, 502,
    501, 535, 526, 521, 499, 536, 523, 474,
    496, 498, 520, 517, 518, 508, 509, 456,
    471, 500, 511, 520, 535, 539, 500, 501,
};

const r_mg = [_]i16{
    309, 316, 321, 326, 332, 313, 292, 309,
    291, 314, 302, 302, 320, 332, 335, 271,
    300, 291, 310, 312, 319, 315, 330, 309,
    304, 298, 313, 319, 331, 334, 331, 321,
    308, 321, 344, 346, 340, 343, 345, 329,
    325, 342, 356, 383, 412, 406, 377, 364,
    358, 364, 384, 412, 421, 411, 363, 362,
    399, 402, 418, 429, 413, 398, 415, 421,
};

const r_eg = [_]i16{
    806, 823, 834, 835, 824, 827, 827, 767,
    805, 806, 821, 820, 807, 816, 790, 786,
    803, 826, 825, 830, 813, 821, 805, 793,
    836, 848, 857, 850, 839, 838, 832, 805,
    859, 871, 870, 872, 866, 872, 854, 842,
    878, 878, 873, 868, 858, 860, 864, 852,
    872, 877, 875, 868, 864, 853, 869, 861,
    845, 851, 848, 854, 857, 863, 855, 842,
};

const q_mg = [_]i16{
    842, 844, 845, 853, 847, 823, 860, 871,
    845, 853, 860, 847, 854, 875, 859, 836,
    842, 857, 852, 845, 840, 852, 854, 852,
    850, 836, 846, 851, 855, 850, 860, 847,
    847, 839, 841, 857, 861, 868, 855, 865,
    837, 846, 855, 874, 899, 899, 879, 878,
    834, 829, 856, 830, 838, 874, 847, 858,
    783, 897, 883, 913, 897, 902, 831, 835,
};

const q_eg = [_]i16{
    1381, 1363, 1367, 1377, 1364, 1355, 1319, 1287,
    1333, 1411, 1393, 1418, 1409, 1366, 1357, 1367,
    1411, 1414, 1448, 1451, 1462, 1455, 1460, 1410,
    1416, 1466, 1485, 1517, 1512, 1511, 1468, 1457,
    1435, 1483, 1530, 1519, 1559, 1527, 1548, 1479,
    1468, 1471, 1496, 1533, 1539, 1560, 1520, 1502,
    1465, 1492, 1519, 1553, 1579, 1529, 1539, 1500,
    1528, 1442, 1491, 1502, 1498, 1497, 1528, 1519,
};

const k_mg = [_]i16{
    -62, 13,  -11, -87,  -16,  -52,  38,   33,
    17,  -20, -32, -87,  -87,  -47,  -3,   16,
    -35, -51, -99, -123, -155, -102, -62,  -67,
    -58, 11,  -98, -73,  -122, -137, -108, -128,
    -5,  -68, -54, -132, -82,  -65,  -109, -168,
    -15, 15,  -53, -11,  -39,  1,    -39,  -125,
    176, 62,  14,  23,   13,   -48,  -66,  -67,
    474, 181, 144, 123,  61,   69,   195,  198,
};

const k_eg = [_]i16{
    -69,  -80, -62, -65, -111, -75, -96, -121,
    -71,  -45, -29, -12, -19,  -29, -44, -74,
    -43,  -20, -3,  16,  21,   7,   -19, -46,
    -33,  -1,  26,  22,  34,   35,  14,  -27,
    -15,  23,  40,  52,  49,   55,  55,  28,
    -2,   25,  37,  33,  37,   42,  57,  35,
    -56,  0,   25,  17,  18,   48,  54,  21,
    -219, -41, -17, -26, 26,   19,  -49, -71,
};

const tempo = [2]i16{ 7, 4 };

pub fn eval(game: *const Game) i14 {
    const mg_phase = phase(&game.board);
    const eg_phase = 24 - mg_phase;
    var score: i32 = 0;
    for (0..16) |id| {
        const where = coord.compress(game.board.where[id]);
        score += switch (game.board.pieces[id]) {
            .none => 0,
            .k => k_mg[where] * mg_phase + k_eg[where] * eg_phase,
            .q => q_mg[where] * mg_phase + q_eg[where] * eg_phase,
            .r => r_mg[where] * mg_phase + r_eg[where] * eg_phase,
            .b => b_mg[where] * mg_phase + b_eg[where] * eg_phase,
            .n => n_mg[where] * mg_phase + n_eg[where] * eg_phase,
            .p => p_mg[where] * mg_phase + p_eg[where] * eg_phase,
        };
    }
    for (16..32) |id| {
        const where = coord.compress(game.board.where[id] ^ 0x70);
        score -= switch (game.board.pieces[id]) {
            .none => 0,
            .k => k_mg[where] * mg_phase + k_eg[where] * eg_phase,
            .q => q_mg[where] * mg_phase + q_eg[where] * eg_phase,
            .r => r_mg[where] * mg_phase + r_eg[where] * eg_phase,
            .b => b_mg[where] * mg_phase + b_eg[where] * eg_phase,
            .n => n_mg[where] * mg_phase + n_eg[where] * eg_phase,
            .p => p_mg[where] * mg_phase + p_eg[where] * eg_phase,
        };
    }
    score = switch (game.board.active_color) {
        .white => score,
        .black => -score,
    };
    score += tempo[0] * mg_phase + p_eg[1] * eg_phase;
    score = @divTrunc(score, 24);
    return clampScore(score);
}

pub fn phase(board: *const Board) i32 {
    var result: i32 = 0;
    for (board.pieces) |ptype| {
        result += switch (ptype) {
            .none, .k, .p => 0,
            .q => 4,
            .r => 2,
            .b => 1,
            .n => 1,
        };
    }
    return @min(result, 24);
}

pub fn clampScore(raw: anytype) Score {
    return @intCast(std.math.clamp(raw, -8000, 8000));
}
pub fn isMateScore(score: Score) bool {
    return @abs(score) > 8000;
}
pub fn isMated(score: Score) bool {
    return score < -8000;
}
pub fn distanceToMate(score: Score) ?i32 {
    if (!isMateScore(score)) return null;
    const dist: i32 = @intCast(std.math.divCeil(u32, @abs(mated) - @abs(score), 2) catch unreachable);
    return std.math.sign(score) * dist;
}

pub const Score = i14;
pub const no_moves: Score = -std.math.maxInt(Score);
pub const draw: Score = 0;
pub const mated: Score = no_moves + 1;

const std = @import("std");
const Board = @import("Board.zig");
const Game = @import("Game.zig");
const coord = @import("coord.zig");
