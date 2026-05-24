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

## Audit Result

Current judgment:

- the flattened root export shape is acceptable as the package surface base
- the current internal contract shape is not acceptable to harden directly
- the first pass must be a small redesign and contract lockdown pass, not general tightening

Highest-risk gaps found in the first derive/critique round:

1. `src/api.zig`
   - `getField()` passes plain `[]const u8` to `lua_getfield()` as `const char *`
   - current field-name contract is unsafe because NUL-termination is implicit
2. `src/api.zig`
   - `fromRaw()` plus `deinit()` creates false ownership semantics
   - a wrapper around external `lua_State*` can be mistaken for an owning state
3. `src/reader.zig` and `src/api.zig`
   - `Reader.child()`, `Reader.arrayItem()`, and `TableIter` hide stack-scoped cleanup responsibilities behind copyable value types
4. `src/api.zig` and `src/reader.zig`
   - borrowed string lifetime is not named clearly enough for `readString()`, `fieldString()`, `keyString()`, and `valueString()`
5. `src/api.zig`
   - `loadFile()` failure behavior and stack/error-object handling are not explicit enough
6. `README.md`
   - docs drift from the flattened root exports and do not state the real ownership/stack rules

## Checkpoint Queue

### Checkpoint 1: Public Contract Lockdown

Why first:

- hardening the current shape directly would preserve unsafe or ambiguous contracts
- this module is small enough that the right first move is to sharpen the surface before adding more proofs

Files in scope:

- `src/root.zig`
- `src/api.zig`
- `src/reader.zig`
- `README.md`
- `docs/releases/v0.1.0-beta.1.md`
- `build.zig` only if proof wiring needs it

In scope:

- make `State` ownership explicit
- make the `lua_getfield` input contract explicit and safe
- define stack effects for field reads, child readers, array readers, and table iteration
- define borrowed string lifetime rules explicitly
- make docs match the real exported package surface

Out of scope:

- new helpers or new parsing features
- trace policy redesign
- broad packaging/release redesign
- convenience growth

Proof target:

- every exported helper has explicit ownership, stack, and lifetime rules or is removed/reshaped until it does
- docs match the actual exported surface and supported usage shape

Minimum proof expectations:

1. a proof for the supported flattened import surface
2. a proof for safe field-name handling at the `lua_getfield` seam
3. an owning-state lifecycle proof
4. stack-balance proofs for field reads and iterator/child-reader cleanup paths
5. docs updated in the same checkpoint

Stop condition:

- if the smallest correct fix for ownership or field-name safety depends on guessing about external consumers, stop and mark `work-not-clear`
- if the best fix needs a larger redesign than this small module can justify, stop and restate the smaller truthful surface

Current base-shape judgment:

- keep the flattened root export shape
- do not keep the current `State.fromRaw` / `deinit` ownership story unchanged
- do not keep unconstrained `[]const u8` as an implicit C-string field-name API

Chosen checkpoint-1 redesign:

1. `State` is owning-only.
   - keep `init()` and `deinit()`
   - remove public `fromRaw()` in this checkpoint
   - if foreign-state wrapping is ever truly needed later, add a separate borrowed type rather than a hidden ownership flag

2. Field lookup stays Zig-facing.
   - keep public field-name inputs as `[]const u8`
   - do not leak sentinel/C-string policy into the public module surface
   - implement lookup through a safe length-aware path instead of passing unconstrained bytes to `lua_getfield()`

3. `Reader` becomes a stable table view only.
   - remove public `finish()` from `Reader`
   - remove public `child()` and `arrayItem()` from `Reader` in checkpoint 1
   - remove public `iter()` from `Reader`
   - child-table traversal becomes explicit stack work on `State`, then `Reader.init(..., -1)` wraps the live table view

4. Borrowed string returns become explicit and narrow.
   - keep `State.readString()` as borrowed, with precise lifetime wording
   - keep `TableIter.keyString()` / `valueString()` as borrowed while the iterator's current pair is live
   - do not keep `Reader.fieldString()` because its current shape returns borrowed data after popping the source value

5. `TableIter` remains the explicit stack-scoped helper.
   - it keeps `finish()`
   - its cleanup and borrowed-string rules must be documented and tested precisely

Why this is the best small shape:

- smaller than adding mixed owned/borrowed state into one type
- safer than pushing sentinel-terminated field names into the entire public surface
- clearer than allowing one `Reader` type to sometimes own stack cleanup and sometimes not
- more truthful than trying to document `Reader.fieldString()` into safety

Checkpoint-1 code target after this decision:

- `State`: explicit owner lifecycle only
- safe field push helper with clear stack effect
- `Reader`: owned-copy and typed immediate field access only
- `TableIter`: the only remaining explicit stack-scoped public helper

### Checkpoint 2: General Hardening

Starts only after checkpoint 1 is proven and accepted.

Chosen narrower scope after checkpoint 1:

- `checkpoint-02-loadfile-and-numeric-contract-hardening`
- tighten `loadFile()` failure contract
- harden integer/number conversion behavior
- strengthen tests around invalid inputs and repeated failure
- remove `Reader.scalarStringOwned()` instead of hardening it

Out of scope for checkpoint 2:

- further public helper pruning
- trace policy changes
- ownership redesign
- package/release restructuring

### Checkpoint 3: Owned String Contract Hardening

- harden `Reader.stringOwned()` and `Reader.optionalStringOwned()`
- keep current effective semantic choice:
  - actual string updates target
  - missing / `nil` / non-string leaves target unchanged
- make both helpers failure-atomic
- add proof for unchanged behavior and stack neutrality

Out of scope for checkpoint 3:

- helper removal beyond checkpoint 2's `scalarStringOwned()` removal
- host consumer updates
- `State` / `TableIter` redesign

### Checkpoint 4: Explicit Nested And Array Traversal

- add `Reader.childTable()` returning an explicit stack-scoped child-table handle
- add `Reader.stringAtOwned()` for ordered 1-based string-array access
- migrate host config consumers off removed helpers and raw `reader.state` / `reader.index` reach-through
- preserve the checkpoint-1 rule that `Reader` itself remains a stable table view only

### Checkpoint 5: Table View And Iterator Contract Tightening

- assert the table-only precondition for `Reader.init()` and `State.tableIter()`
- assert array helper table-only preconditions
- prove `TableIter.finish()` idempotence and exhaustion safety
- prove non-string iterator key/value access returns `null` without stack damage
- document the remaining borrow window and stack-scope rules clearly
