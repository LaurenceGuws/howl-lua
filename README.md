# Howl Lua

Small reusable Zig helpers for embedding Lua 5.4 through the C API.

Current surface:

- `State`: owning Lua state lifecycle and stack helpers
- `TableIter`: explicit stack-scoped table iteration
- `Reader`: typed table reads for config-style Lua tables


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

const State = howl_lua.State;
const TableIter = howl_lua.TableIter;
const Reader = howl_lua.Reader;
```

## Contract Notes

- `State` is owning-only in the current package surface.
- `State.loadFile()` is stack-neutral on failure and leaves returned Lua values on the stack on success.
- `State.readString()` returns borrowed Lua-managed bytes; copy them if they must outlive the current Lua value usage window.
- `TableIter` is stack-scoped. Use `defer it.finish()` when iterating.
- `Reader` is a stable view over a table already live on the Lua stack. Its immediate field helpers restore stack depth before returning.
- `Reader.childTable()` returns an explicit stack-scoped child-table handle; use `defer child.finish()` and read through `child.view()` while that scope is live.
- `Reader.stringAtOwned()` is the supported ordered string-array accessor for 1-based Lua array tables.
- `Reader.stringOwned()` and `Reader.optionalStringOwned()` only update their targets when the field is an actual Lua string.
- missing, `nil`, and non-string fields leave owned-string targets unchanged.
- owned-string helpers are failure-atomic: allocation failure preserves the caller's prior value.
- `Reader.intField()` accepts only actual Lua integers.
- `Reader.numberField()` accepts only actual Lua numbers and does not treat numeric strings as numbers.

Release notes:

- [v0.1.0-beta.1](docs/releases/v0.1.0-beta.1.md)
