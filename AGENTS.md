# Repository Guidance

This file is authoritative for work inside this repository. Keep machine-local or assistant-specific preferences out of it.

## Project Snapshot

Little Windows is a SwiftUI iOS 17+ app for local-first child and dog care tracking. It uses SwiftData for the main store, a private CloudKit database for same-Apple-Account sync in signed builds, WidgetKit/ActivityKit/App Intents for system surfaces, and JSON backup import/export for portability.

Primary code areas:

- `LittleWindows/Models`: SwiftData models and value types.
- `LittleWindows/Services`: persistence, prediction, import/export, notifications, widgets, live activities, sync, analytics, and mutation services.
- `LittleWindows/ViewModels`: stateful UI coordination.
- `LittleWindows/Views`: SwiftUI screens and reusable view components.
- `LittleWindows/AppIntents`: shortcuts, controls, and app intent entry points.
- `LittleWindowsWidgets`: widget and Live Activity extension code.
- `LittleWindows/Resources`: bundled reference content such as growth charts and guides.
- `LittleWindows/SeedData`: development/test import fixtures.
- `LittleWindowsTests`: XCTest coverage for prediction, import/export, sync, widgets, analytics, guides, appointments, and model behavior.

## Product And Privacy Rules

- Treat this as production-prep code. Do not introduce real personal names, family details, or third-party tracking-brand names into source, fixtures, UI copy, docs, tests, logs, or generated summaries.
- Use neutral sample names such as `Sample Child`, `Sample Dog`, `Test Child`, `Test Dog`, `Imported Child`, and `Sibling`.
- Before handoff for privacy cleanup work, scan source-facing paths with `rg -n -i "<term>" README.md LittleWindows LittleWindowsTests Scripts LittleWindows.xcodeproj`.
- Ignore stale matches inside `DerivedData*`; those are generated Xcode build outputs and are already gitignored.
- Do not bundle personal archives into production resources. The legacy tracker archive is a development/test fixture only.
- Keep README wording honest: personal archives should be loaded through **Settings -> Data -> Import JSON backup**.

## Legacy Import Fixture

- The neutral fixture is `LittleWindows/SeedData/Sample-Legacy-Tracker-Backup.json`.
- The neutral summary is `LittleWindows/SeedData/Legacy-Import-Summary.md`.
- The converter is `Scripts/convert_legacy_tracker.rb`.
- Generated notes should use neutral wording such as `Imported details:` and `History imported from a legacy tracker.`
- Growth migration code should remain brand-neutral; use names like `LegacyTrackerGrowthMigration`.
- Import behavior matters for analytics and predictions. After changing the converter, fixture, or import path, validate that the JSON parses and the converter has valid Ruby syntax.

Useful checks:

```sh
ruby -rjson -e 'JSON.parse(File.read("LittleWindows/SeedData/Sample-Legacy-Tracker-Backup.json")); puts "ok"'
ruby -c Scripts/convert_legacy_tracker.rb
```

## Data And Architecture Rules

- Keep SwiftData mutations centralized through existing services. Prefer `EventMutationService`, `EventTimerService`, `ProfileService`, `DataExportImportService`, and related service APIs over ad hoc model writes from views.
- Widgets, Live Activities, controls, shortcuts, and deep links should pass commands to the app and read lightweight App Group snapshots. They should not make unsafe concurrent edits to the full SwiftData history.
- Preserve profile scoping. Events, milestones, appointments, guide state, predictions, and snapshots must stay tied to the intended profile.
- Child and dog behavior diverge in meaningful ways. Check `profileType`, dog details, child-only growth/prediction assumptions, and UI copy before sharing logic across both.
- Sleep predictions are planning aids only. Keep user-facing language non-medical and confidence-aware.
- Family sharing is not production-ready until real CKShare support is implemented and tested. Do not imply multi-caregiver sharing works.
- CloudKit private sync is same-Apple-Account sync only.

## UI And Copy Rules

- Match the existing SwiftUI style: dense care workflows, clear forms, predictable navigation, and practical system colors.
- Keep settings and diagnostics copy precise. Do not overstate CloudKit, widgets, Live Activities, notifications, or family sharing capabilities.
- For production-facing UI, prefer generic labels over sample data references.
- When changing system integrations, update `SYSTEM_INTEGRATIONS.md` if behavior, routes, capabilities, entitlements, widgets, shortcuts, or testing steps change.

## Xcode Project Rules

- The app target is `LittleWindows`.
- The widget extension target is `LittleWindowsWidgets`.
- The test target is `LittleWindowsTests`.
- Keep `LittleWindows.xcodeproj/project.pbxproj` aligned with file renames and resource membership.
- Do not re-add seed fixtures to the production app resources unless explicitly required and reviewed.
- `DerivedData/`, `DerivedDataAnchoredMenus/`, and `DerivedDataValidation/` are generated and ignored. Do not use them as source of truth.

## Validation

Start with focused checks for the area changed, then use a build or tests when behavior can compile-break or regress broadly.

Useful commands:

```sh
xcodebuild -list -project LittleWindows.xcodeproj
xcodebuild build -project LittleWindows.xcodeproj -scheme LittleWindows -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedDataValidation CODE_SIGNING_ALLOWED=NO
xcodebuild test -project LittleWindows.xcodeproj -scheme LittleWindows -destination 'platform=iOS Simulator,name=<available simulator name>,OS=<available runtime version>'
```

Notes:

- The generic simulator build is useful for compile/link validation without choosing a specific simulator.
- In sandboxed environments, Xcode may fail while accessing CoreSimulator or developer caches. If the failure is environmental, rerun with appropriate approval instead of treating it as a source failure.
- Full simulator tests require an available runtime. Live Activities, Dynamic Island, Control Center controls, App Groups, notifications, and CloudKit behavior still need signed physical-device testing.

## Working Tree Safety

- The repository may already have unrelated local changes. Do not revert or overwrite them unless explicitly asked.
- When touching a dirty file, inspect the relevant context first and make the smallest safe edit.
- Prefer explicit renames for file moves so Git history remains understandable.
- Avoid broad formatting churn in Swift or project files.

## Handoff Expectations

For completed work, report:

- What changed.
- Which files or areas matter most.
- Which validation commands ran and whether they passed.
- Any remaining risk, especially simulator/device-only behavior, CloudKit schema work, provisioning, or generated stale `DerivedData*` output.
