# Contributing

Thank you for considering a contribution to Travels iOS.

Before making a non-trivial change, read `requirements.md`, `README.md`, and `AGENTS.md`. Travels is a local-first iOS location-history application with a reusable Swift package core, a SwiftUI app shell, SQLite persistence, GPX import/export, legacy database migration, photo import, reverse geocoding, and privacy-aware settings.

---

## Platform, Signing & Versioning

* **Swift tools version:** 6.0
* **Supported platforms:** iOS 17.0+ (App); macOS 14.0+ (Core package testing)
* **UI & Frameworks:** SwiftUI, Core Location, MapKit, Photos, LocalAuthentication, UniformTypeIdentifiers
* **Persistence:** SQLite via the package's `CSQLite` system library target
* **Bundle Identifier:** `com.adigitalanalog.travels`

### Code Signing
Signed device and archive builds read your team ID from the gitignored `Config/Signing.local.xcconfig` file. Copy or create this file locally before building for a physical device:
```text
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

### Build Numbers
Builds use a numeric `CFBundleVersion` (starting above 310) for App Store Connect alongside a human-readable build string (commit count + Git SHA) displayed in the About screen. Set `TRAVELS_BUNDLE_BUILD_NUMBER` to an unused positive integer when an archive requires a higher build number than local automatic state.

---

## Development Workflow

1. Make focused changes that preserve the documented requirements.
2. Work on a development branch, not directly on `main`.
3. Preserve existing regression guard comments unless a requirement is intentionally changed.
4. Keep platform-neutral business logic in `Sources/TravelsCore` whenever practical so it can be unit tested without the iOS UI.
5. Keep iOS-specific code, permissions, SwiftUI views, MapKit integration, Photos integration, LocalAuthentication, and Core Location integration in `iOSApp/TravelsApp`.
6. Update `requirements.md`, `README.md`, `CONTRIBUTING.md`, `PRIVACY.md`, and relevant tests when behavior, deployment, configuration, data model, privacy behavior, build assumptions, or test expectations change.
7. Keep requirements focused on observable behavior and required compatibility outcomes; do not constrain implementation choices unless the constraint is needed for minimal functionality, safety, privacy, compatibility, migration, build reproducibility, or preserving the intended look and feel.
8. Do not add network services, analytics, cloud sync, external accounts, server-side storage, advertising, or remote logging unless the requirements are intentionally changed first.
9. Use normal pull requests or unified diffs. Avoid broad rewrites when a minimal, well-tested change is sufficient.

---

## Building, Testing & Deployment

### Unit & Regression Tests
Run the package tests before submitting ordinary source changes:
```bash
swift test
```

The repository also provides a wrapper with optional focused filters:
```bash
scripts/run_regression_tests.sh
scripts/run_regression_tests.sh --filter LocationTrackingStateMachineTests
```
The wrapper suppresses passed-test chatter by default, summarizes failing tests, and stores the full output in `.build/test-logs/`. Use `--failure-detail` for assertion-by-assertion failure lines or `--verbose` when you need the raw XCTest stream.

### iOS Simulator Builds
Open `Travels.xcodeproj` in Xcode using the **Travels** scheme, or build from the command line:
```bash
# Direct xcodebuild check
xcodebuild -project Travels.xcodeproj -scheme Travels -destination 'platform=iOS Simulator,name=iPhone 15' build

# Build for default simulator (iPhone 17 Pro) and validate build metadata
scripts/build_simulator.sh

# Target a specific simulator by name or UDID
scripts/build_simulator.sh --name "iPhone 15"
scripts/build_simulator.sh --device SIMULATOR_UDID

# Clean install (wipes existing simulator app data) and launch
scripts/install_simulator.sh --build --fresh --launch
```
*(Omit `--fresh` to preserve the simulator's existing Travels data.)*

### Physical iOS Device Builds
*Note: `install_device.sh` intentionally accepts only physical iOS device identifiers, not simulator UDIDs.*
```bash
# Build for a connected physical iPhone and validate embedded version metadata
scripts/build_device.sh

# Build and install over an existing installation without wiping app data
scripts/install_device.sh --build

# Specify a device when multiple phones are paired (via `xcrun devicectl list devices`)
scripts/install_device.sh --build --device DEVICE_ID
```

When UI or platform integration behavior changes, run the applicable Simulator or device checks in Xcode. Real-device validation is required for background location behavior, Always Location permission flow, Photos metadata import, LocalAuthentication, adaptive Location Detail behavior, and App Store privacy copy.

---

## Patch Quality

* Keep changes small enough to review.
* Prefer explicit requirements over implicit behavior.
* Add or update tests for every bug fix and every new requirement that can be tested in `TravelsCore`.
* Do not change the app's database schema without a migration path and regression tests.
* Do not change GPX import/export compatibility without tests that cover the old and new behavior.
* Do not change legacy migration behavior without tests that protect existing imported data.
* Do not change privacy-sensitive behavior without updating `PRIVACY.md`, `SECURITY.md`, `README.md`, and `requirements.md`.

---

## Data Backups, Recovery & Release Operations

### Backing Up Device Data
Back up the complete `Application Support/Travels` directory (SQLite database, sidecar files, photo attachments, and `Maintenance.log`) from a connected phone:
```bash
scripts/backup_device_data.sh [--device DEVICE_ID]
```
* Stores timestamped backups under `../device-backups` with table counts and a SHA-256 checksum in `backup-manifest.txt`.
* Pass `--truncate-log` to clear the on-device `Maintenance.log` *only* after backup and database integrity checks succeed.

### Offline Event Recovery
Audit or recover location events from an exported `Maintenance.log` into a copied `Travels.sqlite` database:
```bash
python3 scripts/recover_location_events.py \
  --database /path/to/Travels.sqlite \
  --log /path/to/Maintenance.log \
  --date 20261010 \
  --time-zone America/Los_Angeles \
  --apply
```
* Operates strictly on local file copies; does not connect to a phone or modify an on-device database.
* Runs in dry-run mode unless `--apply` is provided (creates a timestamped backup before applying changes and outputs a JSON action report).
* Use `--print-events` (mutually exclusive with `--apply`) to inspect accepted/rejected records without altering files.

### External TestFlight Preparation
1. Choose an unused numeric build number and create a Release archive:
   ```bash
   scripts/archive_testflight.sh --build-number BUILD_NUMBER
   ```
   *(Automatically selects a valid full Xcode installation if `xcode-select` points to Command Line Tools. Add `--export` to generate an App Store Connect IPA for Transporter. The script validates the shipping bundle identifier, marketing version, build number, encryption declaration, privacy manifest, and opaque app icons, but intentionally does not upload anything.)*
2. Follow `docs/testflight-release-checklist.md` for manual App Store Connect metadata, TestFlight App Review, external group setup, and real-device validation steps.
3. Review `PRIVACY.md` and App Store Connect privacy answers whenever data handling or dependencies change.

---

## License Notices

Project-owned source files must retain the Mozilla Public License 2.0 source notice. Third-party code, legacy artwork, imported assets, icons, or other external materials must retain their own notices and must be reviewed before public release.
