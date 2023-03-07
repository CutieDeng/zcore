const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();

    const allocator = gpa.allocator(); 

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    // const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "learn-freestanding",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        // .root_source_file = .{ .path = "src/main.zig" },
        .target = std.zig.CrossTarget {
            .cpu_arch = .riscv64,   
        }, 
        .optimize = optimize,
    });
    exe.code_model = .medium; 
    exe.c_std = .C11; 

    install(allocator, exe) catch |e| {
        std.debug.print("Error: {}\n", .{e}); 
    }; 

    // use zig to compile the C file in a directory 
    exe.install(); 

    const cmd = b.addSystemCommand( 
        &[_] [] const u8 {
            "/home/parallels/Downloads/qemu/qemu-system-riscv64", 
            "-machine", "virt", 
            "-nographic",
            "-bios", "default", 
            "-kernel", "zig-out/bin/learn-freestanding", 
        } 
    ); 
    cmd.step.dependOn(&exe.step); 

    const run = b.step("run", "Run the kernel in qemu"); 
    run.dependOn(&cmd.step);
}

pub fn install(allocator: std.mem.Allocator, exe : *std.Build.CompileStep) !void {
    // const dir = [_] [] const u8 { "libs", "kern" }; 
    var cwd = try std.fs.cwd().openIterableDir(".", .{} );  
    defer cwd.close(); 
    var walker = try cwd.walk(allocator); 
    defer walker.deinit(); 
    exe.setLinkerScriptPath(.{
        .path = "tools/kernel.ld", 
    }); 
    // exe.addIncludePath("libs"); 
    while (walker.next()) |walker_entry| {
        if (walker_entry) |real_entry| {
            const in_kern = std.mem.startsWith(u8, real_entry.path, "kern"); 
            const in_libs = std.mem.startsWith(u8, real_entry.path, "libs"); 
            if ( ! in_kern and ! in_libs ) {
                continue; 
            }
            if (real_entry.kind == .Directory) {
                exe.addIncludePath(real_entry.path);
                continue; 
            }
            if (std.mem.endsWith(u8, real_entry.path, ".c") or 
                std.mem.endsWith(u8, real_entry.path, ".S")) {
                std.debug.print("c file: {s}\n", .{real_entry.path}); 
                exe.addCSourceFile(real_entry.path, & [_] [] const u8 {
                    "--no-standard-includes",
                    "-fno-builtin",
                    "-O2", 
                    "-fno-stack-protector", 
                    "-ffunction-sections", 
                    "-fdata-sections", 
// CFLAGS	+= -fno-stack-protector -ffunction-sections -fdata-sections
                } ); 
            } else if (std.mem.endsWith(u8, real_entry.path, ".ld")) {
                std.debug.print("linker script: {s}\n", .{real_entry.path});
                exe.setLinkerScriptPath( 
                    .{ .path = real_entry.path, } 
                ); 
            } else {
                // std.debug.print("not a c file: {s}\n", .{real_entry.path}); 
            }
        } else {
            break; 
        }
    } else |_| { } 
}