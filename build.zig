const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("smartcard", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (sdkFrameworkPath(b)) |path| mod.addFrameworkPath(path);
    mod.linkFramework("PCSC", .{});

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Auto-detect SoftHSM2 for testing.
    if (softhsm2Setup(b)) |env| {
        run_mod_tests.setEnvironmentVariable("SOFTHSM2_PATH", env.lib_path);
        run_mod_tests.setEnvironmentVariable("SOFTHSM2_CONF", env.conf_path);
    }

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}

const SoftHsm2Env = struct {
    lib_path: []const u8,
    conf_path: []const u8,
};

fn softhsm2Setup(b: *std.Build) ?SoftHsm2Env {
    // Find the library by resolving softhsm2-util on PATH.
    const result = std.process.Child.run(.{
        .allocator = b.allocator,
        .argv = &.{ "which", "softhsm2-util" },
    }) catch return null;
    defer b.allocator.free(result.stdout);
    defer b.allocator.free(result.stderr);

    if (result.term.Exited != 0) return null;

    const bin_path = std.mem.trimRight(u8, result.stdout, "\n\r ");
    const bin_dir = std.fs.path.dirname(bin_path) orelse return null;
    const base_dir = std.fs.path.dirname(bin_dir) orelse return null;
    const lib_path = std.fs.path.join(b.allocator, &.{ base_dir, "lib", "softhsm", "libsofthsm2.so" }) catch return null;

    std.fs.accessAbsolute(lib_path, .{}) catch {
        b.allocator.free(lib_path);
        return null;
    };

    // Create temp token directory and config file under the build cache.
    const tmp = b.makeTempPath();
    var tmp_dir = b.build_root.handle.makeOpenPath(tmp, .{}) catch return null;
    defer tmp_dir.close();
    tmp_dir.makeDir("tokens") catch return null;

    var tokens_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tokens_path = tmp_dir.realpath("tokens", &tokens_buf) catch return null;

    const conf_content = std.fmt.allocPrint(b.allocator, "directories.tokendir = {s}\n", .{tokens_path}) catch return null;
    defer b.allocator.free(conf_content);
    tmp_dir.writeFile(.{ .sub_path = "softhsm2.conf", .data = conf_content }) catch return null;

    var conf_buf: [std.fs.max_path_bytes]u8 = undefined;
    const conf_path = b.allocator.dupe(u8, tmp_dir.realpath("softhsm2.conf", &conf_buf) catch return null) catch return null;

    return .{
        .lib_path = lib_path,
        .conf_path = conf_path,
    };
}

fn sdkFrameworkPath(b: *std.Build) ?std.Build.LazyPath {
    // Try xcrun first.
    if (std.process.Child.run(.{
        .allocator = b.allocator,
        .argv = &.{ "/usr/bin/xcrun", "--show-sdk-path" },
    })) |result| {
        defer b.allocator.free(result.stdout);
        defer b.allocator.free(result.stderr);
        if (result.term.Exited == 0) {
            const sdk = std.mem.trimRight(u8, result.stdout, "\n\r ");
            const path = std.fs.path.join(b.allocator, &.{ sdk, "System/Library/Frameworks" }) catch return null;
            return .{ .cwd_relative = path };
        }
    } else |_| {}

    // Fallback: CommandLineTools SDK.
    const fallback = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks";
    std.fs.accessAbsolute(fallback, .{}) catch return null;
    return .{ .cwd_relative = fallback };
}
