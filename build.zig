const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target and optimize options that can be shared
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add the HTTP client module
    const http_client_module = b.addModule("http-client", .{
        .root_source_file = b.path("src/http_client.zig"),
    });

    // Create the executable
    const exe = b.addExecutable(.{
        .name = "your-exe-name",
        .root_source_file = b.path("src/main.zig"),
        .target = target, // Use the shared target
        .optimize = optimize, // Use the shared optimize
    });

    // Add module as a dependency to the executable
    exe.root_module.addImport("http-client", http_client_module);

    // Create the run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Create a run step
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_source_file = b.path("src/http_client_test.zig"),
        .target = target, // Use the shared target
        .optimize = optimize, // Use the shared optimize
    });

    tests.root_module.addImport("http-client", http_client_module);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
