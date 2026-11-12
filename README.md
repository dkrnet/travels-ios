# Travels iOS

Travels iOS is a modern rebuild of the legacy Travels iOS app. It preserves the original product model while emphasizing privacy-first location tracking: local storage, map/list browsing, GPX import/export, legacy SQLite migration, search, notes, demo history, optional reverse geocoding, photo attachments, and privacy-aware settings.

The application is designed around a reusable Swift package core and a SwiftUI iOS app shell. The core package owns model, SQLite, GPX, search, migration, filtering, trip-detection, solar-period, and color logic so those behaviors can be tested independently from iOS UI, Core Location, Photos, LocalAuthentication, and MapKit.

## Intended use

Travels is intended for personal, privacy-first location history on iOS. It records locations locally, displays them by day, allows browsing as a map or list, supports manual location capture, imports GPX tracks and geotagged photos, and exports GPX logs.

Travels exports GPX 1.1 with a documented Travels extension namespace for app-specific metadata. The schema is documented in `docs/gpx-extension-v1.md`.

The app is not intended to be a public tracking service, fleet-management platform, social network, remote monitoring tool, or cloud-first location service.

## Main features

- Local-first SQLite-backed location history
- SwiftUI iOS app with map and list browsing
- Always-visible lower-right map scale marker
- Date navigation with previous-day context for continuity, including otherwise empty selected days and full-day map framing
- Automatic and manual location capture, including a Precise Location Mode setting with Automatic hybrid tracking, Always On high precision, and Always Off lower-power monitoring
- A silent, background-capable `Add` Shortcuts action with `Forced`, `Stopped`, and `Non-Duplicate` parameters, plus actions that persistently turn Automatic Location Tracking on or off. A stopped non-duplicate capture can mark the nearby previous event stopped when it is less than five minutes old instead of inserting a duplicate; stopped captures preserve measured speed, and trigger availability and background execution remain subject to iOS
- Developer builds include a silent parameterized `Log CarPlay Event` Shortcuts action that records Connect/Disconnect automation events, timestamps, current tracking state, and the latest tracking-state transition in the maintenance log without changing tracking behavior; TestFlight and App Store builds omit this temporary diagnostic action
- A full-width date/count banner on the map and list screens with a trailing `Precise Location` indicator while high-precision tracking is running
- Background-location option with adaptive Location Detail presets for High Detail, Balanced, Battery Saver, and Road Trip point density
- Automatic Precise Location Mode makes its first active callback immediately available with temporarily unfiltered continuous delivery, uses a bounded background handoff that retains significant-change monitoring until a later callback confirms active delivery, retains background activity only for the active precise interval when Background Location is enabled, can enter active mode from fresh materially distant idle samples even when Core Location speed is unavailable, keeps precise tracking alive through the first hybrid watchdog recheck or a short minimum active interval, periodically rechecks Core Location with a bounded unfiltered continuous callback when movement quiets down, and recovers from prolonged active-stream silence with one stream restart whose stationary recovery sample confirms the existing stop episode before bounded final precise exit; normal active delivery filtering resumes after each requested callback or timeout, the background activity session ends immediately on return to low-power idle monitoring, and a short post-exit guard prevents queued or ambiguous samples from bouncing the app straight back into precise mode unless movement is clearly resumed. Always On keeps precise tracking active while automatic tracking is enabled, Always Off avoids automatic precise escalation while preserving manual current-location capture, and battery/low-power changes re-evaluate the active configuration without overriding the selected mode
- Adaptive automatic tracking distance grows conservatively during sustained highway speed, shrinks faster after sustained town-speed slowdowns, requests a bounded automatic transition sample near highway exits or town entries, keeps stop detection independent of highway-sized event-save filtering, and keeps active Core Location delivery more frequent than event persistence when preserving route continuity
- LocalAuthentication privacy lock option
- Reverse-geocoded place metadata with queueing and diagnostics
- Developer diagnostics mirrored to a local maintenance log file in app-controlled storage
- Per-event movement and trip-endpoint overrides for refining stopped-location treatment and automatic trip detection without changing recorded speed
- GPX import and export with GPX 1.1 standard fields, a documented Travels extension namespace, and legacy import compatibility
- Legacy `travels.sqlite` migration with backup and duplicate skipping
- Photo import from geotagged photo metadata with local attachment storage
- Responsive search by text, dates, notes, source, and hierarchical place filters
- Demo data that can be shown or hidden
- Time-of-day coloring based on solar periods, civil twilight, day, and night
- Trip/stopped-location map filtering
- Stopped map markers remain visible when dense nearby moving samples are thinned
- GPX export for the full selected day or the active export scope, such as a selected trip, filtered result set, or search result
- Database backup, restore, health check, and repair behavior
- Unit-testable `TravelsCore` package

## Repository layout

```text
Package.swift
Sources/
  TravelsCore/          Platform-neutral model, SQLite store, GPX, migration, search, settings, filtering, trips, solar/color logic
  TravelsCLI/           Command-line utility for exercising import/export outside the iOS app
iOSApp/
  TravelsApp/           SwiftUI app, MapKit, Core Location, Photos, LocalAuthentication, reverse geocoding, settings, diagnostics
Tests/
  TravelsCoreTests/     XCTest coverage for core behavior
Fixtures/               Sample GPX and fixture data
Travels.xcodeproj/      Xcode iOS app project
```

## Platform and tooling

- Swift tools version: 6.0
- Package platforms: iOS 17 or later; macOS 14 or later for core/package testing
- App UI framework: SwiftUI
- iOS integrations: Core Location, MapKit, Photos, LocalAuthentication, UniformTypeIdentifiers
- Persistence: SQLite through the package's `CSQLite` system library target

## Build and test

The restored shipping identity is `com.adigitalanalog.travels`, matching the
original App Store app. The development team is read from the gitignored
`Config/Signing.local.xcconfig`; copy or create that file locally with a
`DEVELOPMENT_TEAM = ...` assignment before signed device or archive builds.

Builds use a numeric `CFBundleVersion` suitable for App Store Connect and a
separate human-readable version containing development count and Git SHA for
the About screen. The numeric sequence starts above the legacy build `310`.
Set `TRAVELS_BUNDLE_BUILD_NUMBER` to an unused positive integer when an archive
must use a build number higher than the local automatic state.

Run the core package tests:

```bash
swift test
```

Or use the repository wrapper:

```bash
scripts/run_regression_tests.sh
```

The wrapper is quiet by default: it writes full output to `.build/test-logs/`, prints a compact pass summary, and summarizes failing tests without passed-test chatter. Pass `--failure-detail` for assertion-by-assertion failure lines or `--verbose` to show the normal XCTest output.

Open the repository in Xcode and use the `Travels` scheme for Simulator/device development, or build from the command line when Xcode is available:

```bash
xcodebuild -project Travels.xcodeproj -scheme Travels -destination 'platform=iOS Simulator,name=iPhone 15' build
```

Build for a connected physical iPhone:

```bash
scripts/build_device.sh
```

Build and install over the existing phone app without uninstalling or deleting the app data container:

```bash
scripts/install_device.sh --build
```

If more than one paired phone is available, pass the device identifier from `xcrun devicectl list devices`:

```bash
scripts/install_device.sh --build --device DEVICE_ID
```

Back up the complete Travels application-support directory from the only
available paired phone, including the database, SQLite sidecar files, photo
attachments, and maintenance log:

```bash
scripts/backup_device_data.sh
```

The helper validates the copied database, records table counts and a SHA-256
checksum in `backup-manifest.txt`, and stores the timestamped backup under
`../device-backups` by default. Pass `--device DEVICE_ID` when more than one
phone is available. To clear the phone's maintenance log only after a valid
backup has been created, explicitly opt in:

```bash
scripts/backup_device_data.sh --truncate-log
```

The script never truncates the maintenance log if the app-support copy,
database integrity check, or regular-file preflight for the exact on-device
`Maintenance.log` path fails.

### External TestFlight preparation

Travels includes an App Store Connect export configuration, a bundled privacy
manifest, and a release archive validator. Choose a numeric build number that
has not previously been uploaded, then create a Release archive with:

```bash
scripts/archive_testflight.sh --build-number BUILD_NUMBER
```

The archive script automatically uses a valid full Xcode installation when the
system-wide `xcode-select` setting points at Command Line Tools.

Add `--export` to also create an App Store Connect IPA for Transporter. The
script validates the shipping bundle identifier, marketing version, build
number, encryption declaration, privacy manifest, and that every App Store
icon is opaque. It intentionally does not upload anything. Follow
`docs/testflight-release-checklist.md` for the manual App Store Connect
metadata, TestFlight App Review, external group, and real-device validation
steps.

The public privacy policy is maintained in `PRIVACY.md`. App Store Connect's
privacy answers and policy URL must be reviewed whenever Travels' data handling
or third-party dependencies change.

Real-device validation is required before release for background location, Always Location permission flow, photo metadata import, LocalAuthentication, and adaptive Location Detail behavior.

## Data storage

The modern app stores its primary database in the app's Application Support directory under the `Travels` subdirectory as `Travels.sqlite`. Photo attachments are stored in a `Photos` subdirectory under the same app support directory. Developer maintenance diagnostics are mirrored to `Maintenance.log` under the same app support directory.

For offline recovery work, `scripts/recover_location_events.py` can audit the
full location-event recovery records in an exported `Maintenance.log` against
a copied `Travels.sqlite` database. It performs a dry run unless `--apply` is
provided, creates a timestamped database backup before applying changes, and
writes a JSON action report. For example:

```bash
python3 scripts/recover_location_events.py \
  --database /path/to/Travels.sqlite \
  --log /path/to/Maintenance.log \
  --date 20261010 \
  --time-zone America/Los_Angeles \
  --apply
```

The required `--date` argument uses `YYYYMMDD` and limits recovery to that
logged local calendar day. Use `--print-events` instead of `--apply` to print
the selected records and their accepted/rejected decisions without changing
the database. `--apply` and `--print-events` cannot be used together.

This maintenance tool operates only on the supplied files. It does not connect
to a phone or replace the on-device database.

On first launch, the app checks for a legacy `Documents/travels.sqlite` database. If present and not already imported, it copies a pre-modernization backup and imports legacy geolocations, events, and settings into the modern store.

## Privacy model

Your location history. On your device.

Travels is a privacy-first location history app. It is local-first and does not require an account or include advertising, analytics, cloud tracking, or tracking SDKs. The database, notes, imported photo references, and photo attachments stay in app-controlled local storage unless the user explicitly exports or shares them.

The full public policy is in [`PRIVACY.md`](PRIVACY.md).

Address lookup is optional and sends coordinates to Apple only when enabled. Before queueing an Apple lookup, Travels conservatively reuses meaningful local place data that already covers the event coordinate. Address resolution is off by default and must be enabled by the user. Photo import can create an event from a photo's date and location metadata either with or without copying the photo into Travels storage. GPX exports and database backups can contain precise location history and should be handled as sensitive files.

### Why Travels is free

Travels was created because its developer wanted a privacy-first way to keep a personal location history. It is free because it serves a niche audience, and charging for it would add more complexity than value. Users are not the product: Travels has no advertising, analytics, accounts, subscriptions, or business model based on selling location data.

The optional authentication lock uses device-owner authentication to hide map/list content while locked. It is a convenience privacy layer on top of normal iOS device security.

## Documentation and requirements

`requirements.md` is the authoritative application, development-process, build-process, and regression-test requirements document. `AGENTS.md` defines AI/LLM editing guardrails and must be read before non-trivial AI-assisted changes.

Keep the documentation and tests synchronized with implementation behavior. A future developer should be able to regenerate the application from scratch with the same look, feel, functionality, data model, privacy posture, and development safeguards by following the requirements.

## License

Travels iOS is licensed under the Mozilla Public License 2.0. See `LICENSE`.

Project-owned source files include the standard MPL-2.0 source notice. Third-party dependencies and imported legacy visual assets must retain their own notices and acknowledgements.
