# Production Grade Scratchpad

Owner: `howl-lua`

Purpose:

- Track the local hardening plan for `howl-lua` without mixing it into main Howl product-planning docs.

Product shape:

- `howl-lua` is a small reusable Zig module for embedding Lua 5.4 through the C API.
- It is not a C ABI product like `howl-vt` or `howl-render`.
- It still must be production-grade code.

Production-grade bar for this repo:

- public API is small, explicit, and documented
- ownership and lifetime rules are named clearly
- stack effects are correct and testable
- invalid inputs and error paths are handled deliberately
- FFI assumptions are explicit rather than accidental
- tests cover both happy paths and failure/edge behavior
- docs match the real exported surface
- convenience does not outrun correctness

Current local surface:

- `src/root.zig`
  - curated public exports
- `src/api.zig`
  - Lua state lifecycle and stack helpers
  - table iteration
- `src/reader.zig`
  - typed table/config reads
- `src/trace.zig`
  - optional debug tracing
- `build.zig`
  - module and test wiring

Initial high-level read:

- repo is small enough for a full focused hardening pass
- current surface is narrow, which is good
- some contracts are implicit rather than stated
- tests exist but are still too light for a C-API wrapper
- docs likely drifted from the flattened root exports
- recent local `src/api.zig` dirt should be reviewed intentionally, not assumed correct

Likely audit buckets:

1. public API surface audit
2. FFI and link seam audit
3. `State` lifecycle and ownership audit
4. stack discipline audit
5. `TableIter` correctness audit
6. `Reader` ownership/lifetime audit
7. invalid-input and edge-case audit
8. tracing policy audit
9. test gap audit
10. build/test portability audit
11. README/doc correctness audit
12. release/versioning hygiene audit

Working rule:

- prefer tightening and proving the existing module over adding new surface area
- if an API is ambiguous, sharpen the contract before expanding it
- if a helper hides too much stack or ownership truth, stop and make it explicit

Near-term output wanted from the next pass:

- a ranked list of the highest-risk production gaps
- a narrow checkpoint queue for fixing them
- a judgment on whether the current API needs only hardening or small redesign
