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
    // Uncomment to always fetch dependency header
    // files instead of using pre-bundled ones.
    // .@"prefer-bundled-headers" = false,
});
your_exe.root_module.linkLibrary(glfw_dependency.artifact("glfw"));
```

## Pre-Bundled Dependencies

GLFW internally requires header files from various projects:

- `wayland-protocols` generated using `wayland-scanner`
- `wayland-client`
- `wayland-cursor`
- `wayland-egl`
- `libxkbcommon`
- `xorgproto`
- `libx11`
- `libxrandr`
- `libxinerama`
- `libxcursor`
- `libxi`
- `libxext`
- `libxrender`
- `libxfixes`

By default, this repository avoids fetching from all of these projects and instead uses pre-bundled header files that can be found in the `deps` directory.

The following options are offered to opt into alternative approaches:

- Fetch from upstream repositories which can be enabled using `-Dprefer-bundled-headers=false`.
- Lookup dependencies on the host system which can be enabled using Zig's [System Integration Options](https://ziglang.org/download/0.12.0/release-notes.html#Ability-to-Declare-Optional-System-Library-Integration).

### Update

The header files have been collected using the following command:

```
zig build -Donly-install-dependency-headers -Dprefer-bundled-headers=false -Dx11 -Dwayland --prefix deps
```
