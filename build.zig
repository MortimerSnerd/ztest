const bld = @import("std").build;
const mem = @import("std").mem;
const zig = @import("std").zig;

// macOS helper function to add SDK search paths
fn macosAddSdkDirs(b: *bld.Builder, step: *bld.LibExeObjStep) !void {
    const sdk_dir = try zig.system.getSDKPath(b.allocator);
    const framework_dir = try mem.concat(b.allocator, u8, &[_][]const u8 { sdk_dir, "/System/Library/Frameworks" });
    const usrinclude_dir = try mem.concat(b.allocator, u8, &[_][]const u8 { sdk_dir, "/usr/include"});
    step.addFrameworkDir(framework_dir);
    step.addIncludeDir(usrinclude_dir);
}

// build sokol into a static library
pub fn buildSokol(b: *bld.Builder, comptime prefix_path: []const u8) *bld.LibExeObjStep {
    const lib = b.addStaticLibrary("sokol", null);
    lib.linkLibC();
    lib.setBuildMode(b.standardReleaseOptions());
    if (prefix_path.len > 0) lib.addIncludeDir(prefix_path ++ "src/sokol/");
    if (lib.target.isDarwin()) {
        macosAddSdkDirs(b, lib) catch unreachable;
        lib.addCSourceFile(prefix_path ++ "sokol-zig/src/sokol/sokol.c", &[_][]const u8{"-ObjC"});
        lib.linkFramework("MetalKit");
        lib.linkFramework("Metal");
        lib.linkFramework("Cocoa");
        lib.linkFramework("QuartzCore");
        lib.linkFramework("AudioToolbox");
    } else {
        lib.addCSourceFile(prefix_path ++ "sokol-zig/src/sokol/sokol.c", &[_][]const u8{});
        if (lib.target.isLinux()) {
            lib.addLibPath("/usr/lib/x86_64-linux-gnu/");
            lib.linkSystemLibrary("X11");
            lib.linkSystemLibrary("Xi");
            lib.linkSystemLibrary("Xcursor");
            lib.linkSystemLibrary("GL");
            lib.linkSystemLibrary("asound");
        }
    }
    return lib;
}

pub fn build(b: *bld.Builder) void {
    const sokol = buildSokol(b, "");

    const exe = b.addExecutable("ztest", "src/ztest.zig");
    exe.linkLibrary(sokol);
    exe.setBuildMode(b.standardReleaseOptions());
    if (exe.target.isLinux()) {
        exe.linkLibC();
        exe.addIncludeDir("sokol-zig/src/sokol");
        exe.addLibPath("/usr/lib/x86_64-linux-gnu/");
        exe.addPackagePath("sokol", "sokol-zig/src/sokol/sokol.zig");
        exe.addPackagePath("zlm", "zlm/zlm.zig");
        exe.linkSystemLibrary("SDL2");
        exe.linkSystemLibrary("GL");
        exe.install();
        b.step("run", "Run ztest").dependOn(&exe.run().step);
    }
}
