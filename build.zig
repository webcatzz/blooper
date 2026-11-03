const sokol = @import("sokol");
const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Adds Sokol

    const sokol_dep = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });
    const sokol_mod = sokol_dep.module("sokol");

    // Transpiles shaders

    const shd_mod = try sokol.shdc.createModule(b, "shader", sokol_mod, .{
        .shdc_dep = sokol_dep.builder.dependency("shdc", .{}),
        .input = "res/shd/basic.glsl",
        .output = "res/shd/basic.zig",
        .slang = .{
            .glsl410 = true,
            .glsl300es = true,
            .hlsl4 = true,
            .metal_macos = true,
            .wgsl = true,
        },
    });

    // Collects sprite info

    const spr_exe = b.addExecutable(.{
        .name = "spr",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/spr.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ase", .module = b.createModule(.{ .root_source_file = b.path("src/util/ase.zig") }) },
            },
        }),
    });

    const spr_cmd = b.addRunArtifact(spr_exe);
    const spr_path = spr_cmd.addOutputFileArg2("res/spr.zon", .{});
    spr_cmd.addFileArg2(b.path("res/spr.aseprite"), .{});

    // Creates module

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "shd_basic", .module = shd_mod },
            .{ .name = "sokol", .module = sokol_mod },
            .{ .name = "spr_info", .module = b.createModule(.{ .root_source_file = spr_path }) },
        },
    });

    const exe = b.addExecutable(.{
        .name = "blooper",
        .root_module = mod,
    });

    b.installArtifact(exe);

    // `check`

    const ck_step = b.step("check", "Analyze code without compiling");

    const ck_exe = b.addExecutable(.{
        .name = "blooper",
        .root_module = mod,
    });

    ck_step.dependOn(&ck_exe.step);

    // `run`

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    run_step.dependOn(&spr_cmd.step);
    run_step.dependOn(&run_cmd.step);
}
