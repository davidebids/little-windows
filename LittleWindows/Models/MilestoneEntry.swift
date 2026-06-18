import Foundation
import SwiftData
import UIKit

enum MilestoneCategory: String, Codable, CaseIterable, Identifiable {
    case firsts
    case motor
    case social
    case communication
    case feeding
    case sleep
    case growth
    case health
    case travel
    case family
    case funny
    case diapering
    case adoption
    case training
    case pottyTraining
    case grooming
    case favoriteThings
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .firsts: "Firsts"
        case .motor: "Motor"
        case .social: "Social"
        case .communication: "Communication"
        case .feeding: "Feeding"
        case .sleep: "Sleep"
        case .growth: "Growth"
        case .health: "Health"
        case .travel: "Travel"
        case .family: "Family"
        case .funny: "Funny"
        case .diapering: "Diapering"
        case .adoption: "Adoption"
        case .training: "Training"
        case .pottyTraining: "Potty Training"
        case .grooming: "Grooming"
        case .favoriteThings: "Favorite Things"
        case .custom: "Custom"
        }
    }

    var systemImage: String {
        switch self {
        case .firsts: "sparkles"
        case .motor: "figure.child"
        case .social: "face.smiling.inverse"
        case .communication: "bubble.left.and.bubble.right.fill"
        case .feeding: "fork.knife"
        case .sleep: "moon.stars.fill"
        case .growth: "ruler.fill"
        case .health: "heart.text.square.fill"
        case .travel: "airplane"
        case .family: "figure.2.and.child.holdinghands"
        case .funny: "theatermasks.fill"
        case .diapering: "drop.fill"
        case .adoption: "house.fill"
        case .training: "graduationcap.fill"
        case .pottyTraining: "pawprint.fill"
        case .grooming: "comb.fill"
        case .favoriteThings: "star.circle.fill"
        case .custom: "star.fill"
        }
    }
}

struct MilestoneTemplate: Identifiable, Hashable {
    let title: String
    let category: MilestoneCategory

    var id: String { title }

    static let suggested: [MilestoneTemplate] = [
        .init(title: "First smile", category: .social),
        .init(title: "First laugh", category: .social),
        .init(title: "First coo", category: .communication),
        .init(title: "First rollover", category: .motor),
        .init(title: "First lifted head or neck", category: .motor),
        .init(title: "First time holding hands at center", category: .motor),
        .init(title: "First reached for toy", category: .motor),
        .init(title: "First grabbed object", category: .motor),
        .init(title: "First longer sleep stretch", category: .sleep),
        .init(title: "First night in crib", category: .sleep),
        .init(title: "First bath", category: .firsts),
        .init(title: "First book or story time", category: .firsts),
        .init(title: "First trip", category: .travel),
        .init(title: "First holiday", category: .family),
        .init(title: "First time meeting grandparent", category: .family),
        .init(title: "Sized up diapers", category: .diapering),
        .init(title: "Sized up clothing", category: .growth),
        .init(title: "Started solids", category: .feeding),
        .init(title: "First tooth", category: .growth),
        .init(title: "First crawl", category: .motor),
        .init(title: "First steps", category: .motor),
        .init(title: "First word", category: .communication)
    ]
}

struct AutomaticMilestoneActivitySummary: Identifiable, Hashable {
    let activityType: ActivityType
    let count: Int
    let durationSeconds: TimeInterval

    var id: String { activityType.rawValue }
}

struct AutomaticMilestoneSummary: Identifiable, Hashable {
    enum Kind: Hashable {
        case days(Int)
        case birthday(Int)
    }

    let id: String
    let kind: Kind
    let babyName: String
    let date: Date
    let sleepSessions: Int
    let totalSleepSeconds: TimeInterval
    let nursingSessions: Int
    let nursingSeconds: TimeInterval
    let pumpingSessions: Int
    let pumpingSeconds: TimeInterval
    let diaperChanges: Int
    let weightGainPounds: Double?
    let topActivities: [AutomaticMilestoneActivitySummary]

    var title: String {
        switch kind {
        case .days(let days):
            "\(babyName) is \(days) days old!"
        case .birthday(let years):
            "\(babyName) is \(years) \(years == 1 ? "year" : "years") old!"
        }
    }

    var ageLabel: String {
        switch kind {
        case .days(let days): "\(days) days"
        case .birthday(let years): "\(years) \(years == 1 ? "year" : "years")"
        }
    }
}

enum PhotoAttachmentOwnerKind: String, Codable, CaseIterable, Identifiable {
    case milestone
    case profilePhoto

    var id: String { rawValue }
}

@Model
final class PhotoAttachment {
    var id: UUID = UUID()
    var profileID: UUID?
    var ownerKindRawValue: String = PhotoAttachmentOwnerKind.milestone.rawValue
    var contentType: String = "image/jpeg"
    var filename: String?
    @Attribute(.externalStorage) var imageData: Data?
    @Attribute(.externalStorage) var thumbnailData: Data?
    var byteCount: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        profileID: UUID? = nil,
        ownerKind: PhotoAttachmentOwnerKind = .milestone,
        contentType: String = "image/jpeg",
        filename: String? = nil,
        imageData: Data,
        thumbnailData: Data? = nil,
        byteCount: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.ownerKindRawValue = ownerKind.rawValue
        self.contentType = contentType
        self.filename = filename
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.byteCount = byteCount ?? imageData.count
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var ownerKind: PhotoAttachmentOwnerKind {
        get { PhotoAttachmentOwnerKind(rawValue: ownerKindRawValue) ?? .milestone }
        set { ownerKindRawValue = newValue.rawValue }
    }

    var previewData: Data? {
        thumbnailData ?? imageData
    }
}

struct PhotoAttachmentDraft: Identifiable, Hashable {
    var id: UUID = UUID()
    var imageData: Data
    var thumbnailData: Data?
    var contentType: String = "image/jpeg"
    var filename: String?
    var createdAt: Date = Date()
}

enum PhotoAttachmentImageProcessor {
    static func draft(from data: Data, filename: String? = nil) -> PhotoAttachmentDraft? {
        guard
            let imageData = jpegData(from: data, maxPixel: 1_800, compressionQuality: 0.82),
            let thumbnailData = jpegData(from: data, maxPixel: 520, compressionQuality: 0.76)
        else { return nil }
        return PhotoAttachmentDraft(
            imageData: imageData,
            thumbnailData: thumbnailData,
            filename: filename
        )
    }

    private static func jpegData(
        from data: Data,
        maxPixel: CGFloat,
        compressionQuality: CGFloat
    ) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let resized = resizedImage(image, maxPixel: maxPixel)
        return resized.jpegData(compressionQuality: compressionQuality)
    }

    private static func resizedImage(_ image: UIImage, maxPixel: CGFloat) -> UIImage {
        let size = image.size
        let longestSide = max(size.width, size.height)
        guard longestSide > maxPixel else { return image }

        let scale = maxPixel / longestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

@MainActor
enum PhotoAttachmentStore {
    static func deleteAttachments(
        with ids: [UUID],
        in attachments: [PhotoAttachment],
        context: ModelContext
    ) {
        guard !ids.isEmpty else { return }
        let idsToDelete = Set(ids)
        attachments
            .filter { idsToDelete.contains($0.id) }
            .forEach { context.delete($0) }
    }

    static func deleteAttachments(profileID: UUID, context: ModelContext) {
        let attachments = (try? context.fetch(FetchDescriptor<PhotoAttachment>())) ?? []
        attachments
            .filter { $0.profileID == profileID }
            .forEach { context.delete($0) }
    }
}

enum AutomaticMilestoneSummaryService {
    static func summaries(
        profile: BabyProfile,
        events: [BabyEvent],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [AutomaticMilestoneSummary] {
        let birthDay = calendar.startOfDay(for: profile.birthDate)
        let today = calendar.startOfDay(for: now)
        guard today >= birthDay else { return [] }

        var celebrations: [(id: String, kind: AutomaticMilestoneSummary.Kind, date: Date)] = []
        let ageDays = max(
            0,
            calendar.dateComponents([.day], from: birthDay, to: today).day ?? 0
        )

        if ageDays >= 100 {
            for days in stride(from: 100, through: ageDays, by: 100) {
                guard let date = calendar.date(byAdding: .day, value: days, to: birthDay) else {
                    continue
                }
                celebrations.append((
                    id: "automatic-days-\(days)",
                    kind: .days(days),
                    date: date
                ))
            }
        }

        let ageYears = max(
            0,
            calendar.dateComponents([.year], from: birthDay, to: today).year ?? 0
        )
        if ageYears >= 1 {
            for years in 1...ageYears {
                guard let date = calendar.date(byAdding: .year, value: years, to: birthDay) else {
                    continue
                }
                let duplicatesDayCelebration = celebrations.contains {
                    abs($0.date.timeIntervalSince(date)) < 7 * 24 * 60 * 60
                }
                if !duplicatesDayCelebration {
                    celebrations.append((
                        id: "automatic-birthday-\(years)",
                        kind: .birthday(years),
                        date: date
                    ))
                }
            }
        }

        return celebrations.map {
            summary(
                id: $0.id,
                kind: $0.kind,
                date: $0.date,
                profile: profile,
                events: events,
                calendar: calendar
            )
        }
        .sorted { $0.date > $1.date }
    }

    private static func summary(
        id: String,
        kind: AutomaticMilestoneSummary.Kind,
        date: Date,
        profile: BabyProfile,
        events: [BabyEvent],
        calendar: Calendar
    ) -> AutomaticMilestoneSummary {
        let birthDay = calendar.startOfDay(for: profile.birthDate)
        let cutoff = calendar.startOfNextDay(for: date)
        let completed = events.filter {
            !$0.isTimerDraft
                && $0.startDate >= birthDay
                && $0.startDate < cutoff
        }
        let sleep = completed.filter { $0.type == .sleep }
        let nursing = completed.filter { $0.type == .nursing }
        let pumps = completed.filter(isPumpingEvent)
        let diapers = completed.filter { $0.type == .diaper }
        let activities = completed.filter { $0.type == .activity }

        let nursingDates = nursing.map(\.startDate).sorted()
        var groupedNursingDates: [Date] = []
        var previousNursingDate: Date?
        for date in nursingDates {
            defer { previousNursingDate = date }
            if let previous = previousNursingDate,
               date.timeIntervalSince(previous) < 45 * 60 {
                continue
            }
            groupedNursingDates.append(date)
        }

        let activityGroups = Dictionary(grouping: activities.compactMap { event in
            event.activityType.map { ($0, event) }
        }, by: \.0)
        let topActivities = activityGroups.map { type, values in
            AutomaticMilestoneActivitySummary(
                activityType: type,
                count: values.count,
                durationSeconds: values.reduce(0) {
                    $0 + clippedDuration(
                        of: $1.1,
                        from: birthDay,
                        through: cutoff
                    )
                }
            )
        }
        .sorted {
            if $0.count != $1.count {
                return $0.count > $1.count
            }
            if $0.durationSeconds != $1.durationSeconds {
                return $0.durationSeconds > $1.durationSeconds
            }
            return $0.activityType.displayName < $1.activityType.displayName
        }
        .prefix(3)

        return AutomaticMilestoneSummary(
            id: id,
            kind: kind,
            babyName: profile.name,
            date: date,
            sleepSessions: sleep.count,
            totalSleepSeconds: sleep.reduce(0) {
                $0 + clippedDuration(of: $1, from: birthDay, through: cutoff)
            },
            nursingSessions: groupedNursingDates.count,
            nursingSeconds: nursing.reduce(0) {
                let sideDuration = $1.totalNursingDurationSeconds
                return $0 + (
                    sideDuration > 0
                        ? sideDuration
                        : clippedDuration(of: $1, from: birthDay, through: cutoff)
                )
            },
            pumpingSessions: pumps.count,
            pumpingSeconds: pumps.reduce(0) {
                $0 + clippedDuration(of: $1, from: birthDay, through: cutoff)
            },
            diaperChanges: diapers.count,
            weightGainPounds: weightGain(
                profile: profile,
                events: completed
            ),
            topActivities: Array(topActivities)
        )
    }

    private static func isPumpingEvent(_ event: BabyEvent) -> Bool {
        guard event.type == .custom else { return false }
        let searchable = [event.title, event.notes]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return searchable.contains("pump")
    }

    private static func clippedDuration(
        of event: BabyEvent,
        from lowerBound: Date,
        through upperBound: Date
    ) -> TimeInterval {
        guard let endDate = event.endDate else { return 0 }
        let start = max(event.startDate, lowerBound)
        let end = min(endDate, upperBound)
        return max(0, end.timeIntervalSince(start))
    }

    private static func weightGain(
        profile: BabyProfile,
        events: [BabyEvent]
    ) -> Double? {
        let measurements = events.filter { $0.type == .growth }
            .compactMap { event -> (Date, Double)? in
                guard let kilograms = event.canonicalWeightKilograms else { return nil }
                return (event.startDate, kilograms)
            }
            .sorted { $0.0 < $1.0 }
        guard let latest = measurements.last?.1 else { return nil }
        let baseline = profile.birthWeightKilograms ?? measurements.first?.1
        guard let baseline else { return nil }
        return (latest - baseline) / GrowthUnitConversion.kilogramsPerPound
    }
}

extension Double {
    var formattedPoundChange: String {
        let value = abs(self).formatted(.number.precision(.fractionLength(0...1)))
        if self > 0 { return "+\(value) lb" }
        if self < 0 { return "-\(value) lb" }
        return "0 lb"
    }
}

@Model
final class MilestoneEntry {
    var id: UUID = UUID()
    var profileID: UUID?
    var title: String = ""
    var date: Date = Date()
    var approximateDate: Bool = false
    var categoryRawValue: String = MilestoneCategory.firsts.rawValue
    var notes: String?
    var photoAttachmentIDsData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var caregiverName: String?
    var isFavorite: Bool = false
    var sortOrder: Int?

    init(
        id: UUID = UUID(),
        profileID: UUID? = nil,
        title: String,
        date: Date,
        approximateDate: Bool = false,
        category: MilestoneCategory = .firsts,
        notes: String? = nil,
        photoAttachmentIDs: [UUID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        caregiverName: String? = nil,
        isFavorite: Bool = false,
        sortOrder: Int? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.title = title
        self.date = date
        self.approximateDate = approximateDate
        self.categoryRawValue = category.rawValue
        self.notes = notes
        self.photoAttachmentIDs = photoAttachmentIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.caregiverName = caregiverName
        self.isFavorite = isFavorite
        self.sortOrder = sortOrder
    }

    var category: MilestoneCategory {
        get { MilestoneCategory(rawValue: categoryRawValue) ?? .custom }
        set { categoryRawValue = newValue.rawValue }
    }

    var photoAttachmentIDs: [UUID] {
        get {
            guard let photoAttachmentIDsData else { return [] }
            return (try? JSONDecoder().decode([UUID].self, from: photoAttachmentIDsData)) ?? []
        }
        set {
            photoAttachmentIDsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue)
        }
    }

    func ageAtMilestoneDescription(
        birthDate: Date,
        calendar: Calendar = .current
    ) -> String {
        let prefix = approximateDate ? "about " : ""
        let birthDay = calendar.startOfDay(for: birthDate)
        let milestoneDay = calendar.startOfDay(for: date)
        guard milestoneDay >= birthDay else { return "\(prefix)before birth" }

        let totalDays = max(
            0,
            calendar.dateComponents([.day], from: birthDay, to: milestoneDay).day ?? 0
        )
        if totalDays < 14 {
            return totalDays == 0
                ? "\(prefix)newborn"
                : "\(prefix)\(totalDays) \(totalDays == 1 ? "day" : "days") old"
        }
        if totalDays < 56 {
            let weeks = totalDays / 7
            return "\(prefix)\(weeks) \(weeks == 1 ? "week" : "weeks") old"
        }

        let components = calendar.dateComponents([.year, .month], from: birthDay, to: milestoneDay)
        let years = components.year ?? 0
        let months = components.month ?? 0
        if years > 0 {
            if months > 0 {
                return "\(prefix)\(years)y \(months)m old"
            }
            return "\(prefix)\(years) \(years == 1 ? "year" : "years") old"
        }
        return "\(prefix)\(months) \(months == 1 ? "month" : "months") old"
    }

    func ageSentence(babyName: String, birthDate: Date) -> String {
        "\(babyName) was \(ageAtMilestoneDescription(birthDate: birthDate))"
    }
}
