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

    func appActionSheet(
        isPresented: Binding<Bool>,
        title: String,
        message: String? = nil,
        systemImage: String? = nil,
        tint: Color = AppTheme.accent,
        options: [AppActionSheetOption],
        cancelTitle: String = "Cancel",
        cancelAction: (() -> Void)? = nil
    ) -> some View {
        let estimatedHeight = max(320, min(700, 220 + CGFloat(options.count) * 78))
        return sheet(isPresented: isPresented) {
            AppActionSheetView(
                title: title,
                message: message,
                systemImage: systemImage,
                tint: tint,
                options: options,
                cancelTitle: cancelTitle,
                cancelAction: cancelAction
            )
            .presentationDetents([
                .height(estimatedHeight),
                .large
            ])
            .presentationContentInteraction(.scrolls)
            .presentationDragIndicator(.visible)
        }
    }
}

struct AppActionSheetOption: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String?
    var systemImage: String
    var tint: Color
    var role: ButtonRole?
    var isSelected: Bool
    var action: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color = AppTheme.accent,
        role: ButtonRole? = nil,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.role = role
        self.isSelected = isSelected
        self.action = action
    }
}

private struct AppActionSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var message: String?
    var systemImage: String?
    var tint: Color
    var options: [AppActionSheetOption]
    var cancelTitle = "Cancel"
    var cancelAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.secondary.opacity(0.28))
                .frame(width: 38, height: 4)
                .padding(.top, 10)

            HStack(alignment: .top, spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(tint.gradient, in: RoundedRectangle(cornerRadius: 13))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                Button {
                    cancelAction?()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(options) { option in
                        Button(role: option.role) {
                            dismiss()
                            option.action()
                        } label: {
                            AppActionSheetRow(option: option)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollBounceBehavior(.basedOnSize)
            .layoutPriority(1)

            Button(cancelTitle, role: .cancel) {
                cancelAction?()
                dismiss()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .background(AppTheme.background)
    }
}

private struct AppActionSheetRow: View {
    let option: AppActionSheetOption

    private var effectiveTint: Color {
        option.role == .destructive ? .red : option.tint
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: option.systemImage)
                .font(.headline)
                .foregroundStyle(effectiveTint)
                .frame(width: 38, height: 38)
                .background(effectiveTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(option.role == .destructive ? .red : .primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = option.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if option.isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(effectiveTint)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.line, lineWidth: 0.5)
        }
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
