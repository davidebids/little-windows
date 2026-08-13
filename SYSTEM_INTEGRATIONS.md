# Little Windows System Integrations

Little Windows integrates with WidgetKit, ActivityKit, App Intents, App Shortcuts, deep links, local notifications, App Groups, WatchConnectivity, an Apple Watch companion, and iOS 18 Control Center controls. The iPhone app remains the single writer for SwiftData history; extensions and system surfaces pass commands back to it and read lightweight snapshots.

## Included surfaces

- Active Timer widget: small, medium, Lock Screen rectangular, and Lock Screen inline, with an add-profile state when no care profile is active.
- Next Sleep Window widget: small, medium, and Lock Screen rectangular, with an add-child state when no care profile is active.
- Today Summary widget: medium, including unified child care summary metrics for sleep, feeding, nursing, pumping, diapers, potty, medicine, temperature, growth, and activities when present, plus an add-profile state when care tracking has not been set up.
- Quick Log widget: medium, backed by profile-scoped ranked smart actions, hidden-category preferences, and user-pinned actions from Today, plus an add-profile state when care tracking has not been set up.
- Shopping List widget: small and medium, backed by the Food & Home shopping snapshot.
- Food Quick Add widget: medium, opens grocery quick add, solids logging, and usual shopping lists in the app.
- Live Activity with Lock Screen, Dynamic Island compact, Dynamic Island minimal, and Dynamic Island expanded presentations.
- App Intents for timer control, quick logging, app navigation, and night-light presets.
- App Shortcuts for repeat-last logging, solids and other high-frequency quick logging, timer control, and dog care.
- iOS 18 Control Center controls for sleep, Left nursing, Right nursing, tummy time, stop timer, diaper-change light, and soothing light.
- A dependent watchOS 10+ companion app with profile switching, six profile-aware smart or customized favorites, a watch-safe All Actions list, timer controls, today metrics, and sleep-window predictions.
- Apple Watch complications and Smart Stack widgets for the active timer, next sleep window, and today summary, with add-profile states when care tracking is not active.
- Apple Watch App Intents for the most common profile-aware care actions.
- Local notifications for sleep windows, medication schedules, routine reminders, appointment reminders, monthly guide reminders, itinerary items, trip packing and final-check reminders, and user-created Food & Home reminders. Medication reminders support snooze, optional 30-minute follow-up, and managed Taken/Skipped actions; the Apple Watch adult-profile card can perform the same dose actions and schedule a 10-minute snooze through the paired iPhone.
- WeatherKit forecasts and Apple Weather attribution for trip packing suggestions.

The primary Live Activity priority is Sleep, Nursing, Pumping, Feed, Tummy Time, Reading, then Bath. When another timer is active, the surface displays a `+1 more active` count.
Running Active Timer widgets show the original session start in a compact footer, such as **Sleeping since 9:12 AM**, while keeping the live elapsed duration prominent. The Lock Screen Live Activity places that start time on the same row as the caregiver and other timer details, right-aligned to avoid increasing the activity's height. The expanded Dynamic Island repeats the start-time context in its footer. Nursing timer widgets and expanded Live Activity presentations show both the live total duration and the cumulative duration for the active Left or Right side.

## Xcode capability setup

The source and entitlements currently use this App Group:

```text
group.com.debidia.LittleWindows
```

The app target also uses this CloudKit container for SwiftData private database sync and Family Sync shared records:

```text
iCloud.com.debidia.LittleWindows
```

For the `LittleWindows`, `LittleWindowsWidgets`, `LittleWindowsWatch`, and `LittleWindowsWatchWidgets` targets:

1. Open **Signing & Capabilities**.
2. Select the same Apple Developer team.
3. Add the **App Groups** capability.
4. Enable `group.com.debidia.LittleWindows`.
5. Let Xcode regenerate both provisioning profiles.

For the `LittleWindows` app target only:

1. Add the **iCloud** capability.
2. Enable **CloudKit**.
3. Enable **Key-value storage** so the caregiver identity for new entries follows the same Apple Account.
4. Select or create `iCloud.com.debidia.LittleWindows`.
5. Add the **Push Notifications** capability to the main app target. The widget extension does not need it.
6. Enable the **Remote notifications** background mode on the main app target.
7. Keep `LittleWindows/LittleWindows.entitlements` connected to the target.
8. Add the **WeatherKit** capability. In the Apple Developer portal, enable WeatherKit in both the app identifier’s **Capabilities** tab and its separate **App Services** tab; enabling only the capability leaves WeatherKit JWT authentication unavailable.
9. Use CloudKit Dashboard to inspect the development schema and deploy it to production before TestFlight/App Store use.
10. For Family Sync testing, create a share from Settings > Family Sync on the owner's device, accept the iCloud invitation on a second Apple Account, and verify both devices can write care data.

The source entitlement declares the development APNs environment. Xcode derives the final development or production value from the provisioning profile when it signs the app; verify the exported TestFlight/App Store app contains `aps-environment = production`.

After WeatherKit is enabled for the app identifier, regenerate the provisioning profile and install a newly signed build. An app already installed from an older profile does not gain the WeatherKit entitlement automatically. Before device testing, verify both the signed app entitlements and its embedded provisioning profile contain `com.apple.developer.weatherkit = true`. The trip UI distinguishes a build-configuration failure from an offline connection and a temporary WeatherKit service failure. Destination cards open an in-app daily forecast. The Apple Weather mark is non-interactive, and the in-app attribution sheet displays WeatherKit’s supplied legal attribution text instead of unexpectedly opening a browser.

If Xcode reports that the App Group is unavailable for a Personal Team, a paid Apple Developer team is required for reliable shared widget/action state. The main app still runs without the shared group, but widgets cannot reliably read timer snapshots and system buttons should be treated as open-app fallbacks.

The app target includes:

- `NSSupportsLiveActivities = YES`
- `CKSharingSupported = YES` so installed TestFlight/App Store builds can open CloudKit Family Sync invitations
- the `littlewindows` URL scheme
- `LittleWindows/LittleWindows.entitlements`

The extension target includes:

- the WidgetKit extension point
- `LittleWindowsWidgets/LittleWindowsWidgets.entitlements`
- bundle identifier `com.debidia.LittleWindows.widgets`

The Apple Watch integration includes:

- `LittleWindowsWatch`, a dependent watchOS 10+ app with bundle identifier `com.debidia.LittleWindows.watchkitapp`
- `LittleWindowsWatchWidgets`, a watch WidgetKit extension with bundle identifier `com.debidia.LittleWindows.watchkitapp.widgets`
- `LittleWindowsWatch/LittleWindowsWatch.entitlements` and `LittleWindowsWatchWidgets/LittleWindowsWatchWidgets.entitlements`, both using the same App Group
- an **Embed Watch Content** build phase on the iPhone app target and an **Embed Foundation Extensions** phase on the watch app target
- `WKCompanionAppBundleIdentifier = com.debidia.LittleWindows` on the watch app

Select the same Apple Developer team for both watch targets, add the App Groups capability to both, and regenerate their provisioning profiles. The watch app is intentionally dependent on the iPhone app and does not declare `WKWatchOnly`.

## Apple Watch companion behavior

The watch is a fast companion surface, not an independent data store. It receives a versioned, profile-scoped state snapshot from the iPhone using WatchConnectivity and caches that snapshot in the shared App Group for offline UI and complications. The snapshot contains only active profiles, the selected profile, every active timer for that profile, a sleep prediction when available, today metrics, up to six favorites, and the watch-safe action catalog. The app presents simultaneous timers in a compact stack with one shared live timeline; each timer's pause, resume, save, discard, and nursing-side controls target that exact timer.

Child smart-favorite defaults are Sleep, Nursing, Feed, Diaper, Pumping, and Tummy Time. Dog defaults are Food, Water, Potty, Walk, Treat, and Rest. The iPhone's ranked quick actions replace those defaults when matching watch-safe actions are available. Settings > Apple Watch can instead store a custom ordered selection of up to six actions for each profile. Hidden care categories remain hidden on the watch. All Actions adds less frequent watch-safe timers and quick logs, including child potty plus Tummy Time, Story Time, Brush Teeth, Indoor Play, Outdoor Play, Screen Time, and Bath timers, and a Dog Grooming timer. Adult Activity offers Exercise, Physical Therapy, Social Activity, Brush Teeth, Screen Time, and Bath without exposing child-development activities. Sleep includes Nap, Night Sleep, and Night Waking choices; Feed includes Bottle and Other. Solids remain iPhone-only because selecting at least one food is required. Detailed editors such as medicine, temperature, growth, and custom notes also remain on the iPhone so the Watch cannot silently create incomplete records.

Settings > Apple Watch reports pairing, companion installation, the last confirmed Watch contact, whether the latest state revision has been received, and whether an immediate foreground connection happens to be available. `isReachable` is presented only as `Connected now`; it is not treated as sync health because normal background delivery does not require live reachability. **Send Latest State** queues a fresh profile, favorites, timers, prediction, and summary snapshot. Whenever the companion accepts an authoritative state, it returns the revision through its latest-only application context so the iPhone can distinguish an update that is merely queued from one the Watch has actually received.

Every watch mutation is a versioned, uniquely identified command containing its profile, the watch tap time, time zone, and expected timer revision when applicable. Timer starts offer **Now** or **Earlier**; Earlier defaults to five minutes earlier and uses a time-only Watch picker for the exact hour and minute without presenting calendar fields. A selected clock time later than the current time is interpreted as the most recent occurrence on the previous day, which keeps near-midnight corrections intuitive. The chosen timer start remains separate from the command's actual tap time so backdating a timer cannot reorder queued commands or make a new action appear expired. The watch immediately applies an optimistic local update, writes the command to a durable outbox, and shows a pending-sync status. It first attempts an interactive message and falls back to background user-info transfer. The iPhone de-duplicates commands, rejects expired or stale timer mutations, applies them through the existing event mutation/timer services, saves SwiftData, and returns both an acknowledgement and refreshed state. Rejected commands restore the authoritative iPhone state and show an error on the watch.

Commands retain their Watch tap order across both interactive and background delivery, so a rapid sequence such as switch side, pause, then save cannot overtake itself. Pull to refresh requests a fresh iPhone snapshot when the phone is reachable. Ordinary iPhone event edits, profile switches, favorite changes, and category-visibility changes also publish through the same content-deduplicated state channel, avoiding redundant transfers and complication reloads when nothing visible changed.

`Pause` pauses the active timer and leaves it as a draft. A paused draft can be resumed, saved, or discarded after confirmation. `Save` stops and saves in one iPhone-side mutation using the exact watch tap time. Resume, discard, and nursing-side switching use the same stale-revision protection. The nursing timer card shows a live total plus independent Left and Right totals; switching banks the current side before the other side begins counting. Quick logs and timer starts carry a watch-generated event identifier so retrying an offline command cannot create a second event.

Watch complications are read-only cached surfaces. They never open or write the SwiftData store. Their timelines refresh when the companion receives authoritative state and otherwise age naturally until the next WatchConnectivity delivery.

Watch validation requires both an iPhone and paired Apple Watch signed with profiles that contain the shared App Group. Verify immediate reachable actions, simultaneous timers with isolated controls, several offline queued actions followed by reconnection, duplicate delivery, profile switching, Stop versus Stop & Save, nursing-side switching, stale timer rejection after an iPhone edit, complication refresh, and app relaunch with a non-empty outbox. Simulator builds require an installed watchOS simulator runtime in addition to the watchOS SDK.

## Action behavior

Timer data, event history, appointments, profiles, medications, structured health observations, predictions, routines, solids progress, allergen introduction state, guided meal plans, named recipe lists, category preferences, and settings remain in the app's SwiftData store. Widgets and Live Activities receive lightweight snapshots through the App Group. A logged solids meal is always a normal `CareEvent` with type `feed` and feed kind `solid`; linked per-food records add stable bundled-catalog identifiers, optional serving amounts, preference and reaction details, and allergen rollups without creating a second event history. The tracker provides status/reaction filters, multiple sorts, and a per-food chronological timeline that remains usable even after a custom catalog entry is deleted. Reports -> Summary -> Feeding provides date-range totals for solid meals, unique and newly introduced foods, allergen-meal observations, and suspected-reaction notes, with links back to the tracker and allergen workspace. Solid events in Reports day/list views open the solid meal detail rather than a generic feeding editor. Solids content is English-only and ships in the app rather than being fetched live.

Medication notifications carry only the identifiers and entered dose facts needed to reopen the app. Taken and Skipped actions are revalidated against the current active schedule before `MedicationService` applies them in the main app, so a delivered notification from an edited schedule cannot create a stale dose. Dose identity, the care timeline, supply history, profile scope, and Family Sync conflict handling remain consistent. Foreground reconciliation shares a bounded rolling notification budget across all active medication schedules after accounting for pending non-medication alerts; only requests accepted by iOS consume that budget. An active snooze survives unrelated reconciliation only while its occurrence is still valid and unlogged. Logging the dose, editing its schedule, or archiving the medication removes the initial, follow-up, and snoozed requests.

The Watch companion receives one profile-scoped upcoming-medication snapshot for the selected adult: the most recent unlogged occurrence within the prior 12 hours, otherwise the next occurrence within seven days. Watch Taken and Skipped commands are revalidated against the current profile, medication, active regimen, phase, schedule, and dose history before `MedicationService` applies them. Snooze is offered only near the due time for reminder-enabled regimens, creates a local iPhone notification for ten minutes after the Watch tap, and remains unavailable until that snooze fires. Commands queue offline, retain their original tap time, and cannot overwrite a dose already recorded on another device.

Solids is child-only. It is hidden for dog profiles and children younger than four months unless prior solids history or explicit activation exists, shows a readiness preview from four through five months, and becomes fully available from six months. Today surfaces readiness, a due or overdue meal plan, and due allergen follow-up exposures only for the active eligible child. Generic solids actions are ignored when a dog profile is active; they never switch profiles or present dog-specific solids UI.

When Family Sync is enabled, SwiftData remains the local cache and `CloudKitSharingService` synchronizes versioned `FamilyEntity` records in one shared CloudKit zone. Household records and only profiles explicitly set to **Share this profile with Family Sync** are exported; private profiles and their care events, appointments, structured appointment follow-ups, milestones, medications, dose records, health observations, photos, guide state, routines, and attention collaboration records are excluded. Importing a shared refresh preserves those private profiles locally. Each included object has an independent asset record plus an update timestamp; deletions are uploaded as tombstones. A lightweight root record carries the dataset checksum and schema version. Accepted caregivers read and write the same shared data, while widgets and Live Activities continue to refresh from each device's local cache.

An owner can disconnect only the current device or stop the iCloud share for everyone. A participant who leaves is removed from the CloudKit share. Owners see the accepted-caregiver count and receive a local activity alert when that membership changes. When CloudKit confirms that a participant's access was removed or the share ended, Little Windows stops shared syncing, keeps the already-downloaded data as a private local copy, shows an in-app recovery message, and posts an access-ended notification when notification permission is available. The user can then keep that copy or explicitly delete it from the device. Temporary network, service, and account-availability errors do not deactivate the share.

Settings resolves destructive Data actions from the store that is actually open, not only the pending preference. Private iCloud imports and full deletion explicitly warn that the change propagates to every device on that Apple Account. Family Sync owners receive the equivalent shared-caregiver warning; participants and devices whose ownership role cannot be confirmed cannot replace or erase the complete family dataset. Import and full deletion use a standard confirmation alert and create a local automatic recovery backup before changing the store.

On a new empty install, onboarding offers **Restore from iCloud** when the app has opened its Private iCloud Sync store. The flow verifies iCloud account availability and waits for SwiftData's automatic CloudKit import to deliver either a household or a care profile. It never queries or decodes SwiftData's private CloudKit records directly, creates replacement records, or treats sync as a point-in-time backup. If no app data arrives during the bounded wait, the user can retry, continue with a new setup, or import a JSON backup. Only data that completed a previous iCloud sync can return through this flow. Startup and later profile imports also repair repeated SwiftData profile rows carrying the same app-level profile ID. If someone continues through new setup before the original profile downloads, the app removes the newer onboarding shell only when it is empty, matches exactly one older profile identity, and that older profile already owns care data; it does not merge matching profiles when both own history.

New setup can create a household workspace without a care profile. In that mode, the root tab bar contains Today, Home, and Night Light; Today opens directly to its household summary. Adding the first active child, adult, or dog profile adds Reports and Care and switches Today to Care. Archiving the final active profile saves any open timer into history, removes profile-scoped alerts and care-only destinations, clears the active selection, preserves archived history, and returns Today to Home.

If neither the configured CloudKit store nor its local fallback can open, the app shows Data Recovery instead of terminating. Retry leaves the store untouched. Restore and empty-start options first copy the SQLite store, WAL/SHM sidecars, and SwiftData support directory into a dated unreadable-store archive, then open a new local-only store. Automatic backups are validated before the unreadable store is moved. Recovery clears stale widget and Live Activity timer state. Trace collection is handled separately from this user-facing recovery flow.

Local Family Sync mutations are serialized so newer timer states cannot be overtaken by an older upload. Synchronization uses a saved common baseline and a three-way, per-record merge, so offline changes to different objects are preserved and the newest `updatedAt` wins when two devices edit the same object. Initial share creation normally uploads one baseline snapshot; `FamilyEntity` assets then store only changed, new, or deleted records and are overlaid on that snapshot when another caregiver syncs. A snapshot above the safe CloudKit asset size falls back to small record- and byte-limited entity batches. Creation reports progress in Settings, applies explicit request/resource time limits, and removes its newly created zone if setup fails. Push-subscription verification continues after the invitation sheet is ready and is retried by launch/manual sync, so a slow push setup cannot block inviting a caregiver. Automatic launch checks compare lightweight root metadata before querying entities. While the app is active in shared mode, it checks that metadata every five seconds as a fallback for delayed CloudKit pushes. Foreground polling waits until the initial UI is usable and backs off after connection failures or when another sync is already running.

Family Sync schema version 5 requires the `FamilyEntity` record type to be created in the CloudKit development environment with `collection` (String), `entityID` (String), `payloadAsset` (Asset), `payloadChecksum` (String), `isDeleted` (Int(64)), and `entityUpdatedAt` (Date/Time), then deployed to production before a release build is distributed. Pre-release version-1 through version-4 shares should be stopped and recreated; there is intentionally no legacy share migration because the app has no production users. Private SwiftData CloudKit schema initialization must also include `CD_CareProfile`, `CD_CareEvent`, `CD_Medication`, `CD_MedicationRegimen`, `CD_MedicationSchedulePhase`, `CD_MedicationDoseRecord`, `CD_MedicationSupplyLog`, `CD_DoctorAppointment`, `CD_AppointmentFollowUp`, `CD_HouseholdAttentionAcknowledgement`, `CD_HouseholdAttentionClaim`, `CD_CaregiverHandoffNote`, `CD_FamilyCaregiverIdentity`, `CD_SolidFoodCatalogItem`, `CD_SolidsProfileState`, `CD_SolidFoodProgress`, `CD_SolidFoodEventItem`, `CD_SolidAllergenProgress`, `CD_PlannedSolidMeal`, `CD_PackingTrip`, `CD_TripTraveler`, `CD_PackingBag`, `CD_PackingItem`, `CD_TripItineraryChoiceGroup`, `CD_TripItineraryItem`, and `CD_TripItineraryLink`; `CD_CareProfile` includes optional `CD_birthDate`, `CD_adultRelationshipRawValue`, `CD_sharingScopeRawValue`, and `CD_ownerIdentifier`; `CD_CareEvent` includes `CD_diaperRash`, `CD_solidFoodDetailsJSON`, and `CD_healthObservationDetailsData`; `CD_MedicationRegimen` includes `CD_followUpRemindersEnabled`; `CD_MedicationDoseRecord` includes `CD_updatedAt`; `CD_MedicationSupplyLog` includes optional `CD_doseRecordID`; the existing solids, Food, Home, Trips, appointment, and attention fields must also remain present. Deploy the complete development schema before release.

Today action customization is stored per profile. Hidden care categories are excluded from Today quick actions and the Quick Log widget, but existing events remain in history, reports, backup/import, and summary snapshots.

Care event starts and ends capture concrete IANA time-zone identifiers. Appointments and Food & Home reminders also retain their selected zone. Automatic mode follows the device at each timestamp; Settings can apply a per-device manual override, and editors can override the relevant zones. Durations remain absolute elapsed time. Today, History, daily summaries, insights, widget snapshots, JSON/Family Sync datasets, and care-report exports use the recorded local day so travel does not reinterpret older entries in the device's new zone.

While a draft timer is active, Today disables other start actions for that event type and Smart Picks and the Quick Log widget omit them. Timer-start routes open the matching active timer when possible, and `EventTimerService` remains the final duplicate-start guard. A running sleep timer suppresses cached next-sleep predictions; Sleep day ahead shows the sleep already in progress and waits for its saved wake time before presenting a recalculated future window. Its usual-bedtime estimate uses the median first plausible night-sleep onset from each of the latest 28 usable nights, respecting the event's recorded local time and collapsing later fragments from the same sleep night.

System action buttons:

1. Append a precise, expiring pending action to the bounded App Group command queue.
2. Open Little Windows or deliver the action to a running app scene.
3. Execute the action through `EventTimerService` or the relevant app service.
4. Refresh widget snapshots, Live Activities, predictions, and notifications.

The queue preserves rapid actions instead of overwriting the previous command, de-duplicates identical URLs, and gives timer mutations a short expiration so an old Lock Screen tap cannot stop a newly started timer later.

Timer control commands include the time the user tapped the control. Stop writes an optimistic paused state to the shared snapshot and explicitly reloads the Active Timer widget before the app finishes opening. The app then fetches and saves only the targeted timer, republishes that authoritative timer snapshot, updates the matching Live Activity state, and defers broader prediction, notification, and sync reconciliation. A delayed duplicate is ignored when the timer has a newer in-app mutation, so an old Stop cannot override a later Resume.

Live Activity reconciliation keeps running and paused timer drafts visible, serializes ActivityKit lifecycle operations, and never retires an existing system surface until iOS accepts its replacement. A transient authorization or SwiftData read failure preserves the last valid surface instead of being interpreted as a completed timer; an ended activity is recreated during the next authoritative foreground reconciliation while the draft remains active. Standard Live Activities remain subject to iOS's system lifetime (up to eight hours active and up to four additional hours on the Lock Screen); the separately configurable Active Timer Lock Screen widget remains the persistent glanceable fallback for longer drafts.

Every in-app timer control uses the same split update. Pause, resume, reset, time corrections, nursing-side changes, save, and discard persist their focused mutation and update the cached timer UI immediately; a timer-only snapshot then updates or retires the active widget and Live Activity. Prediction generation, Today summary rebuilding, Watch publication, notifications, and broader reconciliation are coalesced and wait until the user has stopped interacting, so timer controls and editor dismissal cannot block Today scrolling.

This is intentional. The widget extension does not make unsafe concurrent edits to the full SwiftData history.

## Deep links

All routes use the `littlewindows://` scheme.

Home, Food, Settings, Night Light, and the unscoped Today route work without an active care profile. Care-only navigation, action, timer, event, report, appointment, routine, guide, milestone, memory, prediction, solids, medication, health-log, and quick-log routes present **Add a care profile** with context for the requested feature. Creating the first profile from that prompt resumes the app in Today > Care; dismissing it leaves the household-only destination unchanged.

Navigation routes:

```text
littlewindows://today
littlewindows://history
littlewindows://settings
littlewindows://insights
littlewindows://reports/feeding
littlewindows://medical
littlewindows://milestones
littlewindows://memories
littlewindows://care
littlewindows://age-guides
littlewindows://age-guide/{month}
littlewindows://puppy-guide
littlewindows://appointments
littlewindows://visits
littlewindows://routines
littlewindows://medications
littlewindows://appointment/{UUID}
littlewindows://appointment/{UUID}/notes
littlewindows://night-light
littlewindows://active-timer
littlewindows://prediction
littlewindows://event/{UUID}
littlewindows://food
littlewindows://care/solids
littlewindows://care/solids/guided
littlewindows://care/solids/database
littlewindows://care/solids/foods/{foodID}
littlewindows://care/solids/custom/{UUID}
littlewindows://care/solids/plan
littlewindows://care/solids/plan/{UUID}
littlewindows://care/solids/plan/{UUID}/log
littlewindows://care/solids/tracker
littlewindows://care/solids/tracker/{eventUUID}
littlewindows://care/solids/allergens
littlewindows://care/solids/allergens/{allergenID}
littlewindows://care/solids/recipes
littlewindows://care/solids/recipes/{recipeID}
littlewindows://food/todos
littlewindows://food/todos/{UUID}
littlewindows://food/quick-add
littlewindows://food/shopping
littlewindows://food/shopping/{UUID}
littlewindows://food/shopping/{UUID}/mode
littlewindows://food/trips
littlewindows://food/trips/{UUID}
littlewindows://food/trips/{tripUUID}/itinerary/{itemUUID}
littlewindows://food/inventory
littlewindows://food/inventory/{UUID}
littlewindows://food/meal-prep
littlewindows://food/meal-prep/{UUID}
littlewindows://food/returns
littlewindows://food/returns/{UUID}
littlewindows://food/stores/{UUID}
```

The earlier `littlewindows://food/solids/...` routes remain supported and redirect to the profile-scoped Care tab. Solids never appears for a selected dog profile, and unscoped routes do not automatically switch away from a dog. A `profile/{profileUUID}/...` route applies that explicit profile first, but still refuses Solids when the target is a dog or a child below the age gate.

Profile-scoped routes can prefix another route with a profile identifier:

```text
littlewindows://profile/{profileUUID}/today
littlewindows://profile/{profileUUID}/insights
littlewindows://profile/{profileUUID}/appointments
littlewindows://profile/{profileUUID}/food/solids
littlewindows://profile/{profileUUID}/food/solids/database
```

Timer/action routes:

```text
littlewindows://action/stop-active
littlewindows://action/stop/{UUID}
littlewindows://action/resume/{UUID}
littlewindows://action/switch-side/{UUID}
```

Quick-log routes:

```text
littlewindows://quick-log/sleep
littlewindows://quick-log/feed
littlewindows://quick-log/solids
littlewindows://quick-log/pumping
littlewindows://quick-log/child-potty
littlewindows://quick-log/repeat-last
littlewindows://quick-log/nursing-left
littlewindows://quick-log/nursing-right
littlewindows://quick-log/tummy-time
littlewindows://quick-log/story-time
littlewindows://quick-log/bath
littlewindows://quick-log/diaper
littlewindows://quick-log/temperature
littlewindows://quick-log/food
littlewindows://quick-log/water
littlewindows://quick-log/pee
littlewindows://quick-log/poop
littlewindows://quick-log/walk
littlewindows://quick-log/training
littlewindows://quick-log/medicine
```

Child quick-log routes use the active child profile when possible. Tummy Time and Story Time routes are rejected when the resolved profile is an adult or dog, and every timer start is revalidated against its profile before an event is inserted. Unscoped `quick-log/solids` does nothing for a dog or a child below the age gate; a profile-scoped version opens only for the explicitly targeted eligible child. Generic `quick-log/feed` becomes the dog Food editor when a dog is selected. `quick-log/pumping` starts a pumping timer, `quick-log/child-potty` creates a child potty log, and `quick-log/repeat-last` ignores hidden categories for the active profile.

Night-light routes:

```text
littlewindows://night-light
littlewindows://night-light/stop
littlewindows://night-light/diaper-change
littlewindows://night-light/nursing
littlewindows://night-light/soothing
littlewindows://night-light/reading
littlewindows://night-light/check-in
```

## App Intents and shortcuts

Timer and quick-log intents:

- `StartSleepTimerIntent`
- `StartNursingLeftIntent`
- `StartNursingRightIntent`
- `RepeatLastLogIntent`
- `LogFeedIntent`
- `LogMedicineIntent`
- `StartTummyTimeIntent`
- `StartStoryTimeIntent`
- `StartBathIntent`
- `LogDiaperIntent`
- `LogTemperatureIntent`
- `LogDogFoodIntent`
- `LogDogWaterIntent`
- `StartDogWalkIntent`
- `StopActiveTimerIntent`
- `StopTimerIntent`
- `ResumeTimerIntent`
- `SwitchNursingSideIntent`

Night-light and navigation intents:

- `OpenNightLightIntent`
- `StartDiaperChangeLightIntent`
- `StartNursingLightIntent`
- `StartSoothingLightIntent`
- `StopNightLightIntent`
- `OpenLittleWindowsIntent`

The `LittleWindowsShortcuts` provider exposes the iOS maximum of 10 promoted shortcuts to Shortcuts/Siri: start sleep, nurse left, nurse right, stop timer, repeat last, log solids, log medicine, log diaper, log dog food, and start dog walk. The generic Log Feed and Open Solids intents remain available in Shortcuts along with other unpromoted intents.

When no care profile is active, intents that open a care-only route hand off to the app's **Add a care profile** prompt rather than creating a placeholder profile or care event. Night Light and household navigation remain fully available.

## Notifications

Little Windows uses local notifications for:

- Sleep-window alerts, gated by notification permission, lead time, nap/bedtime toggles, and minimum confidence.
- Routine reminders for household or profile routines shown on Today.
- Appointment reminders with selectable lead times.
- Monthly guide reminders that fire at most once per monthly age guide.
- Trip packing reminders and final checks that open the matching trip. When any active item has a caregiver assignment, each device schedules only that device caregiver's unfinished, reminder-enabled assignments; trips without assignments retain shared trip reminders.
- Timed itinerary-item reminders with selectable lead times. They open the matching trip and item, and completed tasks no longer schedule an alert.
- Food & Home reminders created by the user for Home to-do lists, shopping, meal prep, returns, or custom home tasks.
- Family Sync shared activity alerts after CloudKit silent pushes wake the app, download the shared dataset, and detect another caregiver's care, appointment, milestone, packing, home to-do, shopping, inventory, meal-prep, return, or food-reminder change.
- Family Sync Home to-do list update alerts can be toggled separately from the broader shared activity alerts.
- Family Sync trip packing alerts can be toggled separately from the broader shared activity alerts, including a targeted alert when an item is newly assigned to the current device caregiver.
- Family Sync access-ended alerts when CloudKit confirms that a participant was removed or the share is no longer available. These lifecycle alerts are not suppressed by the shared-activity preference.

One-shot sleep, appointment, guide, planned-solids-meal, allergen-follow-up, and Food & Home alerts use absolute fire dates, so travel does not reinterpret an already-scheduled alert in the device's new zone. Solids meal alerts open the plan and allergen alerts open the relevant introduction detail. Per-profile sleep-alert state prevents one child's alert from suppressing another's. After the initial interaction window, and after an import, sync download, profile lifecycle change, or permission change, a coalesced central reconciler rebuilds widget snapshots, Live Activities, predictions, and all enabled notification categories while removing orphan requests. Foreground reconciliation is skipped when the last pass is recent and no local data changed. Food & Home shopping-list widgets refresh from lightweight App Group snapshots; the widget extension opens the app for edits rather than writing SwiftData directly.

Family Sync creates a CloudKit record-zone subscription for the shared family zone when a share is created or accepted. On the first shared sync of each app launch, it verifies the expected subscription still exists on the server and recreates missing or stale subscriptions. The CloudKit push itself is silent; Little Windows posts a local shared-activity notification only after the remote dataset imports and the local diff identifies a user-facing change. Push registration status and the most recent registration error are visible in **Settings -> iCloud & Sync -> Sync Diagnostics**. Shared activity alerts can be disabled from **Settings -> Family Sync -> Shared activity alerts**.

## Real-device testing

1. Install and launch Little Windows once.
2. Confirm the App Group entitlement is active for both targets.
3. In **Settings -> Apps -> Little Windows**, ensure Live Activities and notifications are allowed.
4. Long-press the Home Screen or Lock Screen and add the Little Windows widgets.
5. Start a Sleep timer, choose its type, and confirm the running timer editor opens immediately. Repeat with a non-sleep timer such as Nursing, Pumping, Activity, Walk, Rest, or Training. Dismiss an editor, then tap the active timer card and confirm it reopens.
6. Lock the phone and verify the Live Activity shows the live duration plus the original session start, such as **Sleeping since 9:12 AM**, right-aligned on the same row as the caregiver and other timer details.
7. On a Dynamic Island device, verify compact, minimal, and expanded presentations, including the start-time footer in the expanded presentation.
8. Tap **Stop**. The app should open and immediately stop the selected timer, and the Active Timer widget should stop counting and offer **Resume**. Save the timer and confirm the widget returns to its ready state.
9. With Little Window Alerts enabled at **10 minutes before**, start a Sleep timer and confirm its pending alert is removed. Stop and save the timer, then confirm the newly predicted sleep alert is scheduled without toggling alerts off and on.
10. For nursing, confirm both Total and the active Left or Right duration count live, then tap **Switch** and confirm the side label and side duration change while the total is retained.
11. Log or start child feed, pumping, child potty, diaper, temperature, and activity actions from Today, then confirm the same details appear in History and the Today Summary widget where applicable.
12. Customize Today actions for a child profile, hide one category, refresh the Quick Log widget, and confirm hidden categories and hidden-category repeat sources are omitted only for that profile.
13. Long-press a Today smart pick, pin it, refresh the Quick Log widget, and confirm the pinned action appears first with a pin indicator.
14. Run the Repeat Last Log shortcut or widget action after a repeatable visible log and confirm the app creates a new completed log at the current time.
15. Start a Sleep or Nursing timer, then confirm Today, care routines, Smart Picks, and the Quick Log widget do not offer another start for that same event type. Confirm a different timer type remains available.
16. Open Routines from Today or `littlewindows://routines`, create or edit a routine, verify the explicit **Done** button dismisses the manager, and confirm routine reminders schedule when enabled.
17. Add a Control Center control and verify it opens the app and applies the intended action.
18. Start diaper-change and soothing night-light presets from shortcuts or controls.
19. Create an appointment and verify selected reminder lead times.
20. Enable monthly guide reminders and verify scheduling after guide state changes.
21. Create a Food & Home reminder and verify it opens the relevant Food screen or item.
22. Create a trip from Home > Trips with a trip-local adult and linked sample child, adult, or dog profile. In Itinerary, add timed and flexible entries, an idea without a day, a booked flight with origin/destination time zones and confirmation details, a task with an assignee and reminder, external links, and a weather-dependent option group; select one option and verify directions and the per-day weather context. In Packing, confirm the generated list reflects the duration, laundry, travel mode, activities, and traveler types. Assign items to bags and different caregivers, confirm each device's Settings caregiver name sees its own remaining count and receives only its own enabled reminders, then pack from both devices and verify packed-by attribution, progress, shopping handoff, and JSON backup/import. Duplicate the trip and confirm itinerary dates shift while confirmations, completion, selection, and reminders reset. Archive a trip and confirm both workspaces become read-only. Finally, delete the trip, confirm it returns to Trips and cancels itinerary and packing reminders, and verify items already handed off to Shopping remain available.
23. On a signed WeatherKit-enabled device, create a multi-destination trip with one stop inside the forecast window and a later stop outside it. Verify the first destination opens an in-app daily forecast with high/low temperature, rain chance, UV, coverage, packing considerations, and a visible last-updated timestamp. Verify the later stop explains that its forecast will appear automatically, and foregrounding or manually refreshing after its dates enter the window loads that forecast. Confirm suggestions can be added without duplication and the add button's plus icon remains visible in light and dark appearance. Confirm the compact Apple Weather mark is legible, tapping it does nothing, and **About weather data** presents the supplied legal attribution inside the app.
24. With two signed devices in the same Family Sync share, keep both apps open, then start, stop, and save a timer on one device. Verify the other device reflects each state within one foreground refresh cycle (normally about five seconds, plus CloudKit network time). In a Home to-do list, confirm the assignment menu offers yourself, accepted share caregivers, and Unassigned; turn off Family Sync and confirm only yourself and Unassigned remain available. Then background the second device, make a shared care, Home to-do assignment, packing, or shopping-list change, and verify its shared-activity alert opens the relevant Little Windows screen.
25. With Family Sync enabled, launch the app on a throttled or unreliable connection. Confirm Today and Night Light remain immediately scrollable and tappable while the sync status updates later; restore connectivity and confirm pending changes eventually sync.
26. In Settings > Time Zone, confirm Automatic shows the detected zone and that Manual override can search for and select another zone. Start a one-hour timer in one zone, switch the simulator/device zone, then stop and save it. Confirm the duration remains one hour, both zone abbreviations appear when appropriate, and the entry remains on its recorded local calendar day. Edit both zones and verify JSON backup/import and CSV care report export preserve them.
27. Add the Shopping List and Food Quick Add widgets, then verify item counts update after checking, reactivating, or adding shopping-list items in the app. With a child selected, use **Log Solids** from Food Quick Add and confirm it opens the solids editor. Select a dog and confirm the widget no longer displays **Log Solids**.
28. With two signed devices using different Apple Accounts, remove the participant from the owner's iCloud share sheet. Verify the participant stops syncing, receives the access-ended alert, and can keep or delete its downloaded local copy. Repeat with **Stop Sharing for Everyone**, and verify the owner returns to private iCloud Sync while each participant enters the same recovery flow. Also verify **Turn Off on This Device** leaves the owner's CloudKit share active for other caregivers.
29. In each sync mode, open Settings > Data and verify import/full-deletion copy identifies the actual scope. Confirm a Family Sync participant cannot perform either bulk action. As an owner, confirm the standard alert offers Cancel and the correctly scoped destructive action, and that an automatic recovery backup is retained before the change syncs.
30. On a disposable simulator store, make the SwiftData store unreadable and relaunch. Verify Data Recovery appears without terminating, Retry does not alter the files, and restore/start-empty preserves the store artifacts before opening a local-only copy. Do not perform this test on a physical device containing personal data.
31. With a six-month-or-older child selected, open Solids and verify the 535-food database, stage-based first-100 path, seven-day guided schedule, swap/shift controls, 424-recipe library, recipe filters and named lists, food-to-recipe links, technique photography and auto-playing preparation walkthroughs, meal plan reminders, inventory-aware shopping handoff, tracker filters, and per-food chronological history. Log two foods in one meal with a serving amount and preference on each and a suspected reaction on only one; verify the meal detail and allergen screen keep amount, symptoms, severity, timing, response, and follow-up attached to the correct food. From an allergen page, plan the remaining introduction portions, verify the precise step and serving guidance reach the log editor, and confirm only explicitly checked portions advance the three-step introduction. Complete three separate tolerated exposures and verify unique-meal counts, safe recipe suggestions, rotation planning, and the Today follow-up prompt. Open **View feeding report** and verify Reports -> Summary -> Feeding shows period-correct solid meals, unique foods, new foods, allergen exposures, and reaction notes; verify its tracker/allergen links and that tapping a solid event in Day/List returns to solid meal detail. Create a custom food with age, preparation, safety, allergen, and photo metadata; mark it want-to-try/favorite, plan it, add it to shopping and inventory flows, log its allergen metadata, reuse it, delete the catalog entry, and confirm its historical timeline remains accessible. Verify JSON backup/import plus Family Sync preserve all solids data and named recipe lists.
32. Select a dog and confirm Solids is absent from Food & Home. Confirm generic solids links and **Log Solids** from Shortcuts do nothing and do not change profiles. Select a one-month-old child and confirm Solids remains absent. At four to five months verify only the readiness preview appears; at six months verify the full section and Today prompt. With a child selected, run **Log Solids** from Shortcuts and confirm it opens the child solids editor.
33. On a signed disposable device or simulator signed into the same Apple Account as an existing Private iCloud Sync install, reinstall Little Windows and choose **Restore from iCloud** during onboarding. Keep the app open and verify onboarding closes after synced profiles arrive, their history follows, and no duplicate starter profile is created. Repeat by continuing through new setup before the original profile arrives, using the same profile identity, and verify the newer empty setup profile disappears after the historical profile syncs. Confirm two matching profiles are preserved if both contain history. Repeat with no iCloud account and with an account that has no Little Windows data; verify the app explains the condition and leaves the empty store unchanged. Do not use destructive reset routes on a physical device containing personal data.
34. On an empty disposable simulator, choose **Home, Food & Night Light** during onboarding. Verify Today opens the Home summary and the tab bar contains only Today, Home, and Night Light. Open Settings, Home, Food, and a Night Light preset and confirm each works without a profile. Open a care quick-log URL or shortcut and verify **Add a care profile** appears without creating care data. Add a child, adult, or dog from the prompt and verify Today opens in Care with Reports and Care restored. Archive that only active profile and verify the household-only tabs return while the archived profile and history remain available in Settings.
35. Add an adult profile for yourself and another for a loved one, leaving both private. Verify adult Today and widget actions, appointments, medication schedules, as-needed guardrails, dose corrections/deletion, dose and supply history, refill state, symptoms, core vitals, adult Reports trends, the exported current medication plan, and adult milestone suggestions. Confirm child sleep predictions, pediatric growth references, solids, and age guides do not appear for either adult.
36. Opt only one adult profile into Family Sync. On a second signed device, verify that profile and its events, appointments, medications, doses, vitals, milestones, photos, and profile routines sync while the private adult never appears. Log the same scheduled dose differently while both devices are offline, reconnect, and confirm the newest status wins without duplicate timeline or supply entries. Sync another change back from the participant and confirm the owner's private adult and records remain intact. Turn on medication reminders and verify initial delivery, optional 30-minute follow-up, Log Taken, Log Skipped, snooze, the shared rolling-window budget with several medications, travel-time behavior, and cancellation after logging or archiving the medication. On a paired Watch, select the adult profile, confirm the nearest unlogged scheduled dose appears, and exercise Taken, Skipped, and 10-minute Snooze both while reachable and temporarily disconnected; verify the iPhone applies queued actions once, advances the card, and rejects a stale conflicting dose.
37. With three Family Sync caregivers and at least one private profile, create structured appointment follow-ups plus due medication, routine, low-stock, return, trip, planned-solids, and allergen items. Verify Today > Home keeps one Needs Attention section, shows the highest-priority five with View all, and labels each row with its source, profile or household scope, due state, and responsibility. Have one caregiver mark a follow-up seen without assigning it, then assign and reassign it between the other two caregivers; verify every device shows all acknowledgements and exactly one responsible caregiver. Add a handoff note and confirm only shared-profile or household activity appears under Since you last checked, Needs your acknowledgement, and Next up for you. Confirm the private profile has no acknowledgement, assignment, or handoff controls. Snooze an item on one device and verify it moves to the local Snoozed section with its return time, remains visible in Needs Attention on the other devices, and can be restored immediately with Unsnooze. Let another snooze expire and confirm it returns automatically, then complete it from its source and verify the queue updates everywhere.

Live Activities, Dynamic Island, Control Center controls, App Groups, CloudKit sync, and notification delivery are best validated on a physical iPhone. Simulator support varies by runtime and does not fully reproduce those surfaces.

Simulator app launches use the local validation store by default so unsigned simulator builds do not initialize the CloudKit-backed SwiftData store. Set `LW_CLOUDKIT_SYNC_SMOKE` when intentionally running the manual CloudKit simulator smoke test.

Family Sync also needs two signed physical devices or simulator/device installs with different Apple Accounts. Verify share creation, invitation acceptance, start/stop timer handoff, offline edits that sync later, and local widget/Live Activity refresh after synced changes arrive.

## Apple references

- [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)
- [Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [App Intents](https://developer.apple.com/documentation/appintents)
