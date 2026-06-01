# travels-ios

travels-ios is a first-pass modern rebuild of the legacy Travels iOS app. It keeps the old app's product model: local-first life tracking, map/list browsing, GPX import/export, legacy SQLite migration, search, notes, and privacy-aware settings.

This folder contains:

- `Sources/TravelsCore`: platform-neutral model, SQLite store, GPX import/export, search, and migration logic.
- `Sources/TravelsCLI`: a small command-line utility for exercising import/export outside the iOS app.
- `iOSApp/TravelsApp`: SwiftUI app source files intended for an Xcode iOS app target.
- `Tests/TravelsCoreTests`: unit tests for core behavior.
- `Fixtures`: sample data for tests and manual checks.

The intended bundle identifier for an in-place upgrade build is currently assumed to be `com.adigitalanalog.Travels` until the original app identity is verified.

## License

travels-ios is licensed under the Mozilla Public License 2.0. See [LICENSE](LICENSE).

Project-owned source files include the standard MPL-2.0 source notice. Third-party dependencies and any imported legacy visual assets should retain their own notices and acknowledgements.

## Build Notes

The local Codex environment used to create this first pass did not have full Xcode selected, so an installable iOS app bundle could not be built here. Open this folder in Xcode or create an iOS app target that includes `iOSApp/TravelsApp` and depends on the `TravelsCore` package.

The core package is designed so the persistence, GPX, search, and legacy migration logic can be tested independently of iOS UI and Core Location.
