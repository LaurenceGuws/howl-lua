const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("howl_lua", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{
        .root_module = mod,
    });
    tests.use_llvm = true;
    tests.root_module.link_libc = true;
    tests.root_module.linkSystemLibrary("lua5.4", .{ .use_pkg_config = .force });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run module tests");
    test_step.dependOn(&run_tests.step);
}
