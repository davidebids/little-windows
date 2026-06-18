import AppIntents
import SwiftUI
import WidgetKit

private struct FoodWidgetEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

private struct FoodWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FoodWidgetEntry {
        FoodWidgetEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (FoodWidgetEntry) -> Void) {
        completion(FoodWidgetEntry(date: Date(), snapshot: WidgetSnapshotReader.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FoodWidgetEntry>) -> Void) {
        let entry = FoodWidgetEntry(date: Date(), snapshot: WidgetSnapshotReader.read())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct ShoppingListWidget: Widget {
    let kind = "LittleWindows.ShoppingList"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FoodWidgetProvider()) { entry in
            ShoppingListWidgetView(food: entry.snapshot.resolvedFood)
                .containerBackground(for: .widget) {
                    LittleWindowsWidgetStyle.background
                }
        }
        .configurationDisplayName("Shopping List")
        .description("See active items and jump into shopping mode.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FoodQuickAddWidget: Widget {
    let kind = "LittleWindows.FoodQuickAdd"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FoodWidgetProvider()) { entry in
            FoodQuickAddWidgetView(food: entry.snapshot.resolvedFood)
                .containerBackground(for: .widget) {
                    LittleWindowsWidgetStyle.background
                }
        }
        .configurationDisplayName("Food Quick Add")
        .description("Open quick add or jump to your usual shopping lists.")
        .supportedFamilies([.systemMedium])
    }
}

private struct ShoppingListWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let food: FoodWidgetSnapshot

    var body: some View {
        if let list = food.selectedList {
            Link(destination: list.openURL) {
                if family == .systemSmall {
                    smallList(list)
                } else {
                    mediumList(list)
                }
            }
        } else {
            Link(destination: URL(string: "littlewindows://food/shopping")!) {
                EmptyFoodWidgetState(
                    title: "Shopping lists",
                    detail: "Open Food & Home to create a reusable list.",
                    icon: "cart.fill"
                )
            }
        }
    }

    private func smallList(_ list: FoodShoppingListSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetBrandLabel(compact: true)
            HStack(alignment: .firstTextBaseline) {
                Text("\(list.activeItemCount)")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Text("active")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
            }
            Text(list.name)
                .font(.headline)
                .lineLimit(1)
            if let first = list.topActiveItems.first {
                Text(first.name)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
            } else {
                Text("\(list.checkedItemCount) checked")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
            }
            Spacer(minLength: 0)
            Label("Open list", systemImage: "arrow.up.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LittleWindowsWidgetStyle.lavender)
        }
        .foregroundStyle(.white)
    }

    private func mediumList(_ list: FoodShoppingListSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    WidgetBrandLabel()
                    Text(list.name)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(list.activeItemCount)")
                        .font(.title2.weight(.bold))
                    Text("active")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.58))
                }
            }
            HStack(spacing: 8) {
                ForEach(list.topActiveItems.prefix(3)) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        if !item.quantityText.isEmpty {
                            Text(item.quantityText)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.58))
                                .lineLimit(1)
                        } else if let section = item.sectionName {
                            Text(section)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.58))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }
                if list.topActiveItems.isEmpty {
                    Text("No active items. Reactivate staples for the next trip.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.66))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            HStack {
                Label("\(list.checkedItemCount) checked", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.64))
                Spacer()
                Text("Tap for list")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LittleWindowsWidgetStyle.lavender)
            }
        }
        .foregroundStyle(.white)
    }
}

private struct FoodQuickAddWidgetView: View {
    let food: FoodWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    WidgetBrandLabel()
                    Text("Food quick add")
                        .font(.headline)
                }
                Spacer()
                Image(systemName: "cart.badge.plus")
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                action(
                    title: "Add Item",
                    icon: "plus.circle.fill",
                    tint: .orange,
                    destination: "food/quick-add"
                )
                ForEach(food.lists.prefix(3)) { list in
                    action(
                        title: shortTitle(for: list.name),
                        icon: icon(for: list.name),
                        tint: tint(for: list.name),
                        destination: "food/shopping/\(list.id.uuidString)"
                    )
                }
            }
            if food.lists.isEmpty {
                Text("Create reusable lists in Food & Home.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
            } else {
                Text("Quick add opens a list picker in the app.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.52))
            }
        }
        .foregroundStyle(.white)
    }

    private func action(
        title: String,
        icon: String,
        tint: Color,
        destination: String
    ) -> some View {
        Button(intent: OpenLittleWindowsIntent(destination: destination)) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
    }

    private func shortTitle(for name: String) -> String {
        if name.localizedCaseInsensitiveContains("Trader") { return "TJ's" }
        if name.localizedCaseInsensitiveContains("Costco") { return "Costco" }
        if name.localizedCaseInsensitiveContains("Safeway") { return "Safeway" }
        return name
    }

    private func icon(for name: String) -> String {
        if name.localizedCaseInsensitiveContains("Costco") { return "shippingbox.fill" }
        if name.localizedCaseInsensitiveContains("General") { return "list.bullet" }
        return "cart.fill"
    }

    private func tint(for name: String) -> Color {
        if name.localizedCaseInsensitiveContains("Costco") { return .blue }
        if name.localizedCaseInsensitiveContains("Safeway") { return .red }
        if name.localizedCaseInsensitiveContains("General") { return LittleWindowsWidgetStyle.lavender }
        return .green
    }
}

private struct EmptyFoodWidgetState: View {
    let title: String
    let detail: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            WidgetBrandLabel(compact: true)
            WidgetIconBadge(systemImage: icon, tint: .orange)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
        }
        .foregroundStyle(.white)
    }
}
