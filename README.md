# Little Windows

Little Windows is a private, local-first SwiftUI baby-care tracker for Ethan, David, and Rachel. It targets iOS 17 and stores profiles, events, and sleep-prediction outcomes with SwiftData.

## Run

1. Open `LittleWindows.xcodeproj` in Xcode 15 or newer.
2. Select the `LittleWindows` scheme and an iOS 17+ simulator or device.
3. Build and run.

The first launch imports the bundled Huckleberry archive when the data store is empty. SwiftUI previews use a separate in-memory container with sample sleep and feed events.

## Huckleberry archive

`LittleWindows/SeedData/Ethan-Huckleberry-Backup.json` is a native Little Windows backup containing 4,774 converted events from January 31 through June 10, 2026. Existing installations can load it from **Settings → Data → Load Ethan's Huckleberry history**. This replaces current local data after confirmation.

Regenerate the archive from a new Huckleberry export with:

```sh
ruby Scripts/convert_huckleberry.rb /path/to/huckleberry.csv \
  --output LittleWindows/SeedData/Ethan-Huckleberry-Backup.json \
  --summary LittleWindows/SeedData/Huckleberry-Import-Summary.md \
  --birth-date 2026-01-31 \
  --baby-name Ethan
```

Breast feeds containing time on both sides are split into sequential Left and Right events. Temperature, growth, and pumping records are retained as custom events.

## Prediction engine

`Services/SleepPredictionEngine.swift` implements the explainable `LittleWindowsSleep-v2` predictor. It blends editable age-based wake-window priors with Ethan's recent wake windows by nap index, prioritizes the most recent 45 days, uses weighted robust statistics, clips outliers, applies a conservative developmental trend, adjusts for the previous nap and bedtime patterns, and returns a confidence-scaled time window. Feed and nursing logs are soft confidence signals only.

`Services/PredictionTuningService.swift` resolves predictions against actual sleep starts, reports error/window accuracy, and applies a conservative per-nap early/late bias correction.

## Insights dashboard

The Insights tab provides seven analytics sections: Overview, Sleep, Wake Windows, Feeding, Diapers, Activities, and Prediction Accuracy. Each supports 3-, 7-, 14-, and 30-day ranges, optional comparison with the preceding period, plain-language pattern observations, and native Swift Charts backed by `InsightsAnalyticsService`.

Analytics are calculated locally from the SwiftData event history. Sleep is grouped into overnight sessions, sequential Left/Right nursing logs are combined when counting care sessions, and prediction errors use negative for predicted early and positive for predicted late. These summaries describe logged patterns only and are not medical advice.

## Widgets and Live Activities

Active timers are synchronized to WidgetKit widgets and a Live Activity with Dynamic Island support. The extension also includes next-sleep, today-summary, and quick-log widgets, App Shortcuts, and availability-gated iOS 18 Control Center controls.

System actions open the app and immediately execute through the same `EventTimerService` used by the Today screen. This keeps SwiftData mutation centralized while shared App Group snapshots keep external surfaces current. See [SYSTEM_INTEGRATIONS.md](SYSTEM_INTEGRATIONS.md) for signing, App Group, deep-link, and real-device testing instructions.

## iCloud and family sharing

Version 1 deliberately uses a local SwiftData configuration so it runs without signing or CloudKit setup. The Family Sync screen reports that shared sync is not enabled.

To enable CloudKit in a signed app:

1. Add the iCloud capability to the app target and enable CloudKit.
2. Select a production iCloud container owned by your Apple Developer account.
3. Change the `ModelConfiguration` in `LittleWindowsApp.swift` from `.none` to the selected CloudKit database.
4. Test schema deployment and migrations on two devices.
5. Add `CKShare` invitation creation and acceptance to `SyncService`.

No email/password login or custom backend is used.

## Obvious v2 improvements

- Richer charts and trend comparisons
- Lock Screen widgets and Live Activities
- Apple Watch timer controls
- Better CloudKit sharing invitations and participant management
- CSV export and photo attachments
- Siri Shortcuts and App Intents
- More advanced prediction models after enough Ethan-specific outcomes are collected
