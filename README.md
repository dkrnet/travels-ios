# Travels iOS

**Your location history. On your device.**

Travels iOS is a personal, privacy-first location history tracker built around local SQLite storage, map and list browsing, GPX portability, and zero third-party surveillance.

* **Public product overview:** `docs/index.md`
* **Privacy policy:** `PRIVACY.md`
* **Building, testing & contributing:** `CONTRIBUTING.md`
* **Authoritative specs:** `requirements.md`
* **AI/LLM editing guardrails:** `AGENTS.md`

---

### Intended Use & Philosophy
Travels is designed for personal, offline-first location logging on iOS. It records and organizes daily movement without requiring an account, cloud sync, or subscriptions.

* **Why it’s free:** Travels was built to solve a personal need for a niche audience. Users are not the product—the app contains no ads, analytics, tracking SDKs, or data monetization.
* **What it is not:** Travels is not a social network, fleet tracker, remote monitoring tool, or cloud-first location service.

---

### Core Capabilities

* **Local-first storage:** Stores coordinates, movement metadata, notes, and photo attachments in a local SQLite database (`Application Support/Travels/Travels.sqlite`) with built-in backup, restore, and integrity repair.
* **Flexible Location Capture:** Log your journeys your way with manual check-ins, Apple Shortcuts automations, or hands-free background tracking.
* **Battery-Aware Smart Tracking:** Background tracking automatically adjusts location precision based on how you move—optimizing power whether you are on the highway, driving through town, or stopped.
* **Private List-First Browsing:** New installs open directly in a chronological list without initializing maps, keeping your location history private by default.
* **Optional Apple Map Integration:** Opt into Apple Map View only when you want it, which downloads map tiles directly from Apple.
* **Rich Map & Trip Controls:** When maps are enabled, explore your journeys with synchronized map and list scrolling, solar time-of-day coloring, trip and stop filtering, and a built-in demo data mode.
* **Smart Filter Persistence:** Passive "Show All," "Show Latest," and auto-scroll features respect your active trip filters and ignore new events outside your current selection.
* **Data portability & migration:** Imports and exports standard **GPX 1.1** (with a documented `Travels` metadata namespace in `docs/gpx-extension-v1.md`), imports geotagged photos, and migrates older `travels.sqlite` databases.
* **Search & organization:** Offers fast filtering by text, date, notes, capture source, and hierarchical place names, plus manual overrides for trip endpoints and movement states.
* **Privacy controls:** Includes an optional `LocalAuthentication` (Face ID / Touch ID) privacy lock, opt-in Apple reverse geocoding, and an opt-in Apple Map View; both Apple network-backed features are off by default.

---

### Architecture & Repository Layout
The project separates platform-independent domain logic into a unit-testable Swift package (`TravelsCore`), keeping the iOS app shell thin.

```text
Package.swift           # Swift 6.0 package manifest (iOS 17+ / macOS 14+)
Sources/
  TravelsCore/          # Platform-neutral models, SQLite, GPX, search, migration, trip & solar logic
  TravelsCLI/           # Command-line tool for testing import/export outside iOS
iOSApp/
  TravelsApp/           # SwiftUI interface, MapKit, Core Location, Photos, LocalAuthentication
Tests/
  TravelsCoreTests/     # XCTest suite for core package logic
Fixtures/               # Sample GPX and test data
scripts/                # Helper scripts for testing, simulator/device builds, backups, and recovery
Travels.xcodeproj/      # Xcode project (bundle ID: com.adigitalanalog.travels)
```

The device-backup helper reports and uses a canonical absolute destination under the repository's sibling `device-backups` directory by default, while `--output-root` can select another location.

---

### Documentation & Synchronization
`requirements.md` serves as the authoritative specification for application behavior, UI/UX, data models, and build rules. Any behavioral changes must keep `requirements.md`, `PRIVACY.md`, and the regression test suite synchronized so the app remains reproducible from documentation alone.

### License
Travels iOS is licensed under the **Mozilla Public License 2.0** (see `LICENSE`). Project-owned source files carry the standard MPL-2.0 header, while third-party dependencies and visual assets retain their original notices.
