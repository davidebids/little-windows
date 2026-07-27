# Little Windows System Integrations

Little Windows integrates with WidgetKit, ActivityKit, App Intents, App Shortcuts, deep links, local notifications, App Groups, and iOS 18 Control Center controls. The app remains the single writer for SwiftData history; extensions and system surfaces pass commands back to the app and read lightweight snapshots.

## Included surfaces

- Active Timer widget: small, medium, Lock Screen rectangular, and Lock Screen inline.
- Next Sleep Window widget: small, medium, and Lock Screen rectangular.
- Today Summary widget: medium, including unified child care summary metrics for sleep, feeding, nursing, pumping, diapers, potty, medicine, temperature, growth, and activities when present.
- Quick Log widget: medium, backed by profile-scoped ranked smart actions, hidden-category preferences, and user-pinned actions from Today.
- Shopping List widget: small and medium, backed by the Food & Home shopping snapshot.
- Food Quick Add widget: medium, opens quick add and usual shopping lists in the app.
- Live Activity with Lock Screen, Dynamic Island compact, Dynamic Island minimal, and Dynamic Island expanded presentations.
- App Intents for timer control, quick logging, app navigation, and night-light presets.
- App Shortcuts for repeat-last logging, high-frequency quick logging, timer control, and dog care.
- iOS 18 Control Center controls for sleep, Left nursing, Right nursing, tummy time, stop timer, diaper-change light, and soothing light.
- Local notifications for sleep windows, routine reminders, appointment reminders, monthly guide reminders, and user-created Food & Home reminders.

The primary Live Activity priority is Sleep, Nursing, Pumping, Feed, Tummy Time, Reading, then Bath. When another timer is active, the surface displays a `+1 more active` count.
Nursing timer widgets and expanded Live Activity presentations show both the live total duration and the cumulative duration for the active Left or Right side.

## Xcode capability setup

The source and entitlements currently use this App Group:

```text
group.com.debidia.LittleWindows
```

The app target also uses this CloudKit container for SwiftData private database sync and Family Sync shared records:

```text
iCloud.com.debidia.LittleWindows
```

For both the `LittleWindows` and `LittleWindowsWidgets` targets:

1. Open **Signing & Capabilities**.
2. Select the same Apple Developer team.
3. Add the **App Groups** capability.
4. Enable `group.com.debidia.LittleWindows`.
5. Let Xcode regenerate both provisioning profiles.

For the `LittleWindows` app target only:

1. Add the **iCloud** capability.
2. Enable **CloudKit**.
3. Select or create `iCloud.com.debidia.LittleWindows`.
4. Keep `LittleWindows/LittleWindows.entitlements` connected to the target.
5. Use CloudKit Dashboard to inspect the development schema and deploy it to production before TestFlight/App Store use.
6. For Family Sync testing, create a share from Settings > Family Sync on the owner's device, accept the iCloud invitation on a second Apple Account, and verify both devices can write care data.

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

## Action behavior

Timer data, event history, appointments, profiles, predictions, routines, category preferences, and settings remain in the app's SwiftData store. Widgets and Live Activities receive lightweight snapshots through the App Group.

When Family Sync is enabled, SwiftData remains the local cache and `CloudKitSharingService` synchronizes versioned `FamilyEntity` records in one shared CloudKit zone. Each care event, profile, appointment, custom solid food, photo attachment, reminder, list item, and related object has an independent asset record plus an update timestamp; deletions are uploaded as tombstones. A lightweight root record carries the dataset checksum and schema version. Accepted caregivers read and write the same shared data, while widgets and Live Activities continue to refresh from each device's local cache.

An owner can disconnect only the current device or stop the iCloud share for everyone. A participant who leaves is removed from the CloudKit share. Owners see the accepted-caregiver count and receive a local activity alert when that membership changes. When CloudKit confirms that a participant's access was removed or the share ended, Little Windows stops shared syncing, keeps the already-downloaded data as a private local copy, shows an in-app recovery message, and posts an access-ended notification when notification permission is available. The user can then keep that copy or explicitly delete it from the device. Temporary network, service, and account-availability errors do not deactivate the share.

Settings resolves destructive Data actions from the store that is actually open, not only the pending preference. Private iCloud imports and full deletion explicitly warn that the change propagates to every device on that Apple Account. Family Sync owners receive the equivalent shared-caregiver warning; participants and devices whose ownership role cannot be confirmed cannot replace or erase the complete family dataset. Import and full deletion use a standard confirmation alert and create a local automatic recovery backup before changing the store.

If neither the configured CloudKit store nor its local fallback can open, the app shows Data Recovery instead of terminating. Retry leaves the store untouched. Restore and empty-start options first copy the SQLite store, WAL/SHM sidecars, and SwiftData support directory into a dated unreadable-store archive, then open a new local-only store. Automatic backups are validated before the unreadable store is moved. Recovery clears stale widget and Live Activity timer state. Trace collection is handled separately from this user-facing recovery flow.

Local Family Sync mutations are serialized so newer timer states cannot be overtaken by an older upload. Synchronization uses a saved common baseline and a three-way, per-record merge, so offline changes to different objects are preserved and the newest `updatedAt` wins when two devices edit the same object. Only changed entity assets and deletion tombstones are uploaded. Automatic launch checks compare lightweight root metadata before querying entities. While the app is active in shared mode, it checks that metadata every five seconds as a fallback for delayed CloudKit pushes. Foreground polling waits until the initial UI is usable and backs off after connection failures or when another sync is already running.

Family Sync schema version 3 requires the `FamilyEntity` record type and its fields to be created in the CloudKit development environment and deployed to production before a release build is distributed. Pre-release version-1 and version-2 shares should be stopped and recreated; there is intentionally no legacy share migration because the app has no production users. Private SwiftData CloudKit schema initialization must also include the new `CD_SolidFoodCatalogItem` record type and be deployed before release.

Today action customization is stored per profile. Hidden care categories are excluded from Today quick actions and the Quick Log widget, but existing events remain in history, reports, backup/import, and summary snapshots.

Care event starts and ends capture concrete IANA time-zone identifiers. Appointments and Food & Home reminders also retain their selected zone. Automatic mode follows the device at each timestamp; Settings can apply a per-device manual override, and editors can override the relevant zones. Durations remain absolute elapsed time. Today, History, daily summaries, insights, widget snapshots, JSON/Family Sync datasets, and care-report exports use the recorded local day so travel does not reinterpret older entries in the device's new zone.

While a draft timer is active, Today disables other start actions for that event type and Smart Picks and the Quick Log widget omit them. Timer-start routes open the matching active timer when possible, and `EventTimerService` remains the final duplicate-start guard.

System action buttons:

1. Append a precise, expiring pending action to the bounded App Group command queue.
2. Open Little Windows or deliver the action to a running app scene.
3. Execute the action through `EventTimerService` or the relevant app service.
4. Refresh widget snapshots, Live Activities, predictions, and notifications.

The queue preserves rapid actions instead of overwriting the previous command, de-duplicates identical URLs, and gives timer mutations a short expiration so an old Lock Screen tap cannot stop a newly started timer later.

Timer control commands include the time the user tapped the control. The app fetches and saves only the targeted timer before opening its editor, immediately updates the lightweight widget and matching Live Activity state, and defers broader prediction, notification, and sync reconciliation. A delayed duplicate is ignored when the timer has a newer in-app mutation, so an old Stop cannot override a later Resume.

This is intentional. The widget extension does not make unsafe concurrent edits to the full SwiftData history.

## Deep links

All routes use the `littlewindows://` scheme.

Navigation routes:

```text
littlewindows://today
littlewindows://history
littlewindows://settings
littlewindows://insights
littlewindows://medical
littlewindows://milestones
littlewindows://memories
littlewindows://age-guides
littlewindows://age-guide/{month}
littlewindows://puppy-guide
littlewindows://appointments
littlewindows://visits
littlewindows://routines
littlewindows://appointment/{UUID}
littlewindows://appointment/{UUID}/notes
littlewindows://night-light
littlewindows://active-timer
littlewindows://prediction
littlewindows://event/{UUID}
littlewindows://food
littlewindows://food/todos
littlewindows://food/todos/{UUID}
littlewindows://food/quick-add
littlewindows://food/shopping
littlewindows://food/shopping/{UUID}
littlewindows://food/shopping/{UUID}/mode
littlewindows://food/inventory
littlewindows://food/inventory/{UUID}
littlewindows://food/meal-prep
littlewindows://food/meal-prep/{UUID}
littlewindows://food/returns
littlewindows://food/returns/{UUID}
littlewindows://food/stores/{UUID}
```

Profile-scoped routes can prefix another route with a profile identifier:

```text
littlewindows://profile/{profileUUID}/today
littlewindows://profile/{profileUUID}/insights
littlewindows://profile/{profileUUID}/appointments
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

Child quick-log routes use the active child profile when possible. `quick-log/pumping` starts a pumping timer, `quick-log/child-potty` creates a child potty log, and `quick-log/repeat-last` ignores hidden categories for the active profile.

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

The `LittleWindowsShortcuts` provider exposes the iOS maximum of 10 promoted shortcuts to Shortcuts/Siri: start sleep, nurse left, nurse right, stop timer, repeat last, log feed, log medicine, log diaper, log dog food, and start dog walk. Other intents remain available to widgets, controls, deep links, and future shortcut curation.

## Notifications

Little Windows uses local notifications for:

- Sleep-window alerts, gated by notification permission, lead time, nap/bedtime toggles, and minimum confidence.
- Routine reminders for household or profile routines shown on Today.
- Appointment reminders with selectable lead times.
- Monthly guide reminders that fire at most once per monthly age guide.
- Food & Home reminders created by the user for Home to-do lists, shopping, meal prep, returns, or custom home tasks.
- Family Sync shared activity alerts after CloudKit silent pushes wake the app, download the shared dataset, and detect another caregiver's care, appointment, milestone, home to-do, shopping, inventory, meal-prep, return, or food-reminder change.
- Family Sync Home to-do list update alerts can be toggled separately from the broader shared activity alerts.
- Family Sync access-ended alerts when CloudKit confirms that a participant was removed or the share is no longer available. These lifecycle alerts are not suppressed by the shared-activity preference.

One-shot sleep, appointment, guide, and Food & Home alerts use absolute fire dates, so travel does not reinterpret an already-scheduled alert in the device's new zone. Per-profile sleep-alert state prevents one child's alert from suppressing another's. After the initial interaction window, and after an import, sync download, profile lifecycle change, or permission change, a coalesced central reconciler rebuilds widget snapshots, Live Activities, predictions, and all enabled notification categories while removing orphan requests. Foreground reconciliation is skipped when the last pass is recent and no local data changed. Food & Home shopping-list widgets refresh from lightweight App Group snapshots; the widget extension opens the app for edits rather than writing SwiftData directly.

Family Sync creates a CloudKit record-zone subscription for the shared family zone when a share is created or accepted, and refreshes it during shared sync. The CloudKit push itself is silent; Little Windows posts a local shared-activity notification only after the remote dataset imports and the local diff identifies a user-facing change. These alerts can be disabled from **Settings -> Family Sync -> Shared activity alerts**.

## Real-device testing

1. Install and launch Little Windows once.
2. Confirm the App Group entitlement is active for both targets.
3. In **Settings -> Apps -> Little Windows**, ensure Live Activities and notifications are allowed.
4. Long-press the Home Screen or Lock Screen and add the Little Windows widgets.
5. Start a Sleep timer, choose its type, and confirm the running timer editor opens immediately. Repeat with a non-sleep timer such as Nursing, Pumping, Activity, Walk, Rest, or Training. Dismiss an editor, then tap the active timer card and confirm it reopens.
6. Lock the phone and verify the Live Activity.
7. On a Dynamic Island device, verify compact, minimal, and expanded presentations.
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
22. With two signed devices in the same Family Sync share, keep both apps open, then start, stop, and save a timer on one device. Verify the other device reflects each state within one foreground refresh cycle (normally about five seconds, plus CloudKit network time). Then background the second device, make a shared care or shopping-list change, and verify its shared-activity alert opens the relevant Little Windows screen.
23. With Family Sync enabled, launch the app on a throttled or unreliable connection. Confirm Today and Night Light remain immediately scrollable and tappable while the sync status updates later; restore connectivity and confirm pending changes eventually sync.
24. In Settings > Time Zone, confirm Automatic shows the detected zone and that Manual override can search for and select another zone. Start a one-hour timer in one zone, switch the simulator/device zone, then stop and save it. Confirm the duration remains one hour, both zone abbreviations appear when appropriate, and the entry remains on its recorded local calendar day. Edit both zones and verify JSON backup/import and CSV care report export preserve them.
25. Add the Shopping List and Food Quick Add widgets, then verify item counts update after checking, reactivating, or adding shopping-list items in the app.
26. With two signed devices using different Apple Accounts, remove the participant from the owner's iCloud share sheet. Verify the participant stops syncing, receives the access-ended alert, and can keep or delete its downloaded local copy. Repeat with **Stop Sharing for Everyone**, and verify the owner returns to private iCloud Sync while each participant enters the same recovery flow. Also verify **Turn Off on This Device** leaves the owner's CloudKit share active for other caregivers.
27. In each sync mode, open Settings > Data and verify import/full-deletion copy identifies the actual scope. Confirm a Family Sync participant cannot perform either bulk action. As an owner, confirm the standard alert offers Cancel and the correctly scoped destructive action, and that an automatic recovery backup is retained before the change syncs.
28. On a disposable simulator store, make the SwiftData store unreadable and relaunch. Verify Data Recovery appears without terminating, Retry does not alter the files, and restore/start-empty preserves the store artifacts before opening a local-only copy. Do not perform this test on a physical device containing personal data.
29. Add a solid feeding, select several visual food tiles, and verify general reaction, common-allergen exposure, and observed sensitivity can be recorded independently. Create a custom food with a photo, reuse it in another feeding, edit or delete it from its tile menu, and verify JSON backup/import plus Family Sync preserve the custom food and photo.

Live Activities, Dynamic Island, Control Center controls, App Groups, CloudKit sync, and notification delivery are best validated on a physical iPhone. Simulator support varies by runtime and does not fully reproduce those surfaces.

Simulator app launches use the local validation store by default so unsigned simulator builds do not initialize the CloudKit-backed SwiftData store. Set `LW_CLOUDKIT_SYNC_SMOKE` when intentionally running the manual CloudKit simulator smoke test.

Family Sync also needs two signed physical devices or simulator/device installs with different Apple Accounts. Verify share creation, invitation acceptance, start/stop timer handoff, offline edits that sync later, and local widget/Live Activity refresh after synced changes arrive.

## Apple references

- [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)
- [Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [App Intents](https://developer.apple.com/documentation/appintents)
