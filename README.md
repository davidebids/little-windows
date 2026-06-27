# Little Windows

Little Windows is a local-first SwiftUI care tracker for children and dogs. It targets iOS 17+, stores the main history with SwiftData, uses App Group snapshots for widgets and Live Activities, and can sync signed builds through Apple-native CloudKit.

The app is built around dense daily care workflows: quick logging, active timers, sleep planning, reports, guides, appointments, Food & Home lists, and private or shared iCloud-backed data modes.

## Run

1. Open `LittleWindows.xcodeproj` in Xcode 15 or newer.
2. Select the `LittleWindows` scheme.
3. Run on an iOS 17+ simulator or signed device.

First launch presents onboarding for a new empty store. It does not create default child profiles, care history, shopping lists, or personal archives automatically. SwiftUI previews and debug-only seed helpers use neutral sample child and dog data.

## App Areas

- Today: profile-scoped care logging, household and profile routines, active timers, quick actions, current prediction, and system integration refresh.
- Profiles: child and dog profiles with switching, colors, archival support, dog-specific details, and optional profile photos.
- History and Reports: day and list history, event editing, filtering, summaries, charts, and prediction accuracy review.
- Milestones and Memories: profile-scoped entries, age prompts, categories, photo attachments, and backup support.
- Appointments and Visits: questions, notes, summaries, follow-up instructions, medications, vaccines, measurements, and reminders.
- Guides: monthly child age guides and puppy-stage guide content with read state and reminder support.
- Food & Home: household shopping lists, store layouts and sections, shopping mode, recurring staples, inventory locations, meal prep tracking, and food reminders.
- Night Light: full-screen low-light presets, color and shape controls, animated glow modes, ambient sounds, sleep timer, and keep-awake behavior.
- Settings: backup/import, iCloud sync, Family Sync, notifications, prediction tuning, diagnostics, and local data reset.

## Care Logging

Child logs cover sleep, feed, nursing, diaper, medicine, growth, temperature, activity, and custom events.

Dog logs cover food, water, treat, potty, walk, rest, training, grooming, medicine, symptoms, growth, temperature, vaccines, glucose, and custom events.

Sleep, feed, nursing, activity, walk, rest, training, grooming, and custom logs can run as active timers. Stopped timer drafts can be reviewed, resumed, saved, or discarded before they enter the permanent history.

SwiftData mutations are centralized through services such as `EventMutationService`, `EventTimerService`, `ProfileService`, `DataExportImportService`, and Food & Home services.

## Sleep Prediction And Bedtime Planning

`LittleWindows/Services/SleepPredictionEngine.swift` implements the explainable `LittleWindowsSleep-v3` predictor. It blends editable age-based wake-window priors with profile-specific sleep history by nap index, prioritizes recent samples, clips outliers, uses weighted robust statistics, accounts for recent trends and previous naps, and returns a confidence-scaled sleep window.

The Plan Bedtime flow lets a caregiver choose a bedtime goal and build a full-day layout from the usual morning wake, typical nap counts, nap durations, and wake windows by nap order. It can still show the planned day after the selected bedtime has already passed, which is useful for comparing today against a goal.

Feed and nursing logs are optional soft confidence signals. `PredictionTuningService` resolves predictions against actual sleep starts, reports error/window accuracy, and applies conservative per-nap early/late bias correction.

Predictions, bedtime plans, and Little Window alerts are planning aids based on logged patterns. They are not medical advice.

## Reports And Insights

The Reports tab combines Day, List, and Summary modes. Summary analytics are calculated locally from SwiftData by `InsightsAnalyticsService` and include:

- Overview
- Sleep
- Wake Windows
- Feeding
- Diapers
- Activities
- Growth
- Appointments
- Milestones
- Dog Care
- Prediction Accuracy

Insights support short lookback ranges, previous-period comparison, plain-language observations, and Swift Charts. Sleep is grouped into overnight sessions, sequential Left/Right nursing logs can be combined for care-session counts, and prediction errors use negative values for early predictions and positive values for late predictions.

## Food & Home

Food & Home tracks household food routines separately from child and dog care events. It includes:

- Shopping lists with store-specific sections, priorities, quantities, notes, recurring staples, checked state, and reactivation helpers.
- Store layouts with default sections such as Produce, Refrigerated, Frozen, Pantry, Household, and Other.
- Inventory locations and items with quantity, unit, status, expiration, and notes.
- Meal prep items with servings, tags, storage details, usage history, and remaining counts.
- Food reminders that schedule local notifications and can link back to shopping lists or meal prep items.
- Shopping List and Food Quick Add widgets backed by lightweight App Group snapshots.

Food & Home data is included in JSON backup/import and in the shared Family Sync dataset.

## Night Light

Night Light turns the device screen into a configurable care surface:

- Presets for diaper changes, nursing/feed sessions, soothing, reading, and check-ins.
- Red, amber, candlelight, orange, pink, warm white, cool white, and custom colors.
- Full-screen glow with selectable shapes.
- Steady, candle, fireplace, shimmer, rainy-window, and starry-night modes.
- Optional breathing animation, brightness/softness controls, ambient sound, volume, sleep timer, and keep-awake behavior.
- Deep links, App Intents, App Shortcuts, and iOS 18 Control Center controls for common presets.

## Widgets, Live Activities, Shortcuts, And Deep Links

The WidgetKit extension includes:

- Active Timer widgets
- Next Sleep Window widgets
- Today Summary widget
- Quick Log widget
- Shopping List widget
- Food Quick Add widget

Active timers synchronize to a Live Activity with Lock Screen and Dynamic Island presentations. App Intents, App Shortcuts, deep links, and iOS 18 Control Center controls can start common timers, stop or resume timers, switch nursing sides, quick-log common events, open app destinations, and start night-light presets.

System surfaces pass commands back to the app and read lightweight App Group snapshots. They do not directly mutate the full SwiftData store. See [SYSTEM_INTEGRATIONS.md](SYSTEM_INTEGRATIONS.md) for signing, entitlements, routes, widgets, Live Activities, notification, and real-device testing details.

## Backup, Import, And Fixtures

Settings supports JSON backup export/import and full local data deletion/reset. Backups include profiles, events, prediction records, appointments, milestones, photo attachments, guide state, Food & Home data, and related local metadata.

The repository includes a neutral legacy import fixture for development and test validation:

- `LittleWindows/SeedData/Sample-Legacy-Tracker-Backup.json`
- `LittleWindows/SeedData/Legacy-Import-Summary.md`
- `Scripts/convert_legacy_tracker.rb`

The fixture is not bundled into production app resources. To load a personal archive on a device, use **Settings -> Data -> Import JSON backup**.

Regenerate a compatible archive from a CSV export with:

```sh
ruby Scripts/convert_legacy_tracker.rb /path/to/export.csv \
  --output LittleWindows/SeedData/Imported-History-Backup.json \
  --summary LittleWindows/SeedData/Import-Summary.md \
  --birth-date 2026-01-31 \
  --baby-name "Sample Child"
```

Breast feeds containing time on both sides are split into sequential Left and Right events. Temperature, growth, pumping, and unknown records are retained in neutral, importable forms.

## Privacy And Sync

Little Windows is local-first. User data is stored on device unless iCloud-backed sync is enabled in a signed build.

Supported modes:

- Local only: data stays on this device.
- Private iCloud Sync: data syncs through the private CloudKit database for devices signed into the same Apple Account.
- Shared Family Sync: accepted caregivers on different Apple Accounts can share one Little Windows dataset through a CloudKit shared record and `CKShare` invitation.

Family Sync is separate from Apple Family Sharing membership. It requires iCloud availability, signed builds with the configured CloudKit container, and real-device testing before production use.

The current CloudKit container identifier is:

```text
iCloud.com.debidia.LittleWindows
```

The App Group identifier used by widgets and Live Activities is:

```text
group.com.debidia.LittleWindows
```

Change `PersistenceService.iCloudContainerIdentifier`, the app entitlements, and the provisioning setup if the Xcode container differs for another Apple Developer team.

Migration and diagnostics:

1. Export a JSON backup from Settings -> Data before changing CloudKit containers or resetting development data.
2. `CloudMigrationService` marks local-to-CloudKit migration and assigns old profile-less records to an existing child profile when possible.
3. Settings -> iCloud Sync shows account status, sync mode, container identifier, migration state, last local save time, and record counts.
4. Settings -> Family Sync creates/manages/leaves shares, tracks owner/participant state, and can trigger a manual sync.
5. CloudKit Dashboard should be used to inspect the development schema and deploy it to production before TestFlight/App Store distribution.

## Validation

Useful local checks:

```sh
xcodebuild -list -project LittleWindows.xcodeproj
xcrun simctl list devices available
xcodebuild build -project LittleWindows.xcodeproj -scheme LittleWindows -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedDataValidation CODE_SIGNING_ALLOWED=NO
xcodebuild test -project LittleWindows.xcodeproj -scheme LittleWindows -destination 'platform=iOS Simulator,name=<available simulator name>,OS=<available runtime version>'
```

After changing the legacy converter or fixture:

```sh
ruby -rjson -e 'JSON.parse(File.read("LittleWindows/SeedData/Sample-Legacy-Tracker-Backup.json")); puts "ok"'
ruby -c Scripts/convert_legacy_tracker.rb
```

Live Activities, Dynamic Island, App Groups, Control Center controls, notifications, CloudKit private sync, and Family Sync should be verified on signed physical devices. Simulator support varies by runtime and does not fully reproduce those surfaces.
