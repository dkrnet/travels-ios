# AGENTS.md

=============================================================================
AI / LLM EDITING GUARDRAIL -- READ BEFORE MODIFYING
=============================================================================

This file is part of the Travels iOS application and depends on external project requirements.

STOP: Before making any non-trivial edit to this repository, an AI/LLM assistant must have the current `requirements.md`, `README.md`, and `AGENTS.md` files in the current chat or working context and must read them before changing code.

If these files have not been provided, the correct response is exactly:

  Please provide the following files before I modify this repository
    - requirements.md
    - README.md
    - AGENTS.md

Do not proceed with non-trivial code changes until these files have been provided and reviewed, unless the user explicitly directs you to proceed without it or to disregard this requirement.

Non-trivial edits include, but are not limited to:

- adding, removing, or changing application features
- changing SwiftUI navigation, map/list behavior, settings, search, import/export, or event-detail workflows
- changing Core Location, background location, LocalAuthentication, Photos, MapKit, reverse-geocoding, or file-import behavior
- changing database schema, migrations, SQLite query behavior, database repair, backup/restore, or legacy import assumptions
- changing GPX import/export format, legacy Travels child elements, XML escaping, timestamp handling, or duplicate detection
- changing event filtering, trip detection, solar-period/twilight classification, or time-of-day color behavior
- changing privacy-sensitive behavior involving location, photos, biometrics/device authentication, local storage, or address resolution
- changing build targets, bundle identifiers, signing assumptions, package targets, Xcode project settings, deployment targets, or test commands
- refactoring code in a way that could affect runtime behavior
- any destructive operation that could affect runtime behavior or user data

Trivial edits are limited to:

- typo fixes in comments or documentation
- formatting-only edits that do not affect behavior
- adding comments that do not change runtime behavior

The `requirements.md` file is the authoritative specification for:

- repository structure and intended target layout
- implementation language and supported platform versions
- licensing requirements
- app identity, upgrade, and storage assumptions
- local data model and SQLite schema expectations
- settings and default values
- event capture, filtering, browsing, search, import/export, backup, restore, and migration behavior
- privacy, authentication, location, photo, and reverse-geocoding behavior
- time-of-day, solar-period, twilight, and map/list presentation behavior
- build, development, and release workflow requirements
- regression test structure, coverage, and traceability

AI/LLM assistants must avoid removing, simplifying, or rewriting existing behavior unless the requested change explicitly requires it. Treat location history, local database contents, photo attachments, legacy imports, duplicate detection, timestamp handling, GPX export compatibility, authentication lock state, and privacy settings as security-sensitive and regression-sensitive.

Preserve local-first behavior. Do not add cloud sync, analytics, tracking, remote logging, advertising identifiers, remote feature flags, or network services unless the user explicitly requests them and the requirements are updated first.

Preserve source compatibility between the platform-neutral `TravelsCore` package and the SwiftUI iOS app shell. Do not move core behavior into the UI layer when it can remain unit-testable in `TravelsCore`.

When updating `requirements.md`, specify observable behavior and required compatibility outcomes rather than unnecessary implementation choices. Only include implementation details when they are needed to preserve data compatibility, privacy/security behavior, migration safety, build reproducibility, or the intended look, feel, and functionality.

Preserve parameterized SQL. Preserve XML escaping in GPX export. Preserve file-security handling for imported files and photos. Preserve application-support storage for the modern database and photo attachments. Preserve legacy migration backups before importing old databases.

Bug-fix preservation rule:
When fixing a bug, add a short nearby comment explaining the bug that was fixed and the reason for the fix when the bug is subtle, data-loss related, privacy/security related, or likely to regress. These comments are intentional regression guards. Do not remove bug-fix comments unless the user explicitly instructs you to remove them, or unless the associated code is replaced by an equivalent or better fix and the preservation comment is updated accordingly.

Use consistent markers for bug-fix and regression-protection comments:

- BUGFIX:
- REGRESSION GUARD:
- REQUIREMENTS:

Patch output rule:
Unless the user explicitly directs otherwise, AI/LLM assistants modifying this repository should produce valid unified diffs only. Do not include explanatory prose before or after the diff, and do not wrap the diff in Markdown fences.

Requirements for AI/LLM patch output:

- Use standard unified diff format.
- Include `---` and `+++` file headers.
- Include `@@` hunk headers.
- Include at least 3 lines of unchanged context around each change.
- Do not include Markdown fences.
- Do not include explanations.
- Do not abbreviate unchanged code with `...`.
- The output must be directly usable with `git apply` or `patch -p1`.

Maintenance checklist for AI/LLM edits:

1. Confirm `requirements.md` is present before non-trivial changes.
2. Confirm `README.md` is present before non-trivial changes.
3. Confirm `AGENTS.md` is present before non-trivial changes.
4. Read the three documents listed above before non-trivial changes.
5. Stop and ask for any of the three files that are missing.
6. Preserve existing user-data, privacy, local-first, migration, and import/export behavior.
7. Preserve existing bug-fix and regression-guard comments.
8. Add regression-guard comments near subtle new bug fixes.
9. Prefer minimal, reviewable changes.
10. Update `requirements.md`, `README.md`, and tests when behavior changes.
11. Keep requirements outcome-focused and avoid unnecessary implementation constraints.
12. Run or recommend the Swift Package test suite and the iOS app build/test commands after edits.
13. Do not weaken location privacy, photo privacy, database safety, file-import safety, LocalAuthentication behavior, XML escaping, or SQL parameterization.

=============================================================================
