# Travels iOS

Travels iOS is a modern rebuild of the legacy Travels iOS app. It preserves the original product model: local-first life tracking, map/list browsing, GPX import/export, legacy SQLite migration, search, notes, demo history, reverse geocoding, photo attachments, and privacy-aware settings.

The application is designed around a reusable Swift package core and a SwiftUI iOS app shell. The core package owns model, SQLite, GPX, search, migration, filtering, trip-detection, solar-period, and color logic so those behaviors can be tested independently from iOS UI, Core Location, Photos, LocalAuthentication, and MapKit.

## Intended use

Travels is intended for personal location journaling and lightweight life tracking on iOS. It records locations locally, displays them by day, allows browsing as a map or list, supports manual location capture, imports GPX tracks and geotagged photos, and exports GPX logs.

Travels exports GPX 1.1 with a documented Travels extension namespace for app-specific metadata. The schema is documented in `docs/gpx-extension-v1.md`.

The app is not intended to be a public tracking service, fleet-management platform, social network, remote monitoring tool, or cloud-first location service.

## Main features

- Local-first SQLite-backed location history
- SwiftUI iOS app with map and list browsing
- Date navigation with previous-day context for continuity
- Automatic and manual location capture, including hybrid significant-change tracking with an optional always-on high precision mode
- A live `Precise Location Active` badge on the map and list screens while high-precision tracking is running
- Background-location option with separate powered and battery distance thresholds
- Hybrid tracking periodically rechecks Core Location when movement quiets down, and battery/low-power changes re-evaluate the active configuration without changing the Always-On policy
- LocalAuthentication privacy lock option
- Reverse-geocoded place metadata with queueing and diagnostics
- Per-event trip endpoint overrides for refining automatic trip detection
- GPX import and export with GPX 1.1 standard fields, a documented Travels extension namespace, and legacy import compatibility
- Legacy `travels.sqlite` migration with backup and duplicate skipping
- Photo import from geotagged photo metadata with local attachment storage
- Search by text, dates, notes, source, and place hierarchy
- Demo data that can be shown or hidden
- Time-of-day coloring based on solar periods, civil twilight, day, and night
- Trip/stopped-location map filtering
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

Run the core package tests:

```bash
swift test
```

Open the repository in Xcode and use the `Travels` scheme for Simulator/device development, or build from the command line when Xcode is available:

```bash
xcodebuild -project Travels.xcodeproj -scheme Travels -destination 'platform=iOS Simulator,name=iPhone 15' build
```

Real-device validation is required before release for background location, Always Location permission flow, photo metadata import, LocalAuthentication, and battery/powered distance behavior.

## Data storage

The modern app stores its primary database in the app's Application Support directory under the `Travels` subdirectory as `Travels.sqlite`. Photo attachments are stored in a `Photos` subdirectory under the same app support directory.

On first launch, the app checks for a legacy `Documents/travels.sqlite` database. If present and not already imported, it copies a pre-modernization backup and imports legacy geolocations, events, and settings into the modern store.

## Privacy model

Travels is local-first. The database, notes, imported photo references, and photo attachments stay in app-controlled local storage unless the user explicitly exports or shares them.

Reverse geocoding can send coordinates to Apple services when address resolution is enabled. Settings must clearly disclose this. GPX exports and database backups can contain precise location history and should be handled as sensitive files.

The optional authentication lock uses device-owner authentication to hide map/list content while locked. It is a convenience privacy layer on top of normal iOS device security.

## Documentation and requirements

`requirements.md` is the authoritative application, development-process, build-process, and regression-test requirements document. `AGENTS.md` defines AI/LLM editing guardrails and must be read before non-trivial AI-assisted changes.

Keep the documentation and tests synchronized with implementation behavior. A future developer should be able to regenerate the application from scratch with the same look, feel, functionality, data model, privacy posture, and development safeguards by following the requirements.

## License

Travels iOS is licensed under the Mozilla Public License 2.0. See `LICENSE`.

Project-owned source files include the standard MPL-2.0 source notice. Third-party dependencies and imported legacy visual assets must retain their own notices and acknowledgements.
