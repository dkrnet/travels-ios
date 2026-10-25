# Security Policy

## Supported versions

Security fixes are considered for the current public version of the project.

Travels is intended to be a local-first personal iOS application. It stores location history, imported photo metadata, notes, settings, and migration state locally on the user's device. It is not intended to expose a public service, server API, remote administration interface, or unauthenticated data-sharing endpoint.

## Reporting a vulnerability

Please report security issues privately to the project maintainer rather than opening a public issue with exploit details. Include the affected version or commit, device/iOS version, reproduction steps, and any relevant logs with sensitive information removed.

Do not include unredacted precise location history, home/work addresses, photo metadata, database files, GPX exports, or biometric/device-authentication details in public reports.

## Security and privacy expectations

- Location history, notes, photo attachment filenames, imported photo metadata, and reverse-geocoded place data are privacy-sensitive.
- The app must remain local-first unless an explicit future requirement adds sync or server-backed behavior.
- The app must not add analytics, advertising identifiers, remote logging, telemetry, cloud sync, or third-party network services without an explicit requirements change.
- Reverse geocoding may send location data to Apple services when the user enables address resolution; this must remain disclosed in settings and App Store privacy copy.
- Photo import requires access to photo metadata and must fail safely when timestamp or location metadata is missing.
- Authentication lock uses device-owner authentication through LocalAuthentication. It is a privacy lock for casual access, not a replacement for iOS device security or encrypted backups.
- Database repair, backup, restore, and legacy import operations must avoid silent data loss.
- GPX exports and database backups can contain precise location history and must be treated as sensitive user-controlled files.

## Deployment and distribution notes

- Use the intended bundle identifier only after verifying compatibility with the legacy app identity and upgrade path.
- Keep the SQLite database and photo attachments in app-controlled local storage.
- Preserve iOS permission strings for location, background location, photo access, and privacy behavior.
- Validate background location behavior on a real device before release.
- Review any reused legacy artwork, glyphs, logos, screenshots, sample data, or third-party code before public distribution.
- If distributed through the App Store, ensure MPL-covered source availability requirements are satisfied.
