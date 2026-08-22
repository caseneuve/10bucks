# Releasing 10bucks

Releases are identified by date: `YYYY.MM.DD` in UTC. Alpha pre-releases
append `-alpha.N`, for example `2026.08.22-alpha.1`. If a correction needs a
second stable release on the same date, append a numeric revision, for example
`2026.08.22.2`. Git tags are the version prefixed with `v`.

## Release checklist

1. Select the next version and update `VERSION`.
2. Update `Tenbucks.version` in `10bucks.spoon/init.lua` to exactly the same
   value. The packaging script rejects a mismatch.
3. Move the completed changes from `Unreleased` into a dated section in
   `CHANGELOG.md`.
4. Run the checks and build the release archive locally:

   ```sh
   lua tests/run.lua
   ./scripts/package-spoon.sh
   ```

   The artifact is `dist/10bucks.spoon.zip`. It contains the top-level
   `10bucks.spoon/` directory required by Hammerspoon.
5. Commit and push the release preparation commit to `master`.
6. Create and push an annotated tag that exactly matches `VERSION`:

   ```sh
   git tag -a "v$(tr -d '[:space:]' < VERSION)" -m "10bucks $(tr -d '[:space:]' < VERSION)"
   git push origin "v$(tr -d '[:space:]' < VERSION)"
   ```

Pushing that tag starts the `Release Spoon` GitHub Actions workflow. It checks
that the tag and `VERSION` agree, builds and validates the archive, then creates
the GitHub Release with `10bucks.spoon.zip` attached. Tags ending in `-alpha.N`
are published as GitHub pre-releases. Do not create the GitHub Release manually.

A user can download the attached ZIP, uncompress it if necessary, and
double-click `10bucks.spoon` in Finder; Hammerspoon installs it into
`~/.hammerspoon/Spoons/`.
