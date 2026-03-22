const std = @import("std");

pub fn build(b: *std.Build) void {
    // Native target (for testing + CLI)
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // -------------------------------------------------------
    // Library module (platform-agnostic core)
    // -------------------------------------------------------
    const mod = b.addModule("num_wasm", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // -------------------------------------------------------
    // Native executable (optional CLI / playground)
    // -------------------------------------------------------
    const exe = b.addExecutable(.{
        .name = "num_wasm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "num_wasm", .module = mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // -------------------------------------------------------
    // WASM target  —  `zig build wasm`
    // -------------------------------------------------------
    const wasm = b.addExecutable(.{
        .name = "num-wasm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wasm_api.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .wasm32,
                .os_tag = .freestanding,
            }),
            .optimize = .ReleaseFast,
        }),
    });

    // WASM-specific settings
    wasm.entry = .disabled; // No _start — JS calls exports directly
    wasm.rdynamic = true; // Make `export fn` symbols visible to JS

    const install_wasm = b.addInstallArtifact(wasm, .{});

    const wasm_step = b.step("wasm", "Build WASM binary");
    wasm_step.dependOn(&install_wasm.step);

    // -------------------------------------------------------
    // Tests  —  `zig build test`
    // -------------------------------------------------------
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
