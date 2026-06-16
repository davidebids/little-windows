# Little Windows System Integrations

Little Windows integrates with WidgetKit, ActivityKit, App Intents, App Shortcuts, deep links, local notifications, App Groups, and iOS 18 Control Center controls. The app remains the single writer for SwiftData history; extensions and system surfaces pass commands back to the app and read lightweight snapshots.

## Included surfaces

- Active Timer widget: small, medium, Lock Screen rectangular, and Lock Screen inline.
- Next Sleep Window widget: small, medium, and Lock Screen rectangular.
- Today Summary widget: medium.
- Quick Log widget: medium.
- Live Activity with Lock Screen, Dynamic Island compact, Dynamic Island minimal, and Dynamic Island expanded presentations.
- App Intents for timer control, quick logging, app navigation, and night-light presets.
- App Shortcuts for starting sleep, starting Left or Right nursing, stopping the primary timer, opening the night light, and starting common night-light presets.
- iOS 18 Control Center controls for sleep, Left nursing, Right nursing, tummy time, stop timer, diaper-change light, and soothing light.
- Local notifications for sleep windows, appointment reminders, and monthly guide reminders.

The primary Live Activity priority is Sleep, Nursing, Feed, Tummy Time, Reading, then Bath. When another timer is active, the surface displays a `+1 more active` count.

## Xcode capability setup

The source and entitlements currently use this App Group:

```text
group.com.debidia.LittleWindows
```

For both the `LittleWindows` and `LittleWindowsWidgets` targets:

1. Open **Signing & Capabilities**.
2. Select the same Apple Developer team.
3. Add the **App Groups** capability.
4. Enable `group.com.debidia.LittleWindows`.
5. Let Xcode regenerate both provisioning profiles.

If Xcode reports that the App Group is unavailable for a Personal Team, a paid Apple Developer team is required for reliable shared widget/action state. The main app still runs without the shared group, but widgets cannot reliably read timer snapshots and system buttons should be treated as open-app fallbacks.

The app target includes:

- `NSSupportsLiveActivities = YES`
- the `littlewindows` URL scheme
- `LittleWindows/LittleWindows.entitlements`

The extension target includes:

- the WidgetKit extension point
- `LittleWindowsWidgets/LittleWindowsWidgets.entitlements`
- bundle identifier `com.debidia.LittleWindows.widgets`

## Action behavior

Timer data, event history, appointments, profiles, predictions, and settings remain in the app's SwiftData store. Widgets and Live Activities receive lightweight snapshots through the App Group.

System action buttons:

1. Save a precise pending action in the App Group.
2. Open Little Windows or deliver the action to a running app scene.
3. Execute the action through `EventTimerService` or the relevant app service.
4. Refresh widget snapshots, Live Activities, predictions, and notifications.

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
littlewindows://appointment/{UUID}
littlewindows://appointment/{UUID}/notes
littlewindows://night-light
littlewindows://active-timer
littlewindows://prediction
littlewindows://event/{UUID}
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
littlewindows://quick-log/medicine
```

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
- `StartTummyTimeIntent`
- `StartStoryTimeIntent`
- `StartBathIntent`
- `LogDiaperIntent`
- `LogTemperatureIntent`
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

The `LittleWindowsShortcuts` provider exposes a smaller curated set to Shortcuts/Siri: start sleep, nurse left, nurse right, stop timer, open night light, diaper light, and soothing light.

## Notifications

Little Windows uses local notifications for:

- Sleep-window alerts, gated by notification permission, lead time, nap/bedtime toggles, and minimum confidence.
- Appointment reminders with selectable lead times.
- Monthly guide reminders that fire at most once per monthly age guide.

Notification scheduling is refreshed after relevant event mutations, prediction updates, appointment changes, and guide-read-state changes.

## Real-device testing

1. Install and launch Little Windows once.
2. Confirm the App Group entitlement is active for both targets.
3. In **Settings -> Apps -> Little Windows**, ensure Live Activities and notifications are allowed.
4. Long-press the Home Screen or Lock Screen and add the Little Windows widgets.
5. Start a Sleep or Nursing timer.
6. Lock the phone and verify the Live Activity.
7. On a Dynamic Island device, verify compact, minimal, and expanded presentations.
8. Tap **Stop**. The app should open and immediately stop the selected timer.
9. For nursing, tap **Switch** and confirm the active side changes while elapsed time is retained.
10. Add a Control Center control and verify it opens the app and applies the intended action.
11. Start diaper-change and soothing night-light presets from shortcuts or controls.
12. Create an appointment and verify selected reminder lead times.
13. Enable monthly guide reminders and verify scheduling after guide state changes.

Live Activities, Dynamic Island, Control Center controls, App Groups, and notification delivery are best validated on a physical iPhone. Simulator support varies by runtime and does not fully reproduce those surfaces.

## Apple references

- [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)
- [Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [App Intents](https://developer.apple.com/documentation/appintents)
