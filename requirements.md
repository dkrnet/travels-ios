# Travels iOS Requirements

## Purpose

Travels iOS is a local-first iOS life-tracking application. It records, imports, displays, searches, annotates, backs up, restores, and exports location events. It is a modern Swift rebuild of the legacy Travels app and must preserve the legacy product model where applicable.

A future developer should be able to regenerate the application from scratch with the same look, feel, functionality, data model, privacy posture, and development safeguards by following this document together with `README.md` and `AGENTS.md`.

## Documentation governance

- `requirements.md` is the authoritative functional, build-process, development-process, and regression-test specification.
- `README.md` is the user/developer overview and setup guide.
- `AGENTS.md` is the authoritative AI/LLM editing guardrail document.
- `CONTRIBUTING.md` is the concise contribution workflow document.
- `SECURITY.md` is the privacy and vulnerability-reporting policy.
- Non-trivial behavior changes shall update requirements, README, and tests as applicable in the same change set.
- Requirements shall describe observable behavior, required compatibility outcomes, data-safety constraints, privacy/security obligations, build/test commands, and other constraints needed for correct minimal functionality.
- Requirements shall not prescribe implementation details, internal class names, algorithms, UI framework mechanics, or storage internals unless those details are necessary for compatibility, security, privacy, build reproducibility, migration safety, or preserving the intended look, feel, and behavior.
- When a requirement constrains implementation freedom, the constraint shall be justified by user-visible behavior, compatibility, privacy, safety, migration, or build reproducibility.
- Regression-testing requirements shall remain in this document rather than a separate regression-testing document.

## Platform and repository requirements

- The app shall be written in Swift.
- The iOS app UI shall use SwiftUI.
- The iOS app may use MapKit, Core Location, Photos, LocalAuthentication, and UniformTypeIdentifiers for platform integrations.
- The core package shall support iOS 17 or later and macOS 14 or later.
- The Swift package shall use Swift tools version 6.0 unless intentionally changed.
- Core logic that does not require iOS UI or platform-only APIs shall reside in `Sources/TravelsCore`.
- UI, permission prompts, platform services, map/list presentation, photo picker, LocalAuthentication, and Core Location service code shall reside in `iOSApp/TravelsApp`.
- Command-line import/export helper behavior shall reside in `Sources/TravelsCLI`.
- The repository shall contain `Package.swift`, `Sources/TravelsCore`, `Sources/TravelsCLI`, `iOSApp/TravelsApp`, `Tests/TravelsCoreTests`, `Fixtures`, `Travels.xcodeproj`, `README.md`, `requirements.md`, `AGENTS.md`, `CONTRIBUTING.md`, `SECURITY.md`, and `LICENSE`.
- The repository shall not contain a separate top-level `REQUIREMENTS.md`; requirements content shall be consolidated in lowercase `requirements.md`.

## Licensing requirements

- Project-owned source files must include the Mozilla Public License 2.0 source notice near the top of each file.
- The top-level `LICENSE` file must contain the MPL-2.0 license text.
- Third-party code, imported legacy visual assets, icons, glyphs, logos, screenshots, sample data, or other external materials must retain appropriate notices and must be reviewed before public release.
- If the application is distributed through the App Store, the MPL-covered source must remain available to recipients as required by the license.

## Privacy and local-first requirements

- The app shall remain local-first.
- The app shall not add analytics, advertising identifiers, cloud sync, remote logging, tracking SDKs, remote feature flags, server accounts, or third-party network services unless explicitly required in a future requirements change.
- Location history, event notes, photo filenames, imported photo metadata, GPX exports, and database backups are privacy-sensitive.
- Reverse geocoding may send location data to Apple services when address resolution is enabled.
- Settings and App Store privacy copy shall disclose address-resolution behavior.
- GPX exports and database backups shall be treated as sensitive user-controlled files.
- The authentication lock shall hide map/list content while locked but shall not be represented as a replacement for iOS device security.

## App identity and upgrade requirements

- The intended in-place upgrade bundle identifier is `com.adigitalanalog.Travels` until the original app identity is verified.
- The bundle identifier must not be changed casually because it affects upgrade, sandbox, data-container, and App Store behavior.
- Before release, verify that the bundle identifier, signing identity, app group assumptions if any, and migration path match the legacy app identity.

## Versioning requirements

- Travels shall use semantic marketing versions for the App Store-facing version number.
- Travels shall use automatic development build metadata for the bundle version.
- The initial marketing version shall be `2.0.0` unless intentionally changed.
- Untagged development build versions shall use the form `2.0.0-dev.<build-count>+<git-short-sha>`.
- Tagged commit build versions shall use the form `2.0.0.<build-count>+<git-short-sha>`, where `build-count` resets to `0`.
- The build count shall increment for each app build and may be stored locally in a gitignored state file so the version updates automatically at build time.
- The About screen shall display the build version directly, for example `Version 2.0.0-dev.0+8508546`.
- Future development builds shall keep the same pattern so the visible version matches the build metadata scheme unless this requirement is intentionally changed.

## Data storage requirements

- The modern database shall be named `Travels.sqlite`.
- The modern database shall be stored in the app's Application Support directory under a `Travels` subdirectory.
- Photo attachments shall be stored in a `Photos` subdirectory under the same Application Support `Travels` directory.
- The app shall create required Application Support directories at startup.
- Temporary GPX exports and database backups may be written to the system temporary directory for user sharing.
- User data shall not be stored in the web, cloud, or shared public locations unless the user explicitly exports or shares it.

## Database schema requirements

The modern SQLite store shall maintain at least `geolocations`, `events`, and `settings` tables.

The `geolocations` table shall preserve latitude, longitude, radius, identifier, horizontal and vertical accuracy, altitude, timestamp, bounding coordinates, time zone identifier, and place metadata including name, street, locality, administrative areas, postal code, country, inland water, ocean, and areas of interest.

The `events` table shall preserve latitude, longitude, horizontal and vertical accuracy, altitude, course, speed, timestamp, localized date, source, geolocation id, note, tags, external reference, photo filename, demo marker, solar period fields, and legacy twilight compatibility fields.

The `settings` table shall preserve key/value settings with forward-compatible loading behavior.

Required indexes shall support timestamp lookups, localized-date lookups, source filtering, solar/twilight recalculation queries, and place-hierarchy filtering.

Opening the modern store shall run schema migration. Migration shall create missing tables and indexes, add missing compatibility columns without data loss, and preserve duplicate detection using latitude, longitude, timestamp, source, and external reference.

The store shall provide health checking, integrity checking, foreign-key checking, backup, repair, and restore behavior. Repair and restore operations shall avoid silent data loss and shall preserve a backup or quarantine path when practical.

## Data model requirements

- Event sources shall include automatic location capture, manual user-added locations, GPX import, legacy import, photo import, and demo data.
- Unknown source values shall not crash the app and shall be handled forward-compatibly.
- Event timestamps shall be stored as absolute dates and shall retain enough time-zone/localized-date information to display the event in the appropriate local-day context.
- Geolocation place metadata shall be optional and may be filled by reverse geocoding or GPX/legacy import.
- Areas of interest shall be normalized so display and search behavior remain consistent.

## Settings requirements

Settings shall include automatic tracking, background tracking, address resolution, authentication lock, demo-data visibility, distance thresholds for powered/battery operation, search/filter preferences where applicable, and migration/demo seed state.

Settings shall load sensible defaults when missing and shall preserve forward compatibility when older databases lack newer setting keys.

## Launch and migration requirements

- On startup, the app shall create required directories, open the modern store, run migrations, load settings, seed demo data when appropriate, and load the current display state.
- On first launch with a legacy `Documents/travels.sqlite` database, the app shall create a pre-modernization backup before import.
- Legacy import shall preserve legacy geolocations, events, settings, timestamps, source identity, notes where available, and duplicate-skipping behavior.
- Legacy import shall mark migration completion so the same database is not repeatedly imported.
- Import failures shall be user-visible and shall not silently destroy legacy or modern data.

## Location capture requirements

- The app shall support automatic foreground location capture.
- The app shall support optional background location capture.
- The app shall support manual add-current-location capture.
- Location capture shall respect user settings, iOS authorization status, and service availability.
- Background capture requires appropriate iOS location permissions and real-device validation before release.
- Distance thresholds shall distinguish powered and battery operation.
- Stale, inaccurate, redundant, and paused location samples shall be filtered according to documented core filtering behavior.
- Improved-accuracy samples may replace earlier nearby samples when doing so preserves a better event.
- Manual current-location capture shall be force-capable where appropriate so the user can intentionally record the current position.
- The add-current-location button shall be enabled only when the selected date is today and the action is otherwise available.
- The add-current-location button shall be visibly disabled/grayed out whenever the add-current-location function is unavailable, including when the selected date is not today, location services or permissions are unavailable, tracking state prevents the action, or the action cannot be performed safely.

## Map, list, and navigation requirements

- The main view shall provide map and list browsing of events.
- The selected date shall drive the displayed day.
- Date navigation shall include current-day browsing, previous/next day movement, and date picking.
- The app shall include previous-day context when needed to preserve map/list continuity.
- The main navigation title shall be compact and date/count oriented.
- Toolbar icons shall use SF Symbols.
- Alerts shall use title `Travels` for general status messages.
- Settings shall use grouped Form sections.
- Privacy-sensitive disabled states shall disable actions rather than allowing failures where practical.
- Debug-only diagnostics shall be compiled only in `DEBUG` builds.

## Search and filtering requirements

- The app shall support text search, date filtering, note filtering, source filtering, and place-hierarchy filtering.
- Place-hierarchy filtering shall narrow available options as country, administrative area, sub-administrative area, and locality selections are made.
- Search results shall respect the include-demo-data setting.
- Search and all-events views shall avoid exposing hidden demo data when demo data is disabled.

## Reverse geocoding requirements

- Address resolution shall be user-configurable.
- When enabled, the app may use Apple reverse-geocoding services to resolve place metadata.
- Unresolved addresses may be queued for later resolution.
- Reverse-geocoding status and diagnostics shall be visible enough for troubleshooting.
- When address resolution is disabled, the app shall not initiate new reverse-geocoding work.

## GPX import/export requirements

- GPX import shall support valid GPX track points.
- Invalid GPX points shall be skipped without crashing the whole import where practical.
- GPX import shall preserve legacy Travels child metadata such as time zone, address fields, accuracy, heading/course, speed, altitude, note, and areas of interest where present.
- GPX export shall include valid XML, metadata, bounds where available, track segments, track points, and legacy Travels child elements needed for round-trip compatibility.
- GPX export shall XML-escape user-controlled and imported strings.
- Empty GPX export shall fail with a clear user-facing error.
- Import/export shall use file-security handling appropriate for iOS document picker/share-sheet workflows.

## Photo import requirements

- The app shall support importing geotagged photos as events.
- Photo import shall require photo timestamp and location metadata.
- Photo import shall fail safely with clear user-facing errors when required metadata is missing.
- Imported photo attachments shall be stored in the app-controlled `Photos` directory.
- Photo import shall avoid exposing the user's real photo library in automated tests; core behavior should be testable through seams where practical.

## Backup, restore, and repair requirements

- Database backup shall create a timestamped SQLite backup using the form `Travels-backup-yyyyMMdd-HHmmss.sqlite`.
- Backup shall checkpoint the SQLite WAL before copying.
- Restore shall support security-scoped file access.
- Restore shall stop location tracking before replacing the database.
- Restore shall reopen the store, reload settings, select an appropriate date, reload events, reconfigure location tracking, and refresh date-selection bounds.
- Repair shall quarantine or back up unhealthy databases where practical before rebuilding.

## Authentication lock requirements

- When `requireAuthentication` is enabled, the app shall lock map/list content when entering inactive or background scene phases.
- When returning active while locked, the app shall request device-owner authentication.
- The LocalAuthentication reason shall explain that authentication is required to use Travels.
- If device-owner authentication is unavailable, the app shall unlock rather than permanently blocking the user.
- Map/list content shall be visually blurred when locked.

## Demo data requirements

- Demo data shall be enabled by default.
- Demo data shall be seeded only when enabled and appropriate.
- Demo data shall be marked with `isDemo`.
- User settings shall allow hiding demo data.
- Search, all-events views, counts, date bounds, latest event, and current-day display shall respect the include-demo setting.
- Demo seed version and first-launch reference date shall be stored in settings.

## Solar period, civil twilight, and time-of-day color requirements

- The app shall classify events into solar periods: morning civil twilight, day, evening civil twilight, night before midnight, night after midnight, and unknown.
- Solar-period percent shall be a normalized value from 0.0 to 1.0 when available.
- Sunrise shall be the start of day period at 0%.
- Solar noon shall be day period at approximately 50%.
- Sunset shall be day period at 100%.
- Civil dawn shall be morning civil twilight at 0%.
- Midway between civil dawn and sunrise shall be morning civil twilight at approximately 50%.
- Civil dusk shall be evening civil twilight at 100%.
- Midway between sunset and civil dusk shall be evening civil twilight at approximately 50%.
- Night periods shall distinguish before and after midnight so gradients can wrap around midnight.
- Existing twilight compatibility APIs may remain as deprecated shims to solar-period behavior.
- Time-of-day colors shall use these base colors unless intentionally changed: midnight `#000000`, end/beginning of night `#2F3437`, morning civil twilight `#F2A15B`, beginning of day `#63C3FF`, midday `#0077CC`, end of day `#2FAF9B`, evening civil twilight `#D96F5D`, and unknown `#A3A3A3`.
- Color blending shall be gamma-aware and shall clamp input/output fractions.
- Missing twilight/solar percent shall fall back to the middle color for twilight/day/night periods where applicable.

## Trip detection requirements

- The app shall detect trips from daily events for map-display filtering.
- Displayed events shall be filtered based on All, Stopped Only, or selected trip ids.
- Trip display selection shall focus map content on selected trips.
- Selecting no trips shall fall back to All display.
- Trip detection logic should remain testable in `TravelsCore`.

## Error handling requirements

- User-facing failures shall be presented through status messages or alerts.
- Routine validation failures shall not crash the app.
- Missing photo metadata, missing database, empty export, invalid GPX, invalid timezone, and event-not-found conditions shall have clear localized descriptions.
- Database and import errors shall include enough context for troubleshooting without exposing unnecessary sensitive data.

## Build-process requirements

- The Swift package shall build with `swift build` when platform dependencies permit.
- Core tests shall run with `swift test`.
- The Xcode project shall provide a `Travels` scheme for Simulator/device app builds.
- When Xcode is available, app builds should be validated with `xcodebuild -project Travels.xcodeproj -scheme Travels -destination 'platform=iOS Simulator,name=iPhone 15' build` or an equivalent available simulator destination.
- Real-device validation is required for background location, Always Location permission behavior, LocalAuthentication, Photos metadata import, and battery/powered distance behavior.
- Build-process changes shall update this document and README.

## Repository workflow requirements

- Changes committed to the repository should be committed on a development branch.
- Ordinary source changes should not be committed directly to `main`.
- Non-trivial changes shall update tests or explicitly document why no automated test is practical.
- Documentation changes shall remain synchronized with implementation behavior.
- AI/LLM-assisted changes shall follow `AGENTS.md` and shall use the delivery mode that matches the assistant's access level.
- If an AI/LLM provides changes to a developer without direct repository access, it shall provide valid unified diffs suitable for `git apply` or `patch -p1`, unless another format is explicitly requested.
- If an AI/LLM has direct repository access, it shall prefer a branch and pull request workflow, with the branch, commits, and pull request serving as the primary review artifact unless a patch is explicitly requested.
- In all modes, AI/LLM-assisted changes shall be scoped to the requested work, shall avoid unrelated edits, shall update requirements and tests when behavior changes, and shall accurately report what validation was or was not performed.
- Pull requests should be focused and reviewable.
- Broad rewrites are discouraged unless required by an explicit requirement.

## Regression testing requirements

The regression test suite shall use XCTest for `TravelsCore` behavior. The suite shall be runnable with:

```bash
swift test
```

The test suite shall include coverage for:

- area-of-interest normalization
- location filtering decisions, including first sample, stale sample rejection, paused threshold, accuracy improvement replacement, force behavior, accuracy rejection, and distance threshold acceptance
- SQLite migration creating modern tables, indexes, and compatibility columns
- duplicate event detection and duplicate skipping
- geolocation save/load behavior
- event save/load/search behavior
- settings load/save defaults and forward compatibility for missing keys
- legacy database import, including geolocation mapping, event import order, skipped duplicates, imported settings, and migration-complete markers
- GPX import of valid track points
- GPX skip behavior for invalid points
- GPX import of legacy Travels child metadata into geolocation fields
- GPX export XML escaping
- GPX export bounds, metadata, and legacy child elements
- empty GPX export error behavior
- date tools and localized date handling with time zones
- photo import core behavior that can be tested without Photos, where seams allow it
- database backup/repair helpers that can be tested without iOS UI
- search criteria combinations and place-hierarchy option narrowing
- solar event calculation, civil twilight percentages, solar noon, day/night segments, and fallback behavior
- time-of-day color resolver anchors and interpolation behavior
- trip detection and stopped-location filtering

## Regression test quality requirements

- Tests shall use temporary directories and temporary databases.
- Tests shall not depend on the developer's real Application Support directory, real photo library, real location history, or real legacy database.
- Tests shall not require network access.
- Tests shall avoid relying on wall-clock current time unless the behavior being tested explicitly requires it; prefer fixed dates.
- Tests for solar/twilight calculations shall use fixed coordinates, dates, and time zones.
- Tests shall verify both data values and preservation of user-facing error behavior where practical.
- Tests shall be added for every fixed regression when the behavior can be automated.
- If UI/device behavior cannot be automated in the package test suite, the requirement shall describe the manual Simulator/device validation step.

## Manual validation requirements

Before release, manually validate:

- first launch on a clean install
- first launch with a legacy `Documents/travels.sqlite`
- map/list browsing and date navigation
- manual add-current-location
- automatic tracking while foregrounded
- background tracking on a real device
- location permission changes and permission banner behavior
- address resolution on/off behavior
- missing-address queue behavior
- GPX import through the document picker
- GPX export and share sheet
- photo import from a geotagged photo
- photo import failure from a photo lacking location or timestamp metadata
- authentication lock on inactive/background/active scene changes
- database backup and restore
- demo data enabled and disabled
- settings persistence across relaunch
- App Store privacy strings and permission copy

## Requirement traceability requirements

- Each non-trivial feature requirement should have either an automated test, a documented manual validation step, or an explicit explanation for why it is not testable.
- Test names should make the protected behavior clear.
- When a bug is fixed, add or update a regression test whose name describes the regression.
- When tests reveal implementation behavior that conflicts with requirements, flag the mismatch rather than silently encoding the current behavior as correct.

## Known follow-up requirements

The following items remain known follow-ups before a production release:

- Validate background location behavior on a real device.
- Polish location icons so they do not imply travel direction or heading unless heading is intentionally represented.
- Review remaining shipping copy after device validation.
- Verify the final bundle identifier and legacy app identity before in-place upgrade distribution.
- Review any reused legacy artwork, glyphs, logos, or third-party code before public release.
