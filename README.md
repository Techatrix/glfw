[![CI](https://github.com/Techatrix/glfw/actions/workflows/ci.yaml/badge.svg)](https://github.com/Techatrix/glfw/actions)

# glfw

This is [glfw](https://github.com/glfw/glfw), packaged for [Zig](https://ziglang.org/).

## Installation

First, update your `build.zig.zon`:

```
# Initialize a `zig build` project if you haven't already
zig init
zig fetch --save git+https://github.com/Techatrix/glfw.git
```

You can then import `glfw` in your `build.zig` with:

```zig
const glfw_dependency = b.dependency("glfw", .{
    .target = target,
    .optimize = optimize,
    // Uncomment to fetch dependency header files
    // instead of using prebundled ones.
    // .@"use-prebundled-headers" = false,
});
your_exe.root_module.linkLibrary(glfw_dependency.artifact("glfw"));
```

## Prebundled Dependencies

GLFW internally requires header files from various projects:

- wayland-protocols generated using wayland-scanner
- wayland-client
- wayland-cursor
- wayland-egl
- libxkbcommon
- xorgproto
- libx11
- libxrandr
- libxinerama
- libxcursor
- libxi
- libxext
- libxrender
- libxfixes

By default, this repository avoids fetching from all these projects but instead use prebundled header files that can be found in the `deps` directory.

This behavior can be configured with the `-Duse-prebundled-headers` config option.

The header files have been collected using the following command:

```
zig build -Donly-install-dependency-headers -Duse-prebundled-headers=false --prefix deps
```
