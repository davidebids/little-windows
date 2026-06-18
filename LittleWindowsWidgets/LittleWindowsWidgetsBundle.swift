import SwiftUI
import WidgetKit

@main
struct LittleWindowsWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ActiveTimerWidget()
        NextSleepWindowWidget()
        TodaySummaryWidget()
        QuickLogWidget()
        ShoppingListWidget()
        FoodQuickAddWidget()
        LittleWindowsLiveActivity()
        if #available(iOSApplicationExtension 18.0, *) {
            StartSleepControl()
            StartNursingLeftControl()
            StartNursingRightControl()
            StartTummyTimeControl()
            StopActiveTimerControl()
            DiaperNightLightControl()
            SoothingNightLightControl()
        }
    }
}
