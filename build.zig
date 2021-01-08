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

pub fn build(b: *bld.Builder) void {
    const exe = b.addExecutable("ztest", "src/ztest.zig");
    exe.setBuildMode(b.standardReleaseOptions());
    if (exe.target.isLinux()) {
        exe.addLibPath("/usr/lib/x86_64-linux-gnu/");
        exe.linkSystemLibrary("SDL2");
        exe.linkSystemLibrary("c");
        exe.install();
        b.step("run", "Run ztest").dependOn(&exe.run().step);
    }
}
