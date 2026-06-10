# Requirements

## Versioning

Travels uses semantic marketing versions for the App Store-facing version number and automatic development build metadata for the bundle version.

- Marketing version: `2.0.0`
- Development build version format for untagged commits: `2.0.0-dev.<build-count>+<git-short-sha>`
- Tagged commit build version format: `2.0.0.<build-count>+<git-short-sha>` where `build-count` resets to `0`
- The build count increments for each app build and is stored locally in a gitignored state file so the version updates automatically at build time.
- The About screen should display the build version directly, for example: `Version 2.0.0-dev.0+8508546`
- Future development builds should keep the same pattern so the visible version matches the build metadata scheme.
