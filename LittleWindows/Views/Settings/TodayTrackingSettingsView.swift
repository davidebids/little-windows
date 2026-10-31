import SwiftUI

struct TodayTrackingSettingsView: View {
    let profile: CareProfile
    @State private var preferences = CareTrackingPreferences()

    var body: some View {
        Form {
            Section {
                Picker("Layout", selection: Binding(
                    get: { preferences.layout },
                    set: { layout in update { $0.set("layout", value: [layout.rawValue]) } }
                )) {
                    ForEach(CareTodayLayout.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("today-settings.layout")
            } header: {
                Text("Today for \(profile.name)")
            } footer: {
                Text("Essentials puts a few large logging buttons at the center of Today. Full keeps the detailed care view. Switching layouts does not pause tracking or reminders.")
            }

            if preferences.layout == .essentials {
                Section("Layout preview") {
                    let types = preferences.essentialTypes(
                        for: profile.profileType,
                        hidden: CareCategoryPreferenceStore.hiddenTypes(profileID: profile.id)
                    )
                    if !preferences.shows(.actions) {
                        Text("Logging buttons are hidden. Turn them on in Visible Sections.")
                            .foregroundStyle(.secondary)
                    } else if types.isEmpty {
                        Text(preferences.configuredEssentials(for: profile.profileType,
                             hidden: CareCategoryPreferenceStore.hiddenTypes(profileID: profile.id)).isEmpty
                             ? "Choose activities below to add your essentials."
                             : "Your chosen activities are paused. Resume them in Tracking & Reminders.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(types.prefix(3)) { type in
                                EssentialsActionButton(
                                    type: type, profileType: profile.profileType,
                                    detail: "Recent record or running timer", count: types.count,
                                    action: {}
                                )
                                .disabled(true)
                            }
                            if types.count > 3 {
                                Text("Plus \(types.count - 3) more below these buttons")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Preview: large buttons for \(types.map(\.displayName).joined(separator: ", "))")
                    }
                }
            }

            Section {
                if preferences.layout == .essentials {
                    NavigationLink("Activities & Button Order") {
                        TodayEssentialsActivitiesView(profile: profile)
                    }
                }
                NavigationLink("Visible Sections") {
                    TodaySectionSettingsView(profile: profile)
                }
                NavigationLink("Tracking & Reminders") {
                    TodayTrackingCategoriesView(profile: profile)
                }
                if preferences.layout == .full {
                    NavigationLink("Full Layout Quick Actions") {
                        CareCategoryCustomizationView(profileID: profile.id, profileType: profile.profileType) {
                            SystemIntegrationReconciler.requestReconciliation()
                        }
                    }
                }
            } footer: {
                Text("These choices follow this profile on devices signed into the same Apple Account when iCloud Sync is on. Offline changes apply here immediately and merge when iCloud becomes available.")
            }

            Section {
                Button("Reset This Layout") {
                    update { $0.resetCurrentLayout(for: profile.profileType) }
                }
            } footer: {
                Text("Resets buttons and section visibility. Paused tracking and reminder choices stay as you set them.")
            }
        }
        .navigationTitle("Today & Tracking")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: CareTrackingPreferenceStore.changedNotification)) { _ in reload() }
    }

    private func reload() { preferences = CareTrackingPreferenceStore.preferences(profileID: profile.id) }
    private func update(_ change: (inout CareTrackingPreferences) -> Void) {
        CareTrackingPreferenceStore.update(profileID: profile.id, change)
        reload()
    }
}

private struct TodayEssentialsActivitiesView: View {
    let profile: CareProfile
    @State private var preferences = CareTrackingPreferences()

    private var selected: [EventType] {
        preferences.configuredEssentials(
            for: profile.profileType,
            hidden: CareCategoryPreferenceStore.hiddenTypes(profileID: profile.id)
        )
    }

    var body: some View {
        List {
            Section {
                ForEach(selected) { type in
                    HStack {
                        Button {
                            save(selected.filter { $0 != type })
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(type.displayName)")
                        .accessibilityIdentifier("today-settings.remove.\(type.rawValue)")
                        Label(type.displayName, systemImage: type.systemImage(for: profile.profileType))
                        Spacer()
                        if !preferences.allows(type) { Text("Paused").foregroundStyle(.secondary) }
                    }
                }
                .onMove { source, destination in
                    var types = selected
                    types.move(fromOffsets: source, toOffset: destination)
                    save(types)
                }
            } header: {
                Text("Essentials buttons")
            } footer: {
                Text("Drag to reorder or remove a button. Fewer activities leave more room for each button. Removing a button does not pause tracking. Paused activities stay in this list and return to Today when resumed.")
            }
            Section("Add an activity") {
                ForEach(EventType.cases(for: profile.profileType).filter { !selected.contains($0) }) { type in
                    Button {
                        save(selected + [type])
                    } label: {
                        HStack {
                            Label(type.displayName, systemImage: "plus.circle")
                            Spacer()
                            if !preferences.allows(type) {
                                Text("Paused").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Activities & Order")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: CareTrackingPreferenceStore.changedNotification)) { _ in reload() }
    }

    private func reload() { preferences = CareTrackingPreferenceStore.preferences(profileID: profile.id) }
    private func save(_ types: [EventType]) {
        CareTrackingPreferenceStore.update(profileID: profile.id) { $0.set("essentials", value: types.map(\.rawValue)) }
        reload()
    }
}

private struct TodaySectionSettingsView: View {
    let profile: CareProfile
    @State private var preferences = CareTrackingPreferences()

    var body: some View {
        Form {
            Section {
                ForEach(CareTodaySection.allCases.filter { $0.applies(to: profile.profileType) }) { section in
                    Toggle(section.title, isOn: Binding(
                        get: { preferences.shows(section) },
                        set: { shown in
                            CareTrackingPreferenceStore.update(profileID: profile.id) {
                                $0.set("section.\(preferences.layout.rawValue).\(section.rawValue)", value: [String(shown)])
                            }
                            reload()
                        }
                    ))
                    .accessibilityIdentifier("today-settings.section.\(section.rawValue)")
                    .disabled(!preferences.allowsPrompts(section))
                }
            } header: {
                Text("Sections in \(preferences.layout.title)")
            } footer: {
                Text("Hidden sections leave no headers or placeholders. Hiding a section does not change its reminders. Running timers and History remain reachable from Today's menu.")
            }
        }
        .navigationTitle("Visible Sections")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: CareTrackingPreferenceStore.changedNotification)) { _ in reload() }
    }
    private func reload() { preferences = CareTrackingPreferenceStore.preferences(profileID: profile.id) }
}

private struct TodayTrackingCategoriesView: View {
    let profile: CareProfile
    @State private var preferences = CareTrackingPreferences()
    @State private var confirmMedicationPause = false

    var body: some View {
        Form {
            Section {
                ForEach(EventType.cases(for: profile.profileType)) { type in
                    Toggle(isOn: Binding(
                        get: { preferences.allows(type) },
                        set: { enabled in
                            if type == .medicine && !enabled { confirmMedicationPause = true }
                            else { setPaused(!enabled, type: type) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(type.displayName, systemImage: type.systemImage(for: profile.profileType))
                            if !preferences.allows(type) {
                                Text("Paused · history saved").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("today-tracking.category.\(type.rawValue)")
                }
            } header: {
                Text("Active tracking")
            } footer: {
                Text("Turn off a category to pause its Today buttons, related prompts, suggestions, and reminders across your devices. Existing logs and plans stay saved. Manual records and running timers remain available. Resuming restores future reminders without a catch-up notification burst.")
            }

            Section {
                ForEach([CareTodaySection.routines, .guides, .appointments].filter { $0.applies(to: profile.profileType) }) { section in
                    Toggle("\(section.title) prompts & reminders", isOn: Binding(
                        get: { preferences.allowsPrompts(section) },
                        set: { enabled in
                            CareTrackingPreferenceStore.update(profileID: profile.id) {
                                $0.set("prompts.\(section.rawValue)", value: [String(enabled)])
                            }
                            reload()
                        }
                    ))
                }
            } footer: {
                Text("These switches also quiet the related Today sections. Hiding a section in Visible Sections only changes its appearance.")
            }
        }
        .navigationTitle("Tracking & Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Pause medication tracking and reminders?", isPresented: $confirmMedicationPause) {
            Button("Pause Medication Reminders", role: .destructive) { setPaused(true, type: .medicine) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Scheduled dose, follow-up, and snoozed reminders for this profile will stop as each device receives the change. Medication plans and dose history stay saved. You can still record doses manually.")
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: CareTrackingPreferenceStore.changedNotification)) { _ in reload() }
    }

    private func reload() { preferences = CareTrackingPreferenceStore.preferences(profileID: profile.id) }
    private func setPaused(_ paused: Bool, type: EventType) {
        CareTrackingPreferenceStore.update(profileID: profile.id) { $0.set("paused.\(type.rawValue)", value: [String(paused)]) }
        reload()
    }
}

struct EssentialsActionButton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let type: EventType
    let profileType: CareProfileType
    let detail: String
    var timerStart: Date? = nil
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            labelContent
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, minHeight: count <= 3 ? 120 : 108, alignment: .leading)
                .background(type.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(type.tint.opacity(0.18)))
                .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today.essential.\(type.rawValue)")
    }

    @ViewBuilder
    private var labelContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: type.systemImage(for: profileType))
                        .foregroundStyle(type.tint)
                        .accessibilityHidden(true)
                    Text(type == .medicine ? "Medication" : type.displayName)
                        .font(.title2.bold())
                }
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                if let timerStart {
                    Text(timerStart, style: .timer)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(type.tint)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            compactContent
        }
    }

    private var compactContent: some View {
        HStack(spacing: 20) {
            Image(systemName: type.systemImage(for: profileType))
                .font(.system(size: count <= 3 ? 36 : 30, weight: .semibold))
                .frame(width: 58, height: 64)
                .foregroundStyle(type.tint)
            VStack(alignment: .leading, spacing: 8) {
                Text(type == .medicine ? "Medication" : type.displayName)
                    .font(.title2.bold())
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let timerStart {
                    Text(timerStart, style: .timer)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(type.tint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: timerStart == nil ? "plus" : "timer")
                .font(.title3.weight(.semibold))
                .foregroundStyle(type.tint)
                .accessibilityHidden(true)
        }
    }
}
