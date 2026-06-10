# Contributing

Thank you for considering a contribution to Travels iOS.

Before making a non-trivial change, read `requirements.md`, `README.md`, and `AGENTS.md`. Travels is a local-first iOS life-tracking application with a reusable Swift package core, a SwiftUI app shell, SQLite persistence, GPX import/export, legacy database migration, photo import, reverse geocoding, and privacy-aware settings.

## Development workflow

1. Make focused changes that preserve the documented requirements.
2. Work on a development branch, not directly on `main`.
3. Preserve existing regression guard comments unless a requirement is intentionally changed.
4. Keep platform-neutral business logic in `Sources/TravelsCore` whenever practical so it can be unit tested without the iOS UI.
5. Keep iOS-specific code, permissions, SwiftUI views, MapKit integration, Photos integration, LocalAuthentication, and Core Location integration in `iOSApp/TravelsApp`.
6. Update `requirements.md`, `README.md`, and relevant tests when behavior, deployment, configuration, data model, privacy behavior, build assumptions, or test expectations change.
7. Keep requirements focused on observable behavior and required compatibility outcomes; do not constrain implementation choices unless the constraint is needed for minimal functionality, safety, privacy, compatibility, migration, build reproducibility, or preserving the intended look and feel.
8. Do not add network services, analytics, cloud sync, external accounts, server-side storage, advertising, or remote logging unless the requirements are intentionally changed first.
9. Use normal pull requests or unified diffs. Avoid broad rewrites when a minimal, well-tested change is sufficient.

## Build and test checks

Run the package tests before submitting ordinary source changes:

```bash
swift test
```

When Xcode and an iOS Simulator are available, also build the app target from the Xcode project:

```bash
xcodebuild -project Travels.xcodeproj -scheme Travels -destination 'platform=iOS Simulator,name=iPhone 15' build
```

When UI or platform integration behavior changes, run the applicable Simulator or device checks in Xcode. Real-device validation is required for background location behavior, permission prompts, Photos metadata import, LocalAuthentication, and App Store privacy copy.

## Patch quality

- Keep changes small enough to review.
- Prefer explicit requirements over implicit behavior.
- Add or update tests for every bug fix and every new requirement that can be tested in `TravelsCore`.
- Do not change the app's database schema without a migration path and regression tests.
- Do not change GPX import/export compatibility without tests that cover the old and new behavior.
- Do not change legacy migration behavior without tests that protect existing imported data.
- Do not change privacy-sensitive behavior without updating `SECURITY.md`, `README.md`, and `requirements.md`.

## License notices

Project-owned source files must retain the Mozilla Public License 2.0 source notice. Third-party code, legacy artwork, imported assets, icons, or other external materials must retain their own notices and must be reviewed before public release.
