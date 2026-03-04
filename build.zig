const std = @import("std");

const xcursor_version = std.SemanticVersion.parse("1.2.3") catch unreachable;

pub fn build(b: *std.Build) !void {
    const upstream = b.dependency("glfw", .{});
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(std.builtin.LinkMode, "linkage", "Link mode") orelse .static;

    const enable_win32 = b.option(bool, "win32", "Build support for Win32") orelse (target.result.os.tag == .windows);
    const enable_cocoa = b.option(bool, "cocoa", "Build support for Cocoa") orelse (target.result.os.tag.isDarwin());
    const enable_x11 = b.option(bool, "x11", "Build support for X11") orelse (target.result.os.tag != .windows and !target.result.os.tag.isDarwin());
    const enable_wayland = b.option(bool, "wayland", "Build support for Wayland") orelse (target.result.os.tag != .windows and !target.result.os.tag.isDarwin());

    const install_dependency_headers = b.option(bool, "only-install-dependency-headers", "Only install header files of dependencies (default: false)") orelse false;
    const use_prebundled_headers = b.option(bool, "use-prebundled-headers", "Use prebundled dependency headers instead of fetching them (default: true)") orelse true;

    const flags: []const []const u8 = &.{
        "-fvisibility=hidden",
    };

    const glfw = b.addLibrary(.{
        .linkage = linkage,
        .name = "glfw",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    glfw.installHeadersDirectory(upstream.path("include"), "", .{});
    if (linkage == .dynamic) glfw.root_module.addCMacro("_GLFW_BUILD_DLL", "");
    glfw.root_module.addCSourceFiles(.{
        .root = upstream.path("src"),
        .flags = flags,
        .files = &.{
            "context.c",
            "init.c",
            "input.c",
            "monitor.c",
            "platform.c",
            "vulkan.c",
            "window.c",
            "egl_context.c",
            "osmesa_context.c",
            "null_init.c",
            "null_monitor.c",
            "null_window.c",
            "null_joystick.c",
        },
    });

    if (install_dependency_headers and use_prebundled_headers) {
        try b.getInstallStep().addError(
            \\Using '-Donly-install-dependency-headers' without '-Duse-prebundled-headers=false' would cause the prebundled header to be reinstalled.
        , .{});
    } else if (install_dependency_headers) {
        b.getInstallStep().dependOn(&b.addInstallArtifact(glfw, .{
            .dest_dir = .disabled,
            .pdb_dir = .disabled,
            .h_dir = .default,
            .implib_dir = .disabled,
        }).step);
    } else {
        b.installArtifact(glfw);
    }

    if (use_prebundled_headers) {
        glfw.root_module.addIncludePath(b.path("deps/include"));
        if (enable_wayland) {
            glfw.root_module.addIncludePath(b.path("deps/include/wayland"));
            glfw.root_module.addIncludePath(b.path("deps/include/wayland-protocols"));
        }
    }

    if (target.result.os.tag.isDarwin()) {
        glfw.root_module.addCSourceFiles(.{
            .root = upstream.path("src"),
            .flags = flags,
            .files = &.{
                "cocoa_time.c",
                "posix_module.c",
                "posix_thread.c",
            },
        });
    } else if (target.result.os.tag == .windows) {
        glfw.root_module.addCSourceFiles(.{
            .root = upstream.path("src"),
            .flags = flags,
            .files = &.{
                "win32_module.c",
                "win32_time.c",
                "win32_thread.c",
            },
        });
        glfw.root_module.addCMacro("UNICODE", "_UNICODE");
    } else {
        glfw.root_module.addCSourceFiles(.{
            .root = upstream.path("src"),
            .flags = flags,
            .files = &.{
                "posix_module.c",
                "posix_time.c",
                "posix_thread.c",
            },
        });
    }

    if (enable_cocoa) {
        glfw.root_module.addCMacro("_GLFW_COCOA", "");
        glfw.root_module.addCSourceFiles(.{
            .root = upstream.path("src"),
            .flags = flags,
            .files = &.{
                "cocoa_init.m",
                "cocoa_joystick.m",
                "cocoa_monitor.m",
                "cocoa_window.m",
                "nsgl_context.m",
            },
        });
        glfw.root_module.linkFramework("Cocoa", .{});
        glfw.root_module.linkFramework("IOKit", .{});
        glfw.root_module.linkFramework("CoreFoundation", .{});

        if (b.lazyDependency("xcode_frameworks", .{
            .target = target,
            .optimize = optimize,
        })) |dep| {
            glfw.root_module.addSystemFrameworkPath(dep.path("Frameworks"));
            glfw.root_module.addSystemIncludePath(dep.path("include"));
            glfw.root_module.addLibraryPath(dep.path("lib"));
        }
    }

    if (enable_win32) {
        glfw.root_module.addCMacro("_GLFW_WIN32", "");
        glfw.root_module.addCSourceFiles(.{
            .root = upstream.path("src"),
            .flags = flags,
            .files = &.{
                "win32_init.c",
                "win32_joystick.c",
                "win32_monitor.c",
                "win32_window.c",
                "wgl_context.c",
            },
        });
        glfw.root_module.linkSystemLibrary("gdi32", .{});
    }

    if (enable_x11) {
        glfw.root_module.addCMacro("_GLFW_X11", "");
        glfw.root_module.addCSourceFiles(.{
            .root = upstream.path("src"),
            .flags = flags,
            .files = &.{
                "x11_init.c",
                "x11_monitor.c",
                "x11_window.c",
                "glx_context.c",
            },
        });
    }

    if (enable_wayland) {
        glfw.root_module.addCMacro("_GLFW_WAYLAND", "");
        glfw.root_module.addCSourceFiles(.{
            .root = upstream.path("src"),
            .flags = flags,
            .files = &.{
                "wl_init.c",
                "wl_monitor.c",
                "wl_window.c",
            },
        });

        const have_memfd_create = switch (target.result.os.tag) {
            .linux => target.result.isMuslLibC() or (target.result.isGnuLibC() and target.result.os.version_range.linux.glibc.order(.{ .major = 2, .minor = 7, .patch = 0 }) != .lt),
            .freebsd => target.result.os.isAtLeast(.freebsd, .{ .major = 13, .minor = 0, .patch = 0 }) orelse false,
            .netbsd => target.result.os.version_range.semver.isAtLeast(.{ .major = 11, .minor = 0, .patch = 0 }) orelse false,
            else => false,
        };
        if (have_memfd_create) glfw.root_module.addCMacro("HAVE_MEMFD_CREATE", "");

        if (target.result.os.tag == .freebsd) {
            if (b.lazyDependency("evdev_proto", .{})) |evdev_proto| {
                glfw.root_module.addIncludePath(evdev_proto.path("include"));
            }
        }
    }

    if (enable_x11 or enable_wayland) {
        if (target.result.os.tag == .linux) {
            glfw.root_module.addCSourceFile(.{ .file = upstream.path("src/linux_joystick.c"), .flags = flags });
        }
        glfw.root_module.addCSourceFile(.{ .file = upstream.path("src/xkb_unicode.c"), .flags = flags });
        glfw.root_module.addCSourceFile(.{ .file = upstream.path("src/posix_poll.c"), .flags = flags });
    }

    if (!use_prebundled_headers and (enable_x11 or enable_wayland)) {
        for ([_][]const u8{
            "xorgproto",
            "libx11",
            "libxrandr",
            "libxinerama",
            "libxi",
            "libxext",
            "libxrender", // dependency of libxrandr
            "libxfixes", //dependency of libxi and libxcursor
        }) |name| {
            if (b.lazyDependency(name, .{})) |dependency| {
                glfw.root_module.addIncludePath(dependency.path("include"));
                if (install_dependency_headers) glfw.installHeadersDirectory(dependency.path("include"), "", .{});
                // install_dependency_headers.dependOn(&b.addInstallDirectory(.{
                //     .source_dir = dependency.path("include"),
                //     .install_dir = .header,
                //     .install_subdir = "",
                //     .include_extensions = &.{".h"},
                // }).step);
            }
        }
        if (b.lazyDependency("libxcursor", .{})) |dependency| {
            const xcursor_header = b.addConfigHeader(.{
                .style = .{ .autoconf_undef = dependency.path("include/X11/Xcursor/Xcursor.h.in") },
                .include_path = "X11/Xcursor/Xcursor.h",
            }, .{
                .XCURSOR_LIB_MAJOR = @as(i64, @intCast(xcursor_version.major)),
                .XCURSOR_LIB_MINOR = @as(i64, @intCast(xcursor_version.minor)),
                .XCURSOR_LIB_REVISION = @as(i64, @intCast(xcursor_version.patch)),
            });
            glfw.root_module.addConfigHeader(xcursor_header);
            if (install_dependency_headers) glfw.installConfigHeader(xcursor_header);
            // install_dependency_headers.dependOn(&b.addInstallHeaderFile(xcursor_header.getOutputFile(), "X11/Xcursor/Xcursor.h").step);
        }
    }

    if (!use_prebundled_headers and enable_wayland) {
        const use_system_wayland_scanner = b.systemIntegrationOption("wayland-scanner", .{});
        const host_wayland = if (!use_system_wayland_scanner)
            b.lazyDependency("wayland", .{
                .target = b.graph.host,
                .optimize = std.builtin.OptimizeMode.Debug,
            })
        else
            null;

        for (
            [_][]const u8{
                "wayland.xml",
                "viewporter.xml",
                "xdg-shell.xml",
                "idle-inhibit-unstable-v1.xml",
                "pointer-constraints-unstable-v1.xml",
                "relative-pointer-unstable-v1.xml",
                "fractional-scale-v1.xml",
                "xdg-activation-v1.xml",
                "xdg-decoration-unstable-v1.xml",
            },
        ) |input_file| {
            const output_name = input_file[0 .. input_file.len - ".xml".len];

            const run_wayland_scanner1: *std.Build.Step.Run = .create(b, "run wayland-scanner");
            const run_wayland_scanner2: *std.Build.Step.Run = .create(b, "run wayland-scanner");
            if (use_system_wayland_scanner) {
                run_wayland_scanner1.addArg("wayland-scanner");
                run_wayland_scanner2.addArg("wayland-scanner");
            } else if (host_wayland) |wayland_host| {
                run_wayland_scanner1.addArtifactArg(wayland_host.artifact("wayland-scanner"));
                run_wayland_scanner2.addArtifactArg(wayland_host.artifact("wayland-scanner"));
            }

            {
                run_wayland_scanner1.addArg("client-header");
                run_wayland_scanner1.addFileArg(upstream.path("deps/wayland").path(b, input_file));
                const header_file = run_wayland_scanner1.addOutputFileArg(b.fmt("{s}-client-protocol.h", .{output_name}));
                if (!use_prebundled_headers) glfw.root_module.addIncludePath(header_file.dirname());
                if (install_dependency_headers) glfw.installHeader(header_file, b.fmt("wayland-protocols/{s}-client-protocol.h", .{output_name}));
                // install_dependency_headers.dependOn(&b.addInstallHeaderFile(
                //     header_file,
                //     b.fmt("wayland-protocols/{s}-client-protocol.h", .{output_name}),
                // ).step);
            }

            {
                run_wayland_scanner2.addArg("private-code");
                run_wayland_scanner2.addFileArg(upstream.path("deps/wayland").path(b, input_file));
                const header_file = run_wayland_scanner2.addOutputFileArg(b.fmt("{s}-client-protocol-code.h", .{output_name}));
                if (!use_prebundled_headers) glfw.root_module.addIncludePath(header_file.dirname());
                if (install_dependency_headers) glfw.installHeader(header_file, b.fmt("wayland-protocols/{s}-client-protocol-code.h", .{output_name}));
                // install_dependency_headers.dependOn(&b.addInstallHeaderFile(
                //     header_file,
                //     b.fmt("wayland-protocols/{s}-client-protocol-code.h", .{output_name}),
                // ).step);
            }
        }

        if (b.lazyDependency("wayland", .{
            .target = target,
            .optimize = optimize,
        })) |wayland| {
            for ([_][]const u8{
                "wayland-client",
                "wayland-cursor",
                "wayland-egl",
            }) |name| {
                const lib = wayland.artifact(name);
                if (!use_prebundled_headers) glfw.root_module.include_dirs.appendSlice(b.allocator, lib.root_module.include_dirs.items) catch @panic("OOM");
                if (install_dependency_headers) glfw.installLibraryHeaders(lib);
                // for (lib.installed_headers.items) |installation| {
                //     switch (installation) {
                //         .file => |file| {
                //             install_dependency_headers.dependOn(&b.addInstallHeaderFile(file.source, b.pathJoin(&.{ "wayland", file.dest_rel_path })).step);
                //         },
                //         .directory => |directory| install_dependency_headers.dependOn(&b.addInstallDirectory(.{
                //             .source_dir = directory.source,
                //             .install_dir = .header,
                //             .install_subdir = b.pathJoin(&.{ "wayland", directory.dest_rel_path }),
                //             .include_extensions = &.{".h"},
                //         }).step),
                //     }
                // }
            }
        }

        if (b.lazyDependency("libxkbcommon", .{})) |dependency| {
            if (!use_prebundled_headers) glfw.root_module.addIncludePath(dependency.path("include"));
            if (install_dependency_headers) glfw.installHeadersDirectory(dependency.path("include"), "", .{});
            // install_dependency_headers.dependOn(&b.addInstallDirectory(.{
            //     .source_dir = dependency.path("include"),
            //     .install_dir = .header,
            //     .install_subdir = "",
            //     .include_extensions = &.{".h"},
            // }).step);
        }
    }
}
