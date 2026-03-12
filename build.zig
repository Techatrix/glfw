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
    const prefer_prebundled_headers = b.option(bool, "prefer-bundled-headers", "Prefer pre-bundled dependency headers instead of fetching from upstream repositories");

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
    if (!install_dependency_headers) glfw.installHeadersDirectory(upstream.path("include"), "", .{});
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

    if (install_dependency_headers) {
        b.getInstallStep().dependOn(&b.addInstallArtifact(glfw, .{
            .dest_dir = .disabled,
            .pdb_dir = .disabled,
            .h_dir = .{ .override = .prefix },
            .implib_dir = .disabled,
        }).step);
    } else {
        b.installArtifact(glfw);
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

    if (enable_x11 or enable_wayland) {
        if (target.result.os.tag == .linux) {
            glfw.root_module.addCSourceFile(.{ .file = upstream.path("src/linux_joystick.c"), .flags = flags });
        }
        glfw.root_module.addCSourceFile(.{ .file = upstream.path("src/xkb_unicode.c"), .flags = flags });
        glfw.root_module.addCSourceFile(.{ .file = upstream.path("src/posix_poll.c"), .flags = flags });
    }

    const x11_header_subdir = "x11-headers";
    const wayland_protocols_header_subdir = "wayland-protocols-headers";
    const wayland_header_subdir = "wayland-headers";
    const libxkbcommon_header_subdir = "libxkbcommon-headers";

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

        const use_system_x11_headers = b.systemIntegrationOption("x11-headers", .{});
        if (prefer_prebundled_headers orelse !use_system_x11_headers) {
            glfw.root_module.addIncludePath(b.path(b.pathJoin(&.{ "deps", x11_header_subdir })));
            if (install_dependency_headers) {
                try b.getInstallStep().addError(
                    \\Using '-Donly-install-dependency-headers' without '-Dprefer-bundled-headers=false' would cause the pre-bundled header to be reinstalled.
                , .{});
            }
        } else {
            for ([_][]const u8{
                "xorgproto",
                "libx11",
                "libxrandr",
                "libxinerama",
                "libxcursor",
                "libxi",
                "libxext",
                "libxrender", // dependency of libxrandr
                "libxfixes", //dependency of libxi and libxcursor
            }) |name| {
                if (use_system_x11_headers) {
                    const pkg_name = if (std.mem.eql(u8, name, "xorgproto"))
                        "xproto"
                    else
                        std.mem.trimStart(u8, name, "lib");
                    const include_dirs = collectPkgConfigIncludeDirs(b, pkg_name) catch |err| {
                        glfw.step.addError("failed to resolve '{s}' package: {}", .{ pkg_name, err }) catch @panic("OOM");
                        continue;
                    };
                    for (include_dirs) |include_dir| {
                        glfw.root_module.addIncludePath(.{ .cwd_relative = include_dir });
                        if (install_dependency_headers) glfw.installHeadersDirectory(.{ .cwd_relative = include_dir }, x11_header_subdir, .{});
                    }
                } else if (b.lazyDependency(name, .{})) |dependency| {
                    if (std.mem.eql(u8, name, "libxcursor")) {
                        const xcursor_header = b.addConfigHeader(.{
                            .style = .{ .autoconf_undef = dependency.path("include/X11/Xcursor/Xcursor.h.in") },
                            .include_path = "X11/Xcursor/Xcursor.h",
                        }, .{
                            .XCURSOR_LIB_MAJOR = @as(i64, @intCast(xcursor_version.major)),
                            .XCURSOR_LIB_MINOR = @as(i64, @intCast(xcursor_version.minor)),
                            .XCURSOR_LIB_REVISION = @as(i64, @intCast(xcursor_version.patch)),
                        });
                        glfw.root_module.addConfigHeader(xcursor_header);
                        if (install_dependency_headers) glfw.installHeader(xcursor_header.getOutputFile(), b.pathJoin(&.{ x11_header_subdir, xcursor_header.include_path }));
                    } else {
                        glfw.root_module.addIncludePath(dependency.path("include"));
                        if (install_dependency_headers) glfw.installHeadersDirectory(dependency.path("include"), x11_header_subdir, .{});
                    }
                }
            }
        }
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

        const use_system_wayland_scanner = b.systemIntegrationOption("wayland-scanner", .{});
        if (prefer_prebundled_headers orelse !use_system_wayland_scanner) {
            glfw.root_module.addIncludePath(b.path(b.pathJoin(&.{ "deps", wayland_protocols_header_subdir })));
            if (install_dependency_headers) {
                try b.getInstallStep().addError(
                    \\Using '-Donly-install-dependency-headers' without '-Dprefer-bundled-headers=false' would cause the pre-bundled header to be reinstalled.
                , .{});
            }
        } else {
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
                    const filename = b.fmt("{s}-client-protocol.h", .{output_name});
                    const header_file = run_wayland_scanner1.addOutputFileArg(filename);
                    glfw.root_module.addIncludePath(header_file.dirname());
                    if (install_dependency_headers) glfw.installHeader(header_file, b.pathJoin(&.{ wayland_protocols_header_subdir, filename }));
                }

                {
                    run_wayland_scanner2.addArg("private-code");
                    run_wayland_scanner2.addFileArg(upstream.path("deps/wayland").path(b, input_file));
                    const filename = b.fmt("{s}-client-protocol-code.h", .{output_name});
                    const header_file = run_wayland_scanner2.addOutputFileArg(filename);
                    glfw.root_module.addIncludePath(header_file.dirname());
                    if (install_dependency_headers) glfw.installHeader(header_file, b.pathJoin(&.{ wayland_protocols_header_subdir, filename }));
                }
            }
        }

        const use_system_wayland_headers = b.systemIntegrationOption("wayland-headers", .{});
        if (prefer_prebundled_headers orelse !use_system_wayland_headers) {
            glfw.root_module.addIncludePath(b.path(b.pathJoin(&.{ "deps", wayland_header_subdir })));
            if (install_dependency_headers) {
                try b.getInstallStep().addError(
                    \\Using '-Donly-install-dependency-headers' without '-Dprefer-bundled-headers=false' would cause the pre-bundled header to be reinstalled.
                , .{});
            }
        } else {
            for ([_][]const u8{
                "wayland-client",
                "wayland-cursor",
                "wayland-egl",
            }) |name| {
                if (use_system_wayland_headers) {
                    const include_dirs = collectPkgConfigIncludeDirs(b, name) catch |err| {
                        glfw.step.addError("failed to resolve '{s}' package: {}", .{ name, err }) catch @panic("OOM");
                        continue;
                    };
                    for (include_dirs) |include_dir| {
                        glfw.root_module.addIncludePath(.{ .cwd_relative = include_dir });
                        if (install_dependency_headers) glfw.installHeadersDirectory(.{ .cwd_relative = include_dir }, "", .{});
                    }
                } else if (b.lazyDependency("wayland", .{
                    .target = target,
                    .optimize = optimize,
                })) |wayland| {
                    const lib = wayland.artifact(name);
                    glfw.root_module.include_dirs.appendSlice(b.allocator, lib.root_module.include_dirs.items) catch @panic("OOM");
                    if (install_dependency_headers) {
                        for (lib.installed_headers.items) |installation| {
                            switch (installation) {
                                .directory => |directory| glfw.installHeadersDirectory(directory.source, b.pathJoin(&.{ wayland_header_subdir, directory.dest_rel_path }), directory.options),
                                .file => |file| glfw.installHeader(file.source, b.pathJoin(&.{ wayland_header_subdir, file.dest_rel_path })),
                            }
                        }
                    }
                }
            }
        }

        const use_system_libxkbcommon_headers = b.systemIntegrationOption("libxkbcommon", .{});
        if (prefer_prebundled_headers orelse !use_system_libxkbcommon_headers) {
            glfw.root_module.addIncludePath(b.path(b.pathJoin(&.{ "deps", libxkbcommon_header_subdir })));
            if (install_dependency_headers) {
                try b.getInstallStep().addError(
                    \\Using '-Donly-install-dependency-headers' without '-Dprefer-bundled-headers=false' would cause the pre-bundled header to be reinstalled.
                , .{});
            }
        } else {
            if (use_system_libxkbcommon_headers) blk: {
                const include_dirs = collectPkgConfigIncludeDirs(b, "xkbcommon") catch |err| {
                    glfw.step.addError("failed to resolve '{s}' package: {}", .{ "xkbcommon", err }) catch @panic("OOM");
                    break :blk;
                };
                for (include_dirs) |include_dir| {
                    glfw.root_module.addIncludePath(.{ .cwd_relative = include_dir });
                    if (install_dependency_headers) glfw.installHeadersDirectory(.{ .cwd_relative = include_dir }, libxkbcommon_header_subdir, .{});
                }
            } else if (b.lazyDependency("libxkbcommon", .{})) |dependency| {
                glfw.root_module.addIncludePath(dependency.path("include"));
                if (install_dependency_headers) glfw.installHeadersDirectory(dependency.path("include"), libxkbcommon_header_subdir, .{});
            }
        }
    }
}

/// Similar to `linkSystemLibrary` but only adds include directories.
/// This functionality would ideally be provided by the build system.
fn collectPkgConfigIncludeDirs(b: *std.Build, pkg_name: []const u8) ![][]const u8 {
    var code: u8 = undefined;
    const pkg_config_exe = b.graph.env_map.get("PKG_CONFIG") orelse "pkg-config";
    const stdout = if (b.runAllowFail(&[_][]const u8{
        pkg_config_exe,
        pkg_name,
        "--cflags-only-I",
    }, &code, .Ignore)) |stdout| stdout else |err| switch (err) {
        error.ProcessTerminated => return error.PkgConfigCrashed,
        error.ExecNotSupported => return error.PkgConfigFailed,
        error.ExitCodeFailure => return error.PkgConfigFailed,
        error.FileNotFound => return error.PkgConfigNotInstalled,
        else => return err,
    };

    var include_dirs: std.ArrayList([]const u8) = .empty;
    var arg_it = std.mem.tokenizeAny(u8, stdout, " \r\n\t");
    while (arg_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "-I")) {
            const dir = arg_it.next() orelse return error.PkgConfigInvalidOutput;
            include_dirs.append(b.allocator, dir) catch @panic("OOM");
        } else if (std.mem.startsWith(u8, arg, "-I")) {
            include_dirs.append(b.allocator, arg["-I".len..]) catch @panic("OOM");
        }
    }

    return include_dirs.items;
}
