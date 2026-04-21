# Releasing howl-lua

`howl-lua` is a source package release, not a binary artifact release.

## Versioning

- Canonical package version lives in [`build.zig.zon`](build.zig.zon).
- Product version uses semver, with prereleases for early milestones:
  - package version: `0.1.0-beta.1`
  - git/GitHub tag: `v0.1.0-beta.1`
- Do not mix ad hoc tag formats into this repo.

## Release Sequence

1. Bump the canonical package version in `build.zig.zon`.
2. Add or update matching notes under `docs/releases/`.
3. Update `README.md` if package consumption guidance changed.
4. Validate locally with `zig build test`.
5. Commit the release prep snapshot.
6. Tag that commit as `v<version>`.
7. Publish a GitHub prerelease or release from that tag.

## Publish

Create a GitHub release from the tag with release notes from the corresponding version file under `docs/releases/`.
