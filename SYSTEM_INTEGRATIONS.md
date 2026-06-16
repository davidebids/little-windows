# Little Windows System Integrations

Little Windows includes a WidgetKit extension, Live Activity and Dynamic Island UI, App Intents, deep links, and iOS 18 Control Center controls.

## Included surfaces

- Active Timer widget: small, medium, Lock Screen rectangular, and Lock Screen inline
- Next Sleep Window widget: small, medium, and Lock Screen rectangular
- Today Summary widget: medium
- Quick Log widget: medium
- Live Activity with Dynamic Island compact, minimal, and expanded presentations
- App Shortcuts for starting sleep, starting Left or Right nursing, and stopping the primary timer
- iOS 18 Control Center controls for sleep, Left nursing, Right nursing, tummy time, and stop

The primary Live Activity priority is Sleep, Nursing, Feed, Tummy Time, Reading, then Bath. When another timer is active, the surface displays a `+1 more active` count.

## Xcode capability setup

The source and entitlements use this App Group:

```text
group.com.debidia.LittleWindows
```

For both the `LittleWindows` and `LittleWindowsWidgets` targets:

1. Open **Signing & Capabilities**.
2. Select the same Apple Developer team.
3. Add the **App Groups** capability.
4. Enable `group.com.debidia.LittleWindows`.
5. Let Xcode regenerate both provisioning profiles.

If Xcode reports that the App Group is unavailable for a Personal Team, a paid Apple Developer team is required for the shared widget/action state. The main app still runs without the shared group, but widgets cannot reliably read its timer snapshots and system buttons should be treated as open-app fallbacks.

The app target already includes:

- `NSSupportsLiveActivities = YES`
- the `littlewindows` URL scheme
- `LittleWindows/LittleWindows.entitlements`

The extension target already includes:

- the WidgetKit extension point
- `LittleWindowsWidgets/LittleWindowsWidgets.entitlements`
- bundle identifier `com.debidia.LittleWindows.widgets`

## Action behavior

Timer data remains in the app's SwiftData store. Widgets and Live Activities receive lightweight snapshots through the App Group.

System action buttons:

1. Save a precise pending action in the App Group.
2. Open Little Windows.
3. Execute the action through `EventTimerService`.
4. Refresh the widget snapshot, Live Activity, prediction, and notification.

This is intentional. The widget extension does not make unsafe concurrent edits to the full SwiftData history.

## Deep links

Supported routes:

```text
littlewindows://today
littlewindows://active-timer
littlewindows://event/{UUID}
littlewindows://prediction
littlewindows://action/stop-active
littlewindows://action/stop/{UUID}
littlewindows://action/switch-side/{UUID}
littlewindows://quick-log/sleep
littlewindows://quick-log/nursing-left
littlewindows://quick-log/nursing-right
littlewindows://quick-log/diaper
littlewindows://quick-log/tummy-time
```

## Real-device testing

1. Install and launch Little Windows once.
2. In **Settings → Apps → Little Windows**, ensure Live Activities are allowed.
3. Long-press the Home Screen or Lock Screen and add the Little Windows widgets.
4. Start a Sleep or Nursing timer.
5. Lock the phone and verify the Live Activity.
6. On a Dynamic Island device, verify compact and expanded presentations.
7. Tap **Stop**. The app opens and immediately stops the selected timer.
8. For nursing, tap **Switch** and confirm the active side changes while elapsed time is retained.

Live Activities are best validated on a physical iPhone. Simulator support varies by runtime and does not fully reproduce Lock Screen or Dynamic Island behavior.

## Apple references

- [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)
- [Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [App Intents](https://developer.apple.com/documentation/appintents)
