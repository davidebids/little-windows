import SwiftUI

enum AppTheme {
    static let accent = Color.indigo
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let line = Color.primary.opacity(0.08)
}

extension EventType {
    var tint: Color {
        switch self {
        case .sleep: .indigo
        case .feed: .orange
        case .nursing: .pink
        case .diaper: .teal
        case .medicine: .red
        case .growth: .mint
        case .temperature: .red
        case .activity: .green
        case .food: .orange
        case .water: .cyan
        case .treat: .brown
        case .potty: .teal
        case .walk: .green
        case .rest: .indigo
        case .training: .purple
        case .grooming: .pink
        case .symptom: .red
        case .vaccine: .mint
        case .glucose: .red
        case .custom: .purple
        }
    }
}

struct AppSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .padding(.horizontal, 4)
    }
}

struct SurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(AppTheme.line, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.035), radius: 12, y: 5)
    }
}

extension View {
    func appSurface(cornerRadius: CGFloat = 22) -> some View {
        modifier(SurfaceModifier(cornerRadius: cornerRadius))
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var router = DeepLinkRouter.shared

    var body: some View {
        TabView(selection: $router.selectedTab) {
            LazyTabContent(isSelected: router.selectedTab == .today) {
                NavigationStack { TodayView() }
            }
                .tabItem { Label("Today", systemImage: "sparkles") }
                .tag(LittleWindowsTab.today)
            LazyTabContent(isSelected: router.selectedTab == .history) {
                NavigationStack { HistoryView() }
            }
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(LittleWindowsTab.history)
            LazyTabContent(isSelected: router.selectedTab == .insights) {
                NavigationStack { InsightsDashboardView() }
            }
                .tabItem { Label("Insights", systemImage: "waveform.path.ecg") }
                .tag(LittleWindowsTab.insights)
            LazyTabContent(isSelected: router.selectedTab == .milestones) {
                NavigationStack { MilestonesView() }
            }
                .tabItem { Label("Milestones", systemImage: "heart.text.clipboard.fill") }
                .tag(LittleWindowsTab.milestones)
            LazyTabContent(isSelected: router.selectedTab == .nightLight) {
                NavigationStack { NightLightView() }
            }
                .tabItem { Label("Night Light", systemImage: "lightbulb.fill") }
                .tag(LittleWindowsTab.nightLight)
        }
        .tint(AppTheme.accent)
        .environmentObject(router)
        .sheet(isPresented: $router.showingSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                router.showingSettings = false
                            }
                        }
                    }
            }
        }
        .onOpenURL { router.route($0) }
        .task {
            if ProcessInfo.processInfo.environment["LITTLE_WINDOWS_START_TAB"] == "insights" {
                router.selectedTab = .insights
            }
            if let value = ProcessInfo.processInfo.environment["LITTLE_WINDOWS_START_URL"],
               let url = URL(string: value) {
                router.route(url)
            }
            consumePendingSystemAction()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { consumePendingSystemAction() }
        }
    }

    private func consumePendingSystemAction() {
        if let url = IntegrationCommandStore.consumePendingURL() {
            router.route(url)
        }
    }
}

private struct LazyTabContent<Content: View>: View {
    let isSelected: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isSelected {
            content()
        } else {
            Color.clear
        }
    }
}

#Preview {
    RootView()
        .modelContainer(SampleData.previewContainer())
}
