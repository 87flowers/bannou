const std = @import("std");
const OptimizeMode = std.builtin.OptimizeMode;
const ResolvedTarget = std.Build.ResolvedTarget;

fn add(b: *std.Build, target: ResolvedTarget, optimize: OptimizeMode, step_cmd: []const u8, description: []const u8, exe_name: []const u8, root_source_file: []const u8) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = exe_name,
        .root_source_file = b.path(root_source_file),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step(step_cmd, description);
    run_step.dependOn(&run_cmd.step);

    return exe;
}

fn addTests(b: *std.Build) void {
    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const bannou_exe = add(b, target, optimize, "run", "Run chess engine", "bannou", "src/main.zig");
    _ = add(b, target, optimize, "generate-psts", "Generate piece square tables", "generate_psts", "src/generate_psts.zig");
    _ = add(b, target, optimize, "generate-zhash", "Generate Zobrist hash tables", "generate_zhash", "src/generate_zhash.zig");
    _ = add(b, target, optimize, "generate-data", "Generate game data", "generate_data", "src/generate_data.zig");

    addTests(b);

    const bench_cmd = b.addRunArtifact(bannou_exe);
    bench_cmd.addArg("bench");
    const bench_cmd_step = b.step("bench", "Run chess engine internal benchmark");
    bench_cmd_step.dependOn(&bench_cmd.step);
}
