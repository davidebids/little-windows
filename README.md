# Little Windows

Little Windows is a local-first SwiftUI care tracker for children and dogs. It targets iOS 17+, stores care history with SwiftData, and keeps predictions, insights, reminders, widgets, Live Activities, and night-light settings on device unless CloudKit is enabled in a signed build.

## Run

1. Open `LittleWindows.xcodeproj` in Xcode 15 or newer.
2. Select the `LittleWindows` scheme and an iOS 17+ simulator or device.
3. Build and run.

The first launch creates a starter child profile when the data store is empty. SwiftUI previews use an in-memory container with sample child and dog profiles, care events, predictions, appointments, milestones, and night-light state.

## Core features

- Multiple care profiles with profile switching, archival support, profile colors, and separate child/dog metadata.
- Child logs for sleep, feed, nursing, diaper, medicine, growth, temperature, activity, and custom events.
- Dog logs for food, water, treat, potty, walk, rest, training, grooming, medicine, symptoms, growth, temperature, vaccines, glucose, and custom events.
- Active timers for sleep, feed, nursing, activity, walk, rest, training, grooming, and custom logs.
- Stopped timer drafts that can be reviewed, resumed, saved, or discarded.
- Calendar/history views for browsing, editing, and filtering logged events.
- Milestones and memories with age-based prompts, categories, and profile scoping.
- Monthly age guides for child profiles and puppy-stage guide content for dog profiles.
- Appointments and visits with questions, notes, summaries, follow-up instructions, medications, vaccines, linked measurements, and reminders.
- JSON backup export/import and full local data deletion/reset.

## Sleep prediction

`LittleWindows/Services/SleepPredictionEngine.swift` implements the explainable `LittleWindowsSleep-v2` predictor. It blends editable age-based wake-window priors with recent profile-specific sleep history by nap index, prioritizes the most recent 45 days, uses weighted robust statistics, clips outliers, applies a conservative developmental trend, adjusts for previous naps and bedtime patterns, and returns a confidence-scaled time window.

Feed and nursing logs are optional soft confidence signals. `LittleWindows/Services/PredictionTuningService.swift` resolves predictions against actual sleep starts, reports error/window accuracy, and applies conservative per-nap early/late bias correction.

Predictions and Little Window alerts are planning aids only. They describe logged patterns and are not medical advice.

## Insights

The Insights tab provides analytics sections for Overview, Sleep, Wake Windows, Feeding, Diapers, Activities, Growth, Appointments, Milestones, Dog Care, and Prediction Accuracy. Sections support short lookback ranges, previous-period comparison, plain-language observations, and Swift Charts backed by `InsightsAnalyticsService`.

Analytics are calculated locally from the SwiftData event history. Sleep is grouped into overnight sessions, sequential Left/Right nursing logs can be combined when counting care sessions, and prediction errors use negative for predicted early and positive for predicted late.

## Night light

The Night Light tab turns the device screen into a configurable low-light care surface with:

- One-tap presets for diaper changes, nursing/feed sessions, soothing, reading, and check-ins.
- Soft red, amber, candlelight, orange, pink, warm white, cool white, and custom colors.
- Full-screen glow and selectable shapes.
- Steady, candle, fireplace, shimmer, rainy-window, and starry-night glow modes.
- Optional breathing animation, brightness/softness controls, sound, volume, sleep timer, and keep-awake behavior.
- Deep links, App Intents, App Shortcuts, and iOS 18 Control Center controls for common presets.

## Widgets, Live Activities, and shortcuts

The WidgetKit extension includes active-timer, next-sleep-window, today-summary, and quick-log widgets. Active timers also synchronize to a Live Activity with Dynamic Island presentations. App Intents and App Shortcuts can start common timers, stop the primary timer, and open night-light presets.

System actions open the app and execute through the same `EventTimerService` used by the Today screen. This keeps SwiftData mutation centralized while shared App Group snapshots keep external surfaces current. See [SYSTEM_INTEGRATIONS.md](SYSTEM_INTEGRATIONS.md) for signing, App Group, deep-link, widget, Live Activity, and real-device testing details.

## Legacy import archive

The project includes a bundled legacy import archive converted from a third-party baby-tracking export. It is used as seed data when explicitly loaded from Settings and is useful for exercising prediction, insights, growth, and history behavior with a large data set.

Existing installations can load the bundled archive from **Settings -> Data -> Load bundled history**. This replaces current local data after confirmation.

Regenerate a compatible archive from a new CSV export with:

```sh
ruby Scripts/convert_huckleberry.rb /path/to/export.csv \
  --output LittleWindows/SeedData/Imported-History-Backup.json \
  --summary LittleWindows/SeedData/Import-Summary.md \
  --birth-date 2026-01-31 \
  --baby-name "Sample Child"
```

Breast feeds containing time on both sides are split into sequential Left and Right events. Temperature, growth, and pumping records are retained as custom events.

## Privacy and sync

Version 1 deliberately uses a local SwiftData configuration so it runs without signing, CloudKit, accounts, passwords, or a custom backend. The Family Sync screen reports that shared sync is not enabled.

To enable CloudKit in a signed app:

1. Add the iCloud capability to the app target and enable CloudKit.
2. Select a production iCloud container owned by your Apple Developer account.
3. Change the `ModelConfiguration` in `LittleWindowsApp.swift` from `.none` to the selected CloudKit database.
4. Test schema deployment and migrations on multiple devices.
5. Add `CKShare` invitation creation and acceptance to `SyncService`.

## Validation

Useful local checks:

```sh
xcodebuild -list -project LittleWindows.xcodeproj
xcodebuild test -project LittleWindows.xcodeproj -scheme LittleWindows -destination 'platform=iOS Simulator,name=iPhone 15'
```

Simulator, Live Activity, Dynamic Island, App Group, notification, and Control Center behavior should also be verified on a signed physical device.
