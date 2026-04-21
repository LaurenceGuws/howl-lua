# Howl Lua

Small reusable Zig helpers for embedding Lua 5.4 through the C API.

Current surface:

- `api.State`: Lua state lifecycle and stack helpers
- `api.TableIter`: table iteration
- `reader.Reader`: typed table access helpers for config-style Lua tables


## Status

This package is intentionally small. It extracts the generic Lua runtime pieces
for the Howl ecosystem so other Zig projects can depend on one shared code
path instead of copying the same helpers.

Current published version line:

- package version: `0.1.0-beta.1`
- release tag: `v0.1.0-beta.1`

## Requirements

- Zig `0.15.2`
- Lua 5.4 development headers and library available through `pkg-config`

## Usage

For local sibling development:

```zig
.howl_lua = .{
    .path = "../howl-lua",
},
```

For pinned release-tag consumption:

```bash
zig fetch --save git+https://github.com/LaurenceGuws/howl-lua#v0.1.0-beta.1
```

Then wire the dependency into your build graph:

Add the package as a dependency, then import it from your build graph:

```zig
const lua_pkg = b.dependency("howl_lua", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("howl_lua", lua_pkg.module("howl_lua"));
exe.linkLibC();
exe.root_module.linkSystemLibrary("lua5.4", .{ .use_pkg_config = .force });
```

Then in Zig:

```zig
const howl_lua = @import("howl_lua");
const api = howl_lua.api;
const reader = howl_lua.reader;
```

Release notes:

- [v0.1.0-beta.1](docs/releases/v0.1.0-beta.1.md)
