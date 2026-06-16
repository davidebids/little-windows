import Foundation
import SwiftData

enum AppointmentType: String, Codable, CaseIterable, Identifiable {
    case pediatrician
    case wellnessCheck
    case vaccine
    case sickVisit
    case specialist
    case lab
    case dental
    case lactation
    case urgentCare
    case vetWellness
    case emergencyVet
    case grooming
    case training
    case boarding
    case daycare
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pediatrician: "Pediatrician"
        case .wellnessCheck: "Wellness Check"
        case .vaccine: "Vaccine"
        case .sickVisit: "Sick Visit"
        case .specialist: "Specialist"
        case .lab: "Lab"
        case .dental: "Dental"
        case .lactation: "Lactation"
        case .urgentCare: "Urgent Care"
        case .vetWellness: "Vet Wellness"
        case .emergencyVet: "Emergency Vet"
        case .grooming: "Grooming"
        case .training: "Training"
        case .boarding: "Boarding"
        case .daycare: "Daycare"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .pediatrician: "stethoscope"
        case .wellnessCheck: "heart.text.square.fill"
        case .vaccine: "syringe.fill"
        case .sickVisit: "facemask.fill"
        case .specialist: "person.text.rectangle.fill"
        case .lab: "testtube.2"
        case .dental: "mouth.fill"
        case .lactation: "figure.and.child.holdinghands"
        case .urgentCare: "cross.case.fill"
        case .vetWellness: "pawprint.fill"
        case .emergencyVet: "cross.case.fill"
        case .grooming: "comb.fill"
        case .training: "graduationcap.fill"
        case .boarding: "house.fill"
        case .daycare: "sun.max.fill"
        case .other: "calendar.badge.clock"
        }
    }
}

enum AppointmentReminderLeadTime: Int, Codable, CaseIterable, Identifiable {
    case atTime = 0
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    case oneDay = 1_440

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .atTime: "At time"
        case .fifteenMinutes: "15 minutes before"
        case .thirtyMinutes: "30 minutes before"
        case .oneHour: "1 hour before"
        case .twoHours: "2 hours before"
        case .oneDay: "1 day before"
        }
    }

    var shortName: String {
        switch self {
        case .atTime: "At time"
        case .fifteenMinutes: "15m"
        case .thirtyMinutes: "30m"
        case .oneHour: "1h"
        case .twoHours: "2h"
        case .oneDay: "1d"
        }
    }
}

@Model
final class DoctorAppointment {
    var id: UUID = UUID()
    var profileID: UUID?
    var title: String = ""
    var appointmentTypeRawValue: String = AppointmentType.pediatrician.rawValue
    var startDate: Date = Date()
    var endDate: Date?
    var locationName: String?
    var address: String?
    var doctorName: String?
    var clinicName: String?
    var phoneNumber: String?
    var notes: String?
    var questionsToAsk: String?
    var visitSummary: String?
    var followUpInstructions: String?
    var medicationsDiscussed: String?
    var vaccinesGiven: String?
    var growthEntryID: UUID?
    var temperatureEntryID: UUID?
    var remindersEnabled: Bool = true
    var reminderLeadTimeMinutes: [Int] = [
        AppointmentReminderLeadTime.oneDay.rawValue,
        AppointmentReminderLeadTime.oneHour.rawValue
    ]
    var lastScheduledAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isCompleted: Bool = false
    var caregiverName: String?

    init(
        id: UUID = UUID(),
        profileID: UUID? = nil,
        title: String,
        appointmentType: AppointmentType = .pediatrician,
        startDate: Date = Date(),
        endDate: Date? = nil,
        locationName: String? = nil,
        address: String? = nil,
        doctorName: String? = nil,
        clinicName: String? = nil,
        phoneNumber: String? = nil,
        notes: String? = nil,
        questionsToAsk: String? = nil,
        visitSummary: String? = nil,
        followUpInstructions: String? = nil,
        medicationsDiscussed: String? = nil,
        vaccinesGiven: String? = nil,
        growthEntryID: UUID? = nil,
        temperatureEntryID: UUID? = nil,
        remindersEnabled: Bool = true,
        reminderLeadTimeMinutes: [Int] = [
            AppointmentReminderLeadTime.oneDay.rawValue,
            AppointmentReminderLeadTime.oneHour.rawValue
        ],
        lastScheduledAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isCompleted: Bool = false,
        caregiverName: String? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.title = title
        self.appointmentTypeRawValue = appointmentType.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.locationName = locationName
        self.address = address
        self.doctorName = doctorName
        self.clinicName = clinicName
        self.phoneNumber = phoneNumber
        self.notes = notes
        self.questionsToAsk = questionsToAsk
        self.visitSummary = visitSummary
        self.followUpInstructions = followUpInstructions
        self.medicationsDiscussed = medicationsDiscussed
        self.vaccinesGiven = vaccinesGiven
        self.growthEntryID = growthEntryID
        self.temperatureEntryID = temperatureEntryID
        self.remindersEnabled = remindersEnabled
        self.reminderLeadTimeMinutes = reminderLeadTimeMinutes
        self.lastScheduledAt = lastScheduledAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isCompleted = isCompleted
        self.caregiverName = caregiverName
    }

    var appointmentType: AppointmentType {
        get { AppointmentType(rawValue: appointmentTypeRawValue) ?? .other }
        set { appointmentTypeRawValue = newValue.rawValue }
    }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? appointmentType.displayName
            : title
    }

    var reminderLeadTimes: [AppointmentReminderLeadTime] {
        get {
            reminderLeadTimeMinutes
                .compactMap(AppointmentReminderLeadTime.init(rawValue:))
                .sorted { $0.rawValue > $1.rawValue }
        }
        set {
            reminderLeadTimeMinutes = newValue
                .map(\.rawValue)
                .uniqued()
                .sorted(by: >)
        }
    }

    var locationSummary: String? {
        [clinicName, locationName, address]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
            .first
    }

    var reminderSummary: String {
        guard remindersEnabled else { return "Reminders off" }
        let values = reminderLeadTimes
        guard !values.isEmpty else { return "No reminders selected" }
        return values.map(\.shortName).joined(separator: ", ")
    }

    var isUpcoming: Bool {
        !isCompleted && startDate >= Date()
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
