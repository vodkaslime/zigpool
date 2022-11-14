const std = @import("std");

const zigpool_pkg = std.build.Pkg {
    .name = "zigpool",
    .source = std.build.FileSource {
        .path = "src/zigpool.zig",
    },
};

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const lib = b.addStaticLibrary("zigpool", "src/zigpool.zig");
    lib.setBuildMode(mode);
    lib.install();

    const test_step = b.step("test", "Run library tests");

    inline for (.{
        "src/zigpool.zig",
        "src/mpmc.zig",
    }) |test_file| {
        const t = b.addTest(test_file);
        t.setBuildMode(mode);

        test_step.dependOn(&t.step);
    }

    const example_step = b.step("examples", "Build examples");
    inline for (.{
        "simple",
    }) |example_name| {
        const example = b.addExecutable(example_name, "examples/" ++ example_name ++ ".zig");
        example.addPackage(zigpool_pkg);
        example.setBuildMode(mode);
        example.setTarget(target);
        example.install();
        example_step.dependOn(&example.step);
    }
}
