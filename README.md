# Little Windows

Little Windows is a local-first SwiftUI home organizer and optional care tracker for children, adults, and dogs. Adult profiles can represent yourself or someone you care for, such as a parent or grandparent. It targets iOS 17+, stores the main history with SwiftData, uses App Group snapshots for widgets and Live Activities, and can sync signed builds through Apple-native CloudKit.

The app is built around dense daily care workflows: quick logging, active timers, customizable Today actions, sleep planning, routines, reports, guides, appointments, Food & Home lists, and private or shared iCloud-backed data modes.

## Support And Privacy

- [Little Windows Support](SUPPORT.md)
- [Little Windows Privacy Policy](PRIVACY.md)

## Run

1. Open `LittleWindows.xcodeproj` in Xcode 15 or newer.
2. Select the `LittleWindows` scheme.
3. Run on an iOS 17+ simulator or signed device.

First launch presents onboarding for a new empty store. A user can begin with **Home, Food & Night Light** without creating a care profile, or add a child, adult, or dog profile during setup. Household-only mode presents Today, Home, and Night Light as the primary app areas; adding the first active care profile expands navigation to Reports and Care and opens Today in its Care mode. Archiving the last active care profile saves any open timer, clears profile-scoped alerts, and returns to the household-only layout without deleting that profile or its history.

Returning users can choose **Restore from iCloud** to wait for data previously synced through Private iCloud Sync on the same Apple Account, or open Settings to import a JSON backup. The iCloud option does not create or overwrite data when no synced household or profile arrives, and it does not represent a separate server-side backup snapshot. If someone completes new setup before their original profile finishes downloading, the app can remove the newer empty matching setup shell in favor of the historical profile; it leaves profiles alone when both own history. The caregiver name for new entries uses iCloud key-value storage so it can follow the same Apple Account without becoming a shared Family Sync household value; older installs can recover one unambiguous non-default name from synced care history. The app does not create default care profiles, care history, shopping lists, or personal archives automatically. SwiftUI previews and debug-only seed helpers use neutral sample data.

## App Areas

- Today: a household overview for Home and Food, a shared Needs Attention queue for urgent Home and care follow-ups with visible personal snoozes and one-tap restore, plus profile-scoped care logging, household and profile routines, active timers, customizable quick actions, current prediction, guided sleep day-ahead planning, and system integration refresh when a care profile is active.
- Profiles: child, adult, and dog profiles with switching, colors, archival support, relationship-aware adult details, dog-specific details, optional profile photos, and private-by-default Family Sync opt-in.
- History and Reports: day and list history, event editing, filtering, summaries, charts, prediction accuracy review for children, and adult health trends.
- Medications: versioned medication plans with effective dates, change source and caregiver audit history, medication reconciliation after visits or discharge, confirmed-current and last-reviewed status, daily and complex schedules, actual dose time and amount, late or different/partial dose tracking, held/refused/unable/missed outcomes with reasons, richer adherence summaries, as-needed interval and daily-limit guardrails, actual-use run-out estimates, prescription and refill details, trip supply warnings, assignable request/pickup tasks, local reminders with optional follow-ups and notification logging actions, and an Apple Watch upcoming-dose card with Taken, Skipped, and 10-minute Snooze controls.
- Milestones, Memories, and Solids: profile-scoped entries and age prompts, adult-appropriate memories and milestones, plus a child-only solids workspace for preparation, planning, allergens, recipes, and tracking.
- Appointments and Visits: questions, notes, summaries, individually due and completable follow-ups, medications, vaccines, measurements, and reminders.
- Guides: monthly child age guides, source-backed Sleep Basics lessons, and puppy-stage guide content with read state and reminder support.
- Food & Home: household to-do lists, shopping lists, trip itineraries and packing, store layouts and sections, shopping mode, recurring staples, inventory locations, meal prep tracking, return tracking, and reminders.
- Night Light: full-screen low-light presets, color and shape controls, animated glow modes, ambient sounds, sleep timer, and keep-awake behavior.
- Settings: backup/import, iCloud sync, Family Sync, notifications, prediction tuning, diagnostics, and local data reset.
- Travel-aware time zones: automatic per-timestamp zone capture, a device-level manual override, and per-entry start/end zone editing.

## Care Logging

Child logs cover sleep, night wakings, feed, nursing, pumping, diaper, potty, medicine, growth, temperature, activity, and custom events. Feed logs distinguish bottle, solids, and other feeds; bottle and pumping entries support optional ounce amounts. Solid feeds use the same event history while attaching per-food amounts, preferences, notes, confirmed allergen-introduction portions, and reaction details. Quantitative amounts are optional; when entered, all 535 built-in foods provide estimates for calories, protein, fat, fiber, iron, zinc, calcium, and vitamin C. Custom foods can use a manual nutrition label, and the recipe builder calculates per-serving totals. A separate child-only Solids workspace in Care provides the bundled food database, age-specific preparation photography and instructions, an adaptable First 100 path, nine-allergen planning and rotation, 424 recipes, custom foods with optional photos, meal planning, inventory-aware shopping handoff, tracking, and feeding-report links.

The child care form keeps pumping, solids, potty, and the rest of the child activity set in the same event editing surface. Structured details include:

- Sleep kind, feed kind, nursing side, diaper kind, child potty kind/location, medicine dose/unit, temperature/unit/method, growth measurements, and activity type.
- Solid-food style options for puree/spoon-fed, baby-led weaning, combination, other, and unknown.
- Solid-meal texture and feeding style, plus per-food preference, serving amount, preparation notes, allergens actually served, confirmed introduction portions, and reaction symptoms, timing, response, and follow-up.
- Child potty pee/poo/both details with location, amount, color, texture, and notes where relevant.

Dog logs cover food, water, treat, potty, walk, rest, training, grooming, medicine, symptoms, growth, temperature, vaccines, glucose, and custom events.

Adult logs cover medications, symptoms, blood pressure, pulse, oxygen saturation, respiratory rate, blood glucose, temperature, weight/height, pain, sleep, activity, and custom notes. The adult health dashboard charts entered values without diagnosing or interpreting them. Medication doses, symptoms, and measured vitals require a fresh entry or managed dose action instead of being cloned by Repeat Last. Adult appointment presets include primary care, specialists, labs, therapy, dental, imaging, procedures, eye care, and urgent care.

Medication schedules support daily doses, selected weekdays, every-N-days routines, fixed courses, on/off cycles, alternating doses, tapers, and as-needed use. Medication plan changes create a new regimen version instead of rewriting the prior schedule; each audit entry records its effective date, prescription-label/discharge-paperwork/clinician/caregiver source, the caregiver who entered it, and before-and-after plan details. The reconciliation workflow requires every current medication to be confirmed, updated, or stopped before recording completion, and it is available directly from completed visit details. Each medication shows its last-reviewed date and whether it has been confirmed current. A detailed dose entry can record the actual time and amount, a late or different/partial dose, held per clinician, refused, unable to take, or a missed-dose reason such as asleep, away, or out of supply. Adherence views keep recorded outcomes separate from doses that were never logged, and supply tracking follows the actual amount taken. Recent taken-dose history powers an estimated run-out date; upcoming trips warn when supply may run out before or during travel. Prescription number, fill quantity, remaining refills, expiration, pharmacy, and refill lead time feed an assignable Home task that progresses from request needed to requested, ready for pickup, and picked up. Pickup adds the fill to supply and reduces the remaining-refill count. Reminders follow either local time or the home time zone, refresh on foreground reconciliation, share one bounded rolling request budget across all active medications while preserving room already used by other app reminders, and support snooze, optional 30-minute follow-up, and managed Taken/Skipped actions. Reminder actions are checked against the current schedule, and an active snooze is preserved through unrelated refreshes but removed after the dose is logged or its schedule changes. Little Windows records the instructions, sources, reviews, and outcomes entered by the user; it does not validate doses, interactions, contraindications, or clinical decisions.

For adult profiles, the Apple Watch companion shows the nearest unlogged scheduled dose from the prior 12 hours or upcoming seven days. Taken and Skipped actions use the same managed dose, timeline, supply, and conflict-handling path as the iPhone. Snooze is available within 30 minutes of the scheduled time when that regimen's reminders are enabled and stays disabled until the snoozed reminder fires; disconnected actions queue with their original tap time and stale or conflicting commands are rejected safely by the iPhone.

Sleep, feed, nursing, pumping, activity, walk, rest, training, grooming, and custom logs can run as active timers. Stopped timer drafts can be reviewed, resumed, saved, or discarded before they enter the permanent history.

Care events store concrete start and end time-zone identifiers. A timer can therefore begin in one zone and end in another without changing its real elapsed duration, while Today, History, summaries, insights, widgets, backups, Family Sync, and report exports continue to use each entry's recorded local day and clock time.

Quick repeat and backup/import preserve the production care details above, including pumping amounts, solid feeding style, diaper/potty details, medicine details, growth values, temperature readings, and activity metadata.

## Today And Routines

Today is the main operational screen for care. It includes:

- A profile-aware Log Something section with child, adult, and dog actions appropriate to the active profile.
- Smart quick actions ranked from recent history, active timers, prediction context, and user-pinned actions.
- Per-profile Today action customization so caregivers can hide categories they do not use without affecting history, reports, backup/import, widgets, or other profiles.
- Active timer cards and saved timer drafts for review before logging.
- Household and profile-scoped routines, routine templates, custom routine steps, start/skip/complete flows, reminders, duplication, reordering, archiving, and an explicit Done button in the routines manager.
- A child sleep day-ahead card below Log Something, generated from recent sleep history and confidence-aware planning windows.

SwiftData mutations are centralized through services such as `EventMutationService`, `EventTimerService`, `ProfileService`, `DataExportImportService`, and Food & Home services.

## Sleep Prediction And Bedtime Planning

`LittleWindows/Services/SleepPredictionEngine.swift` implements the explainable `LittleWindowsSleep-v3` predictor. It blends editable age-based wake-window priors with profile-specific sleep history by nap index, prioritizes recent samples, clips outliers, uses weighted robust statistics, accounts for recent trends and previous naps, and returns a confidence-scaled sleep window.

The Today sleep day-ahead card summarizes the next sleep window, recent awake context, and usual bedtime cues. The Plan Bedtime flow lets a caregiver choose a bedtime goal and build a full-day layout from the usual morning wake, typical nap counts, nap durations, and wake windows by nap order. It can still show the planned day after the selected bedtime has already passed, which is useful for comparing today against a goal.

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

Insights support short lookback ranges, previous-period comparison, plain-language observations, and Swift Charts. Sleep is grouped into overnight sessions, explicit night-waking logs feed overnight wake metrics, sequential Left/Right nursing logs can be combined for care-session counts, and prediction errors use negative values for early predictions and positive values for late predictions.

## Food & Home

Food & Home tracks household food routines separately from profile-scoped care events. It includes:

- Shopping lists with store-specific sections, priorities, quantities, notes, recurring staples, checked state, smart history reactivation, bulk entry, reusable list duplication, and reordering helpers.
- Named home to-do lists with active and completed sections, added/completed caregiver tracking, and optional assignment to yourself or an accepted Family Sync caregiver.
- Trip workspaces with a manual, day-by-day itinerary alongside packing. Itinerary entries support specific or flexible times, ideas without a day, activities, transportation, flights, lodging, meals, tasks, and notes; booking status and confirmation details; multiple web links; mapped places and directions; per-caregiver assignments and reminders; and mutually exclusive option groups for weather-dependent or undecided plans. Packing supports trip-local adults plus linked child, adult, and dog profiles, duration-aware starter suggestions, traveler and bag grouping, quantities, essential items, per-caregiver responsibility, targeted reminders, packed-by attribution, completion progress, duplication, and shopping-list handoff.
- Per-destination WeatherKit forecast guidance with explicit full or partial trip-day coverage and reviewable rain, cold-weather, heat, and high-UV additions. Forecasts automatically become available as each destination's dates enter the forecast window.
- Store layouts with default sections such as Produce, Refrigerated, Frozen, Pantry, Household, and Other.
- Inventory locations and items with quantity, unit, status, expiration, and notes.
- Meal prep items with servings, tags, storage details, usage history, and remaining counts.
- Returns with multiple items, send-back details, return links, return-by dates, drop-off partners, return label photos, and drop-off/completion tracking.
- Food & Home reminders that schedule local notifications and can link back to to-do lists, shopping lists, meal prep items, or returns.
- Shopping List and Food Quick Add widgets backed by lightweight App Group snapshots.

Food & Home data, including Home to-do and trip assignments, itineraries, links, option selections, and packing state, is included in JSON backup/import and in the shared Family Sync dataset. Shared assignment choices are limited to accepted caregivers in the same Family Sync space; without Family Sync, Home to-dos can be assigned only to the current caregiver or left unassigned. Targeted trip reminders are local to each device and match the item's assignee to that device's caregiver name in Settings.

## Night Light

Night Light turns the device screen into a configurable care surface:

- Presets for diaper changes, nursing/feed sessions, soothing, reading, and check-ins.
- Red, amber, candlelight, orange, pink, warm white, cool white, and custom colors.
- Full-screen glow with selectable shapes.
- Steady, candle, fireplace, shimmer, rainy-window, and starry-night modes.
- Optional breathing animation, brightness/softness controls, ambient sound, volume, sleep timer, and keep-awake behavior.
- A one-tap Home Screen or Lock Screen widget for the dim red diaper-change preset, with additional nursing and soothing actions in the medium widget.
- Deep links, App Intents, App Shortcuts, and iOS 18 Control Center controls for common presets.

## Widgets, Live Activities, Shortcuts, And Deep Links

The WidgetKit extension includes:

- Active Timer widgets
- Next Sleep Window widgets
- Today Summary widget
- Quick Log widget
- Shopping List widget
- Food Quick Add widget
- Night Light widget

Active timers synchronize to a Live Activity with Lock Screen and Dynamic Island presentations. App Intents, promoted App Shortcuts, deep links, and iOS 18 Control Center controls can start common timers, stop or resume timers, switch nursing sides, quick-log common events, open app destinations, and start night-light presets where that surface exposes them.

Without an active care profile, care-specific widgets use an intentional **Add a care profile** state instead of showing fictional or stale care data. Care-only shortcuts and deep links open the app with the same profile prompt; Home, Food, Settings, and Night Light links continue to work normally.

System surfaces pass commands back to the app and read lightweight App Group snapshots. They do not directly mutate the full SwiftData store. See [SYSTEM_INTEGRATIONS.md](SYSTEM_INTEGRATIONS.md) for signing, entitlements, routes, widgets, Live Activities, notification, and real-device testing details.

## Backup, Report Export, Import, And Fixtures

Settings supports JSON backup export/import and full data deletion/reset. The confirmation identifies whether the action affects only this device, private iCloud devices on the same Apple Account, or every caregiver in a Family Sync space. Only a confirmed Family Sync owner can replace or erase the complete shared dataset. Both operations create a local automatic recovery backup first. Backups include the caregiver identity used for new entries, profiles, events and structured health observations, medications and dose history, prediction records, appointments, milestones, photo attachments, the custom solid-food catalog, guide state, Home data, and related local metadata. Import restores the backed-up caregiver identity only when the receiving install does not already have an explicit one.

If the SwiftData store cannot open, Little Windows presents a recovery screen instead of terminating. It can retry without changing the store, restore a validated automatic backup, or preserve the unreadable store and start empty. Recovery archives all store artifacts before opening a new local-only copy, so it does not silently delete iCloud or Family Sync data.

Settings also supports profile-scoped CSV and PDF care report export for doctor visits and caregiver handoff. Report export includes selectable 7-day, 30-day, and custom date ranges, optional notes and caregiver names, the current medication plan, and care-profile events with appointments and milestones when enabled. CSV/PDF reports are human-readable only; JSON remains the restore/import format.

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
- Shared Family Sync: accepted caregivers on different Apple Accounts can share household data and only the care profiles explicitly opted in by their owner. New profiles are private by default, and a shared-data refresh preserves private profiles and their records locally.

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
