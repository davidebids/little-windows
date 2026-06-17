import SwiftData
import SwiftUI

struct ProfileAvatarView: View {
    let profile: CareProfile
    var size: CGFloat = 42

    var body: some View {
        Text(profile.initials)
            .font(.system(size: size * 0.34, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(profileTint.gradient, in: Circle())
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: profile.profileType.systemImage)
                    .font(.system(size: size * 0.22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.38, height: size * 0.38)
                    .background(.black.opacity(0.24), in: Circle())
                    .offset(x: size * 0.05, y: size * 0.05)
            }
    }

    private var profileTint: Color {
        switch profile.displayColor {
        case "pink": .pink
        case "orange": .orange
        case "green": .green
        case "teal": .teal
        case "purple": .purple
        case "brown": .brown
        default: AppTheme.accent
        }
    }
}

struct ProfileSwitcherView: View {
    let selectedProfile: CareProfile?
    let profiles: [CareProfile]
    var selectProfile: (CareProfile) -> Void
    var addProfile: () -> Void
    var manageProfiles: () -> Void

    @State private var showingPicker = false

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            HStack(spacing: 12) {
                if let selectedProfile {
                    ProfileAvatarView(profile: selectedProfile, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedProfile.name)
                            .font(.headline)
                        Text(selectedProfile.profileSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.title2)
                        .foregroundStyle(AppTheme.accent)
                    Text("Choose profile")
                        .font(.headline)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .appSurface()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingPicker) {
            NavigationStack {
                ProfilePickerSheet(
                    selectedProfile: selectedProfile,
                    profiles: profiles,
                    selectProfile: {
                        selectProfile($0)
                        showingPicker = false
                    },
                    addProfile: {
                        showingPicker = false
                        addProfile()
                    },
                    manageProfiles: {
                        showingPicker = false
                        manageProfiles()
                    }
                )
            }
        }
    }
}

struct ProfilePickerSheet: View {
    let selectedProfile: CareProfile?
    let profiles: [CareProfile]
    var selectProfile: (CareProfile) -> Void
    var addProfile: () -> Void
    var manageProfiles: () -> Void

    var body: some View {
        List {
            if !profiles.filter({ $0.profileType == .child }).isEmpty {
                Section("Children") {
                    profileRows(profiles.filter { $0.profileType == .child })
                }
            }

            if !profiles.filter({ $0.profileType == .dog }).isEmpty {
                Section("Dogs") {
                    profileRows(profiles.filter { $0.profileType == .dog })
                }
            }

            Section {
                Button("Add Profile", systemImage: "plus.circle.fill", action: addProfile)
                Button("Manage Profiles", systemImage: "person.2.fill", action: manageProfiles)
            }
        }
        .navigationTitle("Switch Profile")
    }

    private func profileRows(_ values: [CareProfile]) -> some View {
        ForEach(values) { profile in
            Button {
                selectProfile(profile)
            } label: {
                HStack(spacing: 12) {
                    ProfileAvatarView(profile: profile, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name)
                            .foregroundStyle(.primary)
                        Text(profile.profileSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selectedProfile?.id == profile.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var profileService = ProfileService.shared

    let profile: CareProfile?

    @State private var profileType: CareProfileType
    @State private var name: String
    @State private var birthDate: Date
    @State private var hasAdoptionDate: Bool
    @State private var adoptionDate: Date
    @State private var sex: BabySex
    @State private var breed: String
    @State private var coatColor: String
    @State private var microchipNumber: String
    @State private var vetName: String
    @State private var vetClinic: String
    @State private var vetPhone: String
    @State private var emergencyVet: String
    @State private var notes: String
    @State private var validationMessage: String?

    init(profile: CareProfile? = nil, defaultType: CareProfileType = .child) {
        self.profile = profile
        _profileType = State(initialValue: profile?.profileType ?? defaultType)
        _name = State(initialValue: profile?.name ?? "")
        _birthDate = State(initialValue: profile?.birthDate ?? Date())
        _hasAdoptionDate = State(initialValue: profile?.adoptionDate != nil)
        _adoptionDate = State(initialValue: profile?.adoptionDate ?? Date())
        _sex = State(initialValue: profile?.sex ?? .unknown)
        _breed = State(initialValue: profile?.breed ?? "")
        _coatColor = State(initialValue: profile?.coatColor ?? "")
        _microchipNumber = State(initialValue: profile?.microchipNumber ?? "")
        _vetName = State(initialValue: profile?.vetName ?? "")
        _vetClinic = State(initialValue: profile?.vetClinic ?? "")
        _vetPhone = State(initialValue: profile?.vetPhone ?? "")
        _emergencyVet = State(initialValue: profile?.emergencyVet ?? "")
        _notes = State(initialValue: profile?.notes ?? "")
    }

    var body: some View {
        Form {
            Section("Profile") {
                if profile == nil {
                    Picker("Type", selection: $profileType) {
                        ForEach(CareProfileType.allCases) { value in
                            Label(value.displayName, systemImage: value.systemImage).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                TextField(profileType == .dog ? "Dog name" : "Child name", text: $name)
                DatePicker(
                    profileType == .dog ? "Birthday or best estimate" : "Birthdate",
                    selection: $birthDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                Picker("Sex", selection: $sex) {
                    ForEach(BabySex.allCases) { value in
                        Text(value.displayName).tag(value)
                    }
                }
            }

            if profileType == .dog {
                Section("Dog Details") {
                    Toggle("Has adoption/gotcha date", isOn: $hasAdoptionDate)
                    if hasAdoptionDate {
                        DatePicker("Adoption date", selection: $adoptionDate, in: ...Date(), displayedComponents: .date)
                    }
                    TextField("Breed", text: $breed)
                    TextField("Color", text: $coatColor)
                    TextField("Microchip number", text: $microchipNumber)
                }

                Section("Vet Contacts") {
                    TextField("Vet name", text: $vetName)
                    TextField("Vet clinic", text: $vetClinic)
                    TextField("Vet phone", text: $vetPhone)
                        .keyboardType(.phonePad)
                    TextField("Emergency vet", text: $emergencyVet)
                }
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
        .navigationTitle(profile == nil ? "Add Profile" : "Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
            }
        }
        .alert("Check profile", isPresented: Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "")
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validationMessage = "Enter a \(profileType == .dog ? "dog" : "child") name."
            return
        }

        if let profile {
            profile.name = trimmed
            profile.birthDate = birthDate
            profile.sex = sex
            profile.notes = notes
            profile.displayColor = profile.displayColor ?? defaultDisplayColor
            profile.profileType = profileType
            applyDogFields(to: profile)
            profileService.updateChildProfile(profile)
        } else if profileType == .dog {
            _ = profileService.createDogProfile(
                name: trimmed,
                birthDate: birthDate,
                sex: sex,
                adoptionDate: hasAdoptionDate ? adoptionDate : nil,
                breed: breed.nilIfBlank,
                coatColor: coatColor.nilIfBlank,
                microchipNumber: microchipNumber.nilIfBlank,
                vetName: vetName.nilIfBlank,
                vetClinic: vetClinic.nilIfBlank,
                vetPhone: vetPhone.nilIfBlank,
                emergencyVet: emergencyVet.nilIfBlank,
                notes: notes,
                displayColor: defaultDisplayColor,
                context: modelContext
            )
        } else {
            _ = profileService.createChildProfile(
                name: trimmed,
                birthDate: birthDate,
                sex: sex,
                notes: notes,
                displayColor: defaultDisplayColor,
                context: modelContext
            )
        }
        try? modelContext.save()
        dismiss()
    }

    private var defaultDisplayColor: String {
        profile?.displayColor ?? (profileType == .dog ? "teal" : "indigo")
    }

    private func applyDogFields(to profile: CareProfile) {
        guard profileType == .dog else {
            profile.adoptionDate = nil
            profile.species = nil
            return
        }
        profile.species = "dog"
        profile.adoptionDate = hasAdoptionDate ? adoptionDate : nil
        profile.breed = breed.nilIfBlank
        profile.coatColor = coatColor.nilIfBlank
        profile.microchipNumber = microchipNumber.nilIfBlank
        profile.vetName = vetName.nilIfBlank
        profile.vetClinic = vetClinic.nilIfBlank
        profile.vetPhone = vetPhone.nilIfBlank
        profile.emergencyVet = emergencyVet.nilIfBlank
    }
}

struct ManageProfilesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CareProfile.createdAt) private var allProfiles: [CareProfile]
    @StateObject private var profileService = ProfileService.shared
    @State private var editingProfile: CareProfile?
    @State private var profileToArchive: CareProfile?
    @State private var profileToDelete: CareProfile?
    @State private var showingAdd = false

    private var sortedProfiles: [CareProfile] {
        allProfiles.sorted { $0.createdAt < $1.createdAt }
    }

    private var activeProfiles: [CareProfile] {
        profileService.allActiveProfiles(in: allProfiles)
    }

    private var archivedProfiles: [CareProfile] {
        sortedProfiles.filter { $0.isArchived }
    }

    var body: some View {
        List {
            if !activeProfiles.filter({ $0.profileType == .child }).isEmpty {
                Section("Children") {
                    manageRows(activeProfiles.filter { $0.profileType == .child })
                }
            }

            if !activeProfiles.filter({ $0.profileType == .dog }).isEmpty {
                Section("Dogs") {
                    manageRows(activeProfiles.filter { $0.profileType == .dog })
                }
            }

            if !archivedProfiles.isEmpty {
                Section("Archived") {
                    manageRows(archivedProfiles)
                }
            }
        }
        .navigationTitle("Profiles")
        .safeAreaInset(edge: .bottom) {
            Text("Tap an active profile to switch. Use the pencil to edit details.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") { showingAdd = true }
            }
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack { ProfileEditorView() }
        }
        .sheet(item: $editingProfile) { profile in
            NavigationStack { ProfileEditorView(profile: profile) }
        }
        .appActionSheet(
            isPresented: Binding(
                get: { profileToArchive != nil || profileToDelete != nil },
                set: { if !$0 { clearPendingProfileAction() } }
            ),
            title: profileActionTitle,
            message: profileActionMessage,
            systemImage: profileActionSystemImage,
            tint: profileActionTint,
            options: profileActionOptions,
            cancelAction: {
                clearPendingProfileAction()
            }
        )
    }

    private var profileActionTitle: String {
        if let profileToArchive {
            return "Archive \(profileToArchive.name)?"
        }
        if let profileToDelete {
            return "Delete \(profileToDelete.name)?"
        }
        return "Profile Action"
    }

    private var profileActionMessage: String {
        if profileToArchive != nil {
            return "This hides the profile from daily tracking, but keeps all history available."
        }
        return "This permanently deletes the profile and its events, appointments, milestones, predictions, and guide progress."
    }

    private var profileActionSystemImage: String {
        profileToArchive != nil ? "archivebox" : "trash"
    }

    private var profileActionTint: Color {
        profileToArchive != nil ? .orange : .red
    }

    private var profileActionOptions: [AppActionSheetOption] {
        if let profile = profileToArchive {
            return [
                AppActionSheetOption(
                    title: "Archive Profile",
                    subtitle: "Hide this profile from daily tracking.",
                    systemImage: "archivebox.fill",
                    tint: .orange
                ) {
                    archive(profile)
                }
            ]
        }
        guard let profile = profileToDelete else { return [] }
        return [
            AppActionSheetOption(
                title: "Delete Profile",
                subtitle: "Remove this profile and its history.",
                systemImage: "trash.fill",
                tint: .red,
                role: .destructive
            ) {
                delete(profile)
            }
        ]
    }

    private func manageRows(_ values: [CareProfile]) -> some View {
        ForEach(values) { profile in
            let isSelected = !profile.isArchived && profileService.selectedProfileID == profile.id
            let canDelete = profileService.canDeleteProfile(profile, profiles: allProfiles)
            Button {
                guard !profile.isArchived else { return }
                profileService.switchProfile(profile)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    if profile.isArchived {
                        Capsule()
                            .fill(Color.secondary.opacity(0.38))
                            .frame(width: 4, height: 38)
                    }
                    ProfileAvatarView(profile: profile, size: 38)
                        .grayscale(profile.isArchived ? 1 : 0)
                        .opacity(profile.isArchived ? 0.48 : 1)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(profile.name)
                                .foregroundStyle(profile.isArchived ? .secondary : .primary)
                            if isSelected {
                                Text("Current")
                                    .font(.caption2.bold())
                                    .foregroundStyle(AppTheme.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppTheme.accent.opacity(0.10), in: Capsule())
                            }
                        }
                        Text(profile.profileType == .child
                            ? "\(profile.birthDate.formatted(date: .abbreviated, time: .omitted)) · \(profile.ageDescription)"
                            : [profile.breed, profile.adoptionDate.map { "home \($0.formatted(date: .abbreviated, time: .omitted))" }]
                                .compactMap { $0 }
                                .joined(separator: " · ")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if profile.isArchived {
                            Label("Archived", systemImage: "archivebox.fill")
                                .font(.caption2.bold())
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.12), in: Capsule())
                                .padding(.top, 2)
                        }
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                    }
                    Button {
                        editingProfile = profile
                    } label: {
                        Image(systemName: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 34)
                            .background(Color.primary.opacity(0.055), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit \(profile.name)")
                    if profile.isArchived {
                        Button {
                            restore(profile)
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 34, height: 34)
                                .background(AppTheme.accent.opacity(0.10), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Restore \(profile.name)")
                    }
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(profile.isArchived ? Color.primary.opacity(0.045) : Color.clear)
            .swipeActions {
                Button(role: .destructive) {
                    profileToDelete = profile
                } label: {
                    Label("Delete", systemImage: "trash.fill")
                }
                .disabled(!canDelete)
                if profile.isArchived {
                    Button {
                        restore(profile)
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    .tint(AppTheme.accent)
                } else {
                    Button {
                        profileToArchive = profile
                    } label: {
                        Label("Archive", systemImage: "archivebox.fill")
                    }
                    .tint(.orange)
                    .disabled(activeProfiles.count <= 1)
                }
            }
        }
    }

    private func archive(_ profile: CareProfile) {
        profileService.archiveProfile(profile, profiles: allProfiles, context: modelContext)
        profileToArchive = nil
    }

    private func restore(_ profile: CareProfile) {
        profileService.restoreProfile(profile, context: modelContext)
    }

    private func delete(_ profile: CareProfile) {
        profileService.deleteProfile(profile, profiles: allProfiles, context: modelContext)
        profileToDelete = nil
    }

    private func clearPendingProfileAction() {
        profileToArchive = nil
        profileToDelete = nil
    }
}

#Preview {
    NavigationStack {
        ManageProfilesView()
            .modelContainer(SampleData.previewContainer())
    }
}
