# Project Review Notes

This document summarizes the documentation-generation review and the assumptions used to draft the new Travels documentation set.

## Reviewed reference documentation from `dkrnet/issues`

The `issues` repository uses a documentation pattern with:

- `AGENTS.md` for AI/LLM editing guardrails
- `CONTRIBUTING.md` for concise workflow and test expectations
- `README.md` for overview, deployment, configuration, data model, and runtime notes
- `requirements.md` as the detailed functional specification
- a separate regression-testing requirements document
- `SECURITY.md` for supported versions, reporting, and deployment/security notes

For Travels, the regression-testing and application requirements have been intentionally collapsed into one `requirements.md` as requested.

## Reviewed Travels repository areas

The generated requirements are based on the current repository structure and these implementation areas:

- Swift package manifest and platform targets
- current README and implementation notes
- data models, settings, errors, and source enums
- SQLite store, migrations, indexes, health check, repair, search, event/geolocation persistence, and duplicate detection
- GPX import/export and legacy Travels child elements
- legacy `travels.sqlite` importer
- location filtering
- SwiftUI app model and bootstrap behavior
- main content view, toolbar, map/list toggles, date navigation, import/export, privacy lock, and settings
- photo import flow
- reverse-geocoding status/diagnostics behavior
- time-of-day color resolver and solar/twilight behavior
- existing XCTest coverage

## Additional context incorporated

The documentation also incorporates project context from prior design help on Travels, especially:

- civil morning/evening twilight as map/list color periods
- the bolder color palette selected for morning and evening civil twilight
- preserving night color while using stronger morning/evening colors
- GPX track-point child elements used in Travels exports and imports
- the goal that requirements be explicit enough to regenerate the application from scratch with the same look, feel, behavior, and development safeguards

## Deliberate documentation choices

- `requirements.md` is intentionally long and explicit.
- Build-process, repository-workflow, and regression-test rules are included in the same requirements document.
- Privacy and local-first constraints are repeated in multiple documents because they are central to the app.
- The requirements avoid adding cloud/sync/product features not present in the current app.
- The documents specify desired release validation steps for behavior that cannot be fully covered by Swift Package tests.

## Items to verify manually before committing these docs

- Confirm the intended final bundle identifier.
- Confirm the exact Xcode Simulator destination available on the development machine.
- Confirm whether a dedicated UI test target should be added.
- Confirm whether command-line build/test instructions should include a specific Xcode version.
- Confirm whether the current MPL-2.0 licensing policy is final.
- Confirm whether any legacy app artwork or icons are present and need third-party/legacy notices.


## Revision Notes

- Added a requirement that the add-current-location button must be visibly disabled/grayed out whenever that function is unavailable.
- Added documentation-governance requirements requiring requirements to focus on observable behavior and necessary compatibility constraints rather than unnecessary implementation details.
