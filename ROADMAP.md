# Travels Roadmap

This roadmap records possible future work for Travels. It is a planning aid, not a product specification or promise. `requirements.md` remains authoritative for implemented and required behavior. An issue must be refined, approved, implemented, tested, and merged before its roadmap description becomes application behavior.

## Status meanings

- **Planned**: Defined well enough to begin focused design or implementation work, subject to normal review.
- **Candidate**: Worth considering for the target release, but scope, priority, or interaction design still needs refinement.
- **Research**: Requires platform, entitlement, privacy, or feasibility investigation before implementation should be promised.

Items may move between releases or be split, combined, or removed as design and testing reveal better boundaries.

## 2.1.0

Travels 2.1.0 is the active development line. Its theme is clearer trip context, more flexible presentation and export, and careful exploration of summaries and CarPlay-related workflows.

### Planned

- [#52 Add unified context events around trips](https://github.com/dkrnet/travels-ios/issues/52): include eligible stopped events around selected trips, bring previous-day context under the same setting, and distinguish context connections visually without changing trip identity or timing.
- [#48 Add a setting to show or hide route lines](https://github.com/dkrnet/travels-ios/issues/48): let users display markers without ordinary route connectors while preserving map state and privacy defaults.
- [#55 Export location events returned by search](https://github.com/dkrnet/travels-ios/issues/55): export the complete filtered result set through the existing standards-compatible GPX workflow.
- [#56 Add user-facing full database export](https://github.com/dkrnet/travels-ios/issues/56): provide a safe, consistent export of the user's complete local data without adding user-facing database import.

### Candidates

- [#51 Improve CarPlay automation setup with App Shortcuts and guidance](https://github.com/dkrnet/travels-ios/issues/51): improve discovery and setup guidance for recommended CarPlay Connect and Disconnect personal automations.
- [#53 Cluster repeated same-location events on the map](https://github.com/dkrnet/travels-ios/issues/53): replace obscuring overlapping markers with an accessible count and event-selection workflow.
- [#42 Support a stopped-first default day display](https://github.com/dkrnet/travels-ios/issues/42): optionally open days emphasizing stopped events while retaining a clear way to include moving events.
- [#54 Add date-range reports and optional heat-map summaries](https://github.com/dkrnet/travels-ios/issues/54): summarize local data across standard or custom periods without overstating incomplete history.
- [#50 Add an optional scheduled daily summary](https://github.com/dkrnet/travels-ios/issues/50): provide a privacy-conscious, opt-in daily summary after reusable report calculations are defined.

### Research

- [#49 Research native CarPlay integration feasibility](https://github.com/dkrnet/travels-ios/issues/49): evaluate Apple eligibility, entitlement, template, distraction, review, and privacy constraints before committing to a CarPlay UI.

## Suggested sequencing

1. Define and implement context-event semantics before marker clustering so both features share one display-event model.
2. Implement search-result export independently using the existing GPX pipeline.
3. Design full database export around a consistent SQLite snapshot and secure temporary-file lifecycle.
4. Define report metrics and date-boundary rules before scheduled summaries.
5. Complete CarPlay feasibility research before planning any native CarPlay implementation; App Shortcuts guidance can proceed independently.

## Planning workflow

- Use one GitHub issue for each independently reviewable feature or research question.
- Add accepted work to the relevant milestone and keep its status label current.
- Create a focused design note for work with substantial data-model, privacy, migration, or interaction tradeoffs.
- Update `requirements.md`, user-facing documentation, and regression tests in the implementation pull request rather than treating this roadmap as the requirement.
- Do not create a release tag until the selected work is complete, validated, and ready to ship.
