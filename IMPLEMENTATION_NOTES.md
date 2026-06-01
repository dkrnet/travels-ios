# Implementation Notes

This first pass is intentionally split into a reusable core package and an iOS SwiftUI app shell.

## Licensing

- Project-owned source is licensed under MPL-2.0.
- Each project-owned source file should carry the MPL-2.0 source notice.
- Any reused legacy artwork, glyphs, logos, or third-party code must be reviewed before public release and should include appropriate notices.
- If the app is distributed through the App Store, the MPL-covered source must remain available to recipients as required by the license.

## Core Decisions

- SQLite remains the storage engine for predictable migration from the legacy app.
- The modern schema uses explicit indexes for timestamp, localized date, source, and place hierarchy queries.
- Legacy import reads the old `travels.sqlite` directly and writes into the modern store.
- GPX export preserves the legacy Travels child elements where modern data exists.
- Areas of interest are normalized by trimming, de-duplicating, and sorting.
- Location filtering is isolated from Core Location so it can be unit tested.

## iOS App Decisions

- The app assumes an in-place upgrade bundle identifier of `com.adigitalanalog.Travels`, pending verification.
- On first launch, the app looks for `Documents/travels.sqlite`, backs it up, and imports it before normal browsing.
- The UI is SwiftUI-first with MapKit integration.
- Privacy lock uses LocalAuthentication and hides map/list content until unlocked.
- Settings include separate powered and battery update distances, matching the old develop-branch TODO.

## Still Needed

- Create an Xcode iOS app target and set the bundle identifier.
- Add a real Core Location service and background mode entitlements.
- Add reverse-geocoding queue/service implementation.
- Add photo picker import and photo preview permissions.
- Add GPX export UI.
- Add richer search filters for place hierarchy pickers.
- Add App Store privacy strings and final permission copy.
- Run on a real device to validate background location behavior.
