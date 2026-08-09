import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ProfileAvatarView: View {
    let profile: CareProfile
    var size: CGFloat = 42
    @Query private var photoAttachments: [PhotoAttachment]

    init(profile: CareProfile, size: CGFloat = 42) {
        self.profile = profile
        self.size = size

        if let attachmentID = profile.profilePhotoAttachmentID {
            var descriptor = FetchDescriptor<PhotoAttachment>(
                predicate: #Predicate<PhotoAttachment> { attachment in
                    attachment.id == attachmentID
                }
            )
            descriptor.fetchLimit = 1
            _photoAttachments = Query(descriptor)
        } else {
            var descriptor = FetchDescriptor<PhotoAttachment>(
                predicate: #Predicate<PhotoAttachment> { attachment in
                    attachment.ownerKindRawValue == "__missing_profile_photo__"
                }
            )
            descriptor.fetchLimit = 1
            _photoAttachments = Query(descriptor)
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(profileTint.gradient)

                if let attachmentID = profile.profilePhotoAttachmentID,
                   let profilePhotoData,
                   let image = ThumbnailImageCache.squareImage(
                    attachmentID: attachmentID,
                    data: profilePhotoData,
                    size: size
                   ) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                } else {
                    Text(profile.initials)
                        .font(.system(size: size * 0.34, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())

            Image(systemName: profile.profileType.systemImage)
                .font(.system(size: size * 0.19, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size * 0.38, height: size * 0.38)
                .background(.black.opacity(0.32), in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.72), lineWidth: max(0.75, size * 0.018))
                }
                .padding(max(1, size * 0.025))
        }
        .frame(width: size, height: size)
    }

    private var profilePhotoData: Data? {
        guard let id = profile.profilePhotoAttachmentID else { return nil }
        return photoAttachments.first { $0.id == id }?.previewData
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

struct ProfileToolbarSettingsButton: View {
    let profile: CareProfile?
    let action: () -> Void

    var body: some View {
        Group {
            if let profile {
                ProfileAvatarView(profile: profile, size: 34)
            } else {
                Image(systemName: "gearshape.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.accent)
            }
        }
        // Navigation bars add horizontal chrome around custom toolbar items.
        // A narrower content frame keeps the resulting control circular.
        .frame(width: 36, height: 44)
        .contentShape(Circle())
        .buttonBorderShape(.circle)
        .onTapGesture(perform: action)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(profile.map { "\($0.name) settings" } ?? "Settings")
        .accessibilityHint(profile == nil
            ? "Opens household settings and care profile options"
            : "Opens settings where you can switch profiles")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            action()
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

            if !profiles.filter({ $0.profileType == .adult }).isEmpty {
                Section("Adults") {
                    profileRows(profiles.filter { $0.profileType == .adult })
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
    @State private var hasBirthDate: Bool
    @State private var adultRelationship: AdultCareRelationship
    @State private var sharesWithFamily: Bool
    @State private var hasAdoptionDate: Bool
    @State private var adoptionDate: Date
    @State private var sex: ProfileSex
    @State private var breed: String
    @State private var coatColor: String
    @State private var microchipNumber: String
    @State private var vetName: String
    @State private var vetClinic: String
    @State private var vetPhone: String
    @State private var emergencyVet: String
    @State private var notes: String
    @State private var validationMessage: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var profilePhotoLoadToken = UUID()
    @State private var profilePhotoDraft: PhotoAttachmentDraft?
    @State private var removesProfilePhoto = false
    @Query(sort: \PhotoAttachment.createdAt) private var photoAttachments: [PhotoAttachment]

    init(profile: CareProfile? = nil, defaultType: CareProfileType = .child) {
        self.profile = profile
        let attachmentID = profile?.profilePhotoAttachmentID
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        var photoDescriptor = FetchDescriptor<PhotoAttachment>(
            predicate: #Predicate { $0.id == attachmentID }
        )
        photoDescriptor.fetchLimit = 1
        _photoAttachments = Query(photoDescriptor)
        _profileType = State(initialValue: profile?.profileType ?? defaultType)
        _name = State(initialValue: profile?.name ?? "")
        _birthDate = State(initialValue: profile?.birthDate ?? Date())
        _hasBirthDate = State(initialValue: profile?.birthDate != nil)
        _adultRelationship = State(initialValue: profile?.adultRelationship ?? .myself)
        _sharesWithFamily = State(initialValue: profile?.sharingScope == .family)
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
                HStack(spacing: 14) {
                    ProfilePhotoPreview(
                        profile: profile,
                        profileType: profileType,
                        name: name,
                        photoID: currentProfilePhotoID,
                        photoData: currentProfilePhotoData
                    )
                    VStack(alignment: .leading, spacing: 10) {
                        if currentProfilePhotoData == nil {
                            PhotosPicker(
                                selection: profilePhotoPickerSelection,
                                matching: .images,
                                photoLibrary: .shared()
                            ) {
                                Label("Choose Photo", systemImage: "photo")
                            }
                            .buttonStyle(.bordered)
                        } else {
                            HStack(spacing: 12) {
                                PhotosPicker(
                                    selection: profilePhotoPickerSelection,
                                    matching: .images,
                                    photoLibrary: .shared()
                                ) {
                                    ProfilePhotoActionIcon(
                                        systemImage: "photo",
                                        tint: .accentColor
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Change photo")

                                Button(role: .destructive) {
                                    profilePhotoLoadToken = UUID()
                                    selectedPhotoItem = nil
                                    profilePhotoDraft = nil
                                    removesProfilePhoto = true
                                } label: {
                                    ProfilePhotoActionIcon(
                                        systemImage: "trash",
                                        tint: .red
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove photo")
                            }
                        }
                    }
                    .controlSize(.regular)
                }
                if profile == nil {
                    Picker("Type", selection: $profileType) {
                        ForEach(CareProfileType.allCases) { value in
                            Label(value.displayName, systemImage: value.systemImage).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                LabeledContent("Name") {
                    TextField(namePrompt, text: $name)
                        .multilineTextAlignment(.trailing)
                }
                if profileType == .adult {
                    Picker("Relationship", selection: $adultRelationship) {
                        ForEach(AdultCareRelationship.allCases) { relationship in
                            Text(relationship.displayName).tag(relationship)
                        }
                    }
                    Toggle("Add date of birth", isOn: $hasBirthDate)
                }
                if profileType != .adult || hasBirthDate {
                    DatePicker(
                        profileType == .dog ? "Birthday or best estimate" : "Date of birth",
                        selection: $birthDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                }
                HStack {
                    Text("Sex")
                    Spacer()
                    Picker("Sex", selection: $sex) {
                        ForEach(ProfileSex.allCases) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            Section {
                Toggle("Share this profile with Family Sync", isOn: $sharesWithFamily)
                    .disabled(!canChangeSharingScope)
            } header: {
                Text("Privacy")
            } footer: {
                if canChangeSharingScope {
                    Text(sharesWithFamily
                        ? "This profile and its care records can be included when Family Sync is connected."
                        : "This profile stays private and is excluded from Family Sync. You can opt in later.")
                } else {
                    Text("Only the caregiver who created this profile can change whether it is included in Family Sync.")
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

    private var currentProfilePhotoData: Data? {
        if let profilePhotoDraft {
            return profilePhotoDraft.thumbnailData ?? profilePhotoDraft.imageData
        }
        guard !removesProfilePhoto,
              let id = profile?.profilePhotoAttachmentID else { return nil }
        return photoAttachments.first { $0.id == id }?.previewData
    }

    private var currentProfilePhotoID: UUID? {
        if let profilePhotoDraft { return profilePhotoDraft.id }
        guard !removesProfilePhoto else { return nil }
        return profile?.profilePhotoAttachmentID
    }

    private var profilePhotoPickerSelection: Binding<PhotosPickerItem?> {
        Binding(
            get: { selectedPhotoItem },
            set: { item in
                guard let item else {
                    selectedPhotoItem = nil
                    return
                }
                selectedPhotoItem = item
                loadProfilePhoto(from: item)
            }
        )
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validationMessage = "Enter a name for this profile."
            return
        }

        if let profile {
            profile.name = trimmed
            profile.birthDate = profileType == .adult && !hasBirthDate ? nil : birthDate
            profile.sex = sex
            profile.adultRelationship = profileType == .adult ? adultRelationship : nil
            if canChangeSharingScope {
                profile.sharingScope = sharesWithFamily ? .family : .privateOnly
            }
            profile.notes = notes
            profile.displayColor = profile.displayColor ?? defaultDisplayColor
            profile.profileType = profileType
            applyDogFields(to: profile)
            applyProfilePhoto(to: profile)
            profileService.updateProfile(profile)
        } else if profileType == .dog {
            let createdProfile = profileService.createDogProfile(
                name: trimmed,
                birthDate: birthDate,
                sex: sex,
                sharingScope: sharesWithFamily ? .family : .privateOnly,
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
            applyProfilePhoto(to: createdProfile)
        } else if profileType == .adult {
            let createdProfile = profileService.createAdultProfile(
                name: trimmed,
                birthDate: hasBirthDate ? birthDate : nil,
                sex: sex,
                relationship: adultRelationship,
                sharingScope: sharesWithFamily ? .family : .privateOnly,
                notes: notes,
                displayColor: defaultDisplayColor,
                context: modelContext
            )
            applyProfilePhoto(to: createdProfile)
        } else {
            let createdProfile = profileService.createChildProfile(
                name: trimmed,
                birthDate: birthDate,
                sex: sex,
                sharingScope: sharesWithFamily ? .family : .privateOnly,
                notes: notes,
                displayColor: defaultDisplayColor,
                context: modelContext
            )
            applyProfilePhoto(to: createdProfile)
        }
        guard PersistenceService.save(context: modelContext) else { return }
        dismiss()
    }

    private var defaultDisplayColor: String {
        if let existing = profile?.displayColor { return existing }
        return switch profileType {
        case .child: "indigo"
        case .adult: "purple"
        case .dog: "teal"
        }
    }

    private var canChangeSharingScope: Bool {
        guard let profile else { return true }
        return profile.isOwned(by: CaregiverIdentityService.stableCaregiverIdentifier())
    }

    private var namePrompt: String {
        switch profileType {
        case .child: "Child name"
        case .adult: adultRelationship == .myself ? "Your name" : "Adult name"
        case .dog: "Dog name"
        }
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

    private func loadProfilePhoto(from item: PhotosPickerItem) {
        let token = UUID()
        profilePhotoLoadToken = token
        Task {
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                let draft = PhotoAttachmentImageProcessor.draft(from: data)
            else {
                if profilePhotoLoadToken == token {
                    selectedPhotoItem = nil
                }
                return
            }
            guard profilePhotoLoadToken == token else { return }
            selectedPhotoItem = nil
            profilePhotoDraft = draft
            removesProfilePhoto = false
        }
    }

    private func applyProfilePhoto(to profile: CareProfile) {
        if removesProfilePhoto || profilePhotoDraft != nil,
           let existingID = profile.profilePhotoAttachmentID,
           let existing = photoAttachments.first(where: { $0.id == existingID }) {
            modelContext.delete(existing)
            profile.profilePhotoAttachmentID = nil
        }

        guard let draft = profilePhotoDraft else { return }
        let attachment = PhotoAttachment(
            id: draft.id,
            profileID: profile.id,
            ownerKind: .profilePhoto,
            contentType: draft.contentType,
            filename: draft.filename,
            imageData: draft.imageData,
            thumbnailData: draft.thumbnailData,
            createdAt: draft.createdAt,
            updatedAt: Date()
        )
        modelContext.insert(attachment)
        profile.profilePhotoAttachmentID = attachment.id
        profile.updatedAt = Date()
    }
}

private struct ProfilePhotoPreview: View {
    let profile: CareProfile?
    let profileType: CareProfileType
    let name: String
    let photoID: UUID?
    let photoData: Data?

    var body: some View {
        ZStack {
            if let photoID,
               let photoData,
               let image = ThumbnailImageCache.squareImage(
                attachmentID: photoID,
                data: photoData,
                size: 72
               ) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: 72, height: 72)
            } else {
                Text(profile?.initials ?? initials)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.accent.gradient)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: profileType.systemImage)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 25, height: 25)
                .background(.black.opacity(0.24), in: Circle())
        }
    }

    private var initials: String {
        let parts = name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        let value = String(parts).uppercased()
        return value.isEmpty ? "?" : value
    }
}

private struct ProfilePhotoActionIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 54, height: 54)
            .background(tint.opacity(0.12), in: Circle())
            .contentShape(Circle())
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
        profileService.allProfiles(in: allProfiles)
    }

    private var activeProfiles: [CareProfile] {
        profileService.allActiveProfiles(in: allProfiles)
    }

    private var archivedProfiles: [CareProfile] {
        sortedProfiles.filter { $0.isArchived }
    }

    var body: some View {
        List {
            if sortedProfiles.isEmpty {
                firstProfileEmptyState
            }

            if !activeProfiles.filter({ $0.profileType == .child }).isEmpty {
                Section("Children") {
                    manageRows(activeProfiles.filter { $0.profileType == .child })
                }
            }

            if !activeProfiles.filter({ $0.profileType == .adult }).isEmpty {
                Section("Adults") {
                    manageRows(activeProfiles.filter { $0.profileType == .adult })
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
            if !sortedProfiles.isEmpty {
                Text(activeProfiles.isEmpty
                    ? "Add or restore a profile whenever you want to return to care tracking."
                    : "Tap an active profile to switch. Use the pencil to edit details.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
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

    private var firstProfileEmptyState: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.09))
                    .frame(width: 116, height: 116)
                Circle()
                    .fill(AppTheme.accent.opacity(0.14))
                    .frame(width: 82, height: 82)
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            .accessibilityHidden(true)

            VStack(spacing: 9) {
                Text("No care profiles yet")
                    .font(.title2.bold())
                Text("Add a child, adult, or dog whenever you want to start care tracking. Your Home, Food, and Night Light setup will stay exactly as it is.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                showingAdd = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Care Profile")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("profiles.empty.add")
        }
        .frame(maxWidth: .infinity, minHeight: 430)
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var profileActionTitle: String {
        if let profileToArchive {
            if archivesLastActiveProfile {
                return "Archive \(profileToArchive.name) and switch to Home?"
            }
            return "Archive \(profileToArchive.name)?"
        }
        if let profileToDelete {
            return "Delete \(profileToDelete.name)?"
        }
        return "Profile Action"
    }

    private var profileActionMessage: String {
        if archivesLastActiveProfile {
            return "This is the last active care profile. Little Windows will hide Care and Reports and continue with Today, Home, Food, and Night Light. The profile and all care history stay safely archived, and you can restore it anytime."
        }
        if profileToArchive != nil {
            return "This saves any open timer and hides the profile from daily tracking, but keeps all history available."
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
                    title: archivesLastActiveProfile
                        ? "Archive and Switch to Home"
                        : "Archive Profile",
                    subtitle: archivesLastActiveProfile
                        ? "Keep all history and turn off Care."
                        : "Hide this profile from daily tracking.",
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

    private var archivesLastActiveProfile: Bool {
        guard let profileToArchive else { return false }
        return !profileToArchive.isArchived && activeProfiles.count == 1
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
                        Text(profileRowSubtitle(profile))
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
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if canDelete {
                    Button {
                        profileToDelete = profile
                    } label: {
                        Label("Delete", systemImage: "trash.fill")
                    }
                    .tint(.red)
                }
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
                }
            }
        }
    }

    private func profileRowSubtitle(_ profile: CareProfile) -> String {
        switch profile.profileType {
        case .child:
            return [
                profile.birthDate?.formatted(date: .abbreviated, time: .omitted),
                profile.ageDescription
            ].compactMap { $0 }.joined(separator: " · ")
        case .adult:
            return profile.profileSubtitle
        case .dog:
            return [
                profile.breed,
                profile.adoptionDate.map { "home \($0.formatted(date: .abbreviated, time: .omitted))" }
            ].compactMap { $0 }.joined(separator: " · ")
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
