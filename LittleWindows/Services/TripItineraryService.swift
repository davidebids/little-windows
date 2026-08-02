import Foundation
import SwiftData

struct TripItineraryLinkInput: Equatable {
    var title: String
    var urlString: String
}

struct TripItineraryItemInput {
    var title: String
    var kind: TripItineraryItemKind
    var scheduleKind: TripItineraryScheduleKind
    var scheduledDay: Date?
    var startDate: Date?
    var endDate: Date?
    var startTimeZoneIdentifier: String?
    var endTimeZoneIdentifier: String?
    var location: TripDestinationSelection?
    var origin: TripDestinationSelection?
    var notes: String
    var bookingStatus: TripItineraryBookingStatus
    var providerName: String
    var confirmationNumber: String
    var choiceGroupID: UUID?
    var assignedCaregiverName: String?
    var reminderEnabled: Bool
    var reminderOffsetMinutes: Int
    var links: [TripItineraryLinkInput]
}

struct TripItineraryPresentationIndex {
    let itineraryDays: [Date]
    let ungroupedItemsByDay: [Date: [TripItineraryItem]]
    let groupsByDay: [Date: [TripItineraryChoiceGroup]]
    let unscheduledItems: [TripItineraryItem]
    let unscheduledGroups: [TripItineraryChoiceGroup]
    let optionsByGroupID: [UUID: [TripItineraryItem]]
    let linksByItemID: [UUID: [TripItineraryLink]]
    let destinationsByDay: [Date: TripDestinationSelection]
    let weatherByDay: [Date: TripDailyWeather]

    @MainActor
    init(
        trip: PackingTrip,
        choiceGroups: [TripItineraryChoiceGroup],
        items: [TripItineraryItem],
        links: [TripItineraryLink],
        weatherForecasts: [TripDestinationWeatherForecast] = []
    ) {
        let calendar = trip.tripCalendar
        let firstDay = calendar.startOfDay(for: trip.startDate)
        let lastDay = calendar.startOfDay(for: trip.endDate)
        var days = [Date]()
        var day = firstDay
        while day <= lastDay {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        itineraryDays = days

        let tripGroups = choiceGroups.filter { $0.tripID == trip.id }
        let groupIDs = Set(tripGroups.map(\.id))
        var groupedOptions = [UUID: [TripItineraryItem]]()
        var ungroupedByDay = [Date: [TripItineraryItem]]()
        var ideas = [TripItineraryItem]()
        for item in TripItineraryService.sortedItems(items.filter { $0.tripID == trip.id }) {
            if let groupID = item.choiceGroupID, groupIDs.contains(groupID) {
                groupedOptions[groupID, default: []].append(item)
            } else if item.scheduleKind == .unscheduled || item.scheduledDay == nil {
                ideas.append(item)
            } else if let scheduledDay = item.scheduledDay {
                ungroupedByDay[calendar.startOfDay(for: scheduledDay), default: []].append(item)
            }
        }
        optionsByGroupID = groupedOptions
        ungroupedItemsByDay = ungroupedByDay
        unscheduledItems = ideas

        var scheduledGroups = [Date: [TripItineraryChoiceGroup]]()
        var ideaGroups = [TripItineraryChoiceGroup]()
        let sortedGroups = tripGroups.map { group in
            (group: group, sortOrder: group.sortOrder, createdAt: group.createdAt, id: group.id.uuidString)
        }.sorted {
            ($0.sortOrder, $0.createdAt, $0.id) < ($1.sortOrder, $1.createdAt, $1.id)
        }.map(\.group)
        for group in sortedGroups {
            if let scheduledDay = group.scheduledDay {
                scheduledGroups[calendar.startOfDay(for: scheduledDay), default: []].append(group)
            } else {
                ideaGroups.append(group)
            }
        }
        groupsByDay = scheduledGroups
        unscheduledGroups = ideaGroups

        var itemLinks = [UUID: [TripItineraryLink]]()
        let sortedLinks = links.filter { $0.tripID == trip.id }.map { link in
            (link: link, sortOrder: link.sortOrder, createdAt: link.createdAt, id: link.id.uuidString)
        }.sorted {
            ($0.sortOrder, $0.createdAt, $0.id) < ($1.sortOrder, $1.createdAt, $1.id)
        }.map(\.link)
        for link in sortedLinks {
            if let itemID = link.itineraryItemID {
                itemLinks[itemID, default: []].append(link)
            }
        }
        linksByItemID = itemLinks

        let destinationWindows = trip.destinationWeatherWindows
        var dayDestinations = [Date: TripDestinationSelection]()
        for day in days {
            if let destination = destinationWindows.first(where: {
                day >= calendar.startOfDay(for: $0.startDate)
                    && day <= calendar.startOfDay(for: $0.endDate)
            })?.destination {
                dayDestinations[day] = destination
            }
        }
        destinationsByDay = dayDestinations

        var dailyWeather = [Date: TripDailyWeather]()
        for forecast in weatherForecasts.compactMap(\.snapshot).flatMap(\.dailyForecast) {
            let forecastDay = calendar.startOfDay(for: forecast.date)
            if dailyWeather[forecastDay] == nil {
                dailyWeather[forecastDay] = forecast
            }
        }
        weatherByDay = dailyWeather
    }
}

@MainActor
enum TripItineraryService {
    static func validationMessage(
        for input: TripItineraryItemInput,
        trip: PackingTrip,
        choiceGroups: [TripItineraryChoiceGroup]
    ) -> String? {
        guard !input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Add a title."
        }
        guard input.reminderOffsetMinutes >= 0 else {
            return "The reminder lead time cannot be negative."
        }
        let choiceGroup = input.choiceGroupID.flatMap { groupID in
            choiceGroups.first { $0.id == groupID && $0.tripID == trip.id }
        }
        if input.choiceGroupID != nil, choiceGroup == nil {
            return "Choose an option group from this trip."
        }
        if let choiceGroup {
            if let groupDay = choiceGroup.scheduledDay {
                guard input.scheduleKind != .unscheduled,
                      let itemDay = input.scheduledDay,
                      trip.tripCalendar.isDate(groupDay, inSameDayAs: itemDay) else {
                    return "Options must use the same day as their option group."
                }
            } else if input.scheduleKind != .unscheduled {
                return "Options in an idea group cannot be assigned to a day."
            }
        }
        if input.scheduleKind == .unscheduled {
            guard input.startDate == nil, input.endDate == nil else {
                return "Ideas without a day cannot have start or end times."
            }
        } else {
            guard let day = input.scheduledDay else { return "Choose an itinerary day." }
            let normalizedDay = trip.tripCalendar.startOfDay(for: day)
            let tripStart = trip.tripCalendar.startOfDay(for: trip.startDate)
            let tripEnd = trip.tripCalendar.startOfDay(for: trip.endDate)
            guard (tripStart...tripEnd).contains(normalizedDay) else {
                return "Choose a day within the trip dates."
            }
        }
        if input.scheduleKind == .timed {
            guard let startDate = input.startDate else { return "Choose a start time." }
            if input.startTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)) != nil
                || input.startTimeZoneIdentifier == nil,
               let scheduledDay = input.scheduledDay,
               !isTimedDate(
                   startDate,
                   on: scheduledDay,
                   scheduleCalendar: trip.tripCalendar,
                   valueTimeZoneIdentifier: input.startTimeZoneIdentifier
               ) {
                return "The start time must be on the selected itinerary day."
            }
            if let endDate = input.endDate, endDate < startDate {
                return "The end time cannot be before the start time."
            }
        } else if input.reminderEnabled {
            return "Reminders require a specific start time."
        }
        for identifier in [input.startTimeZoneIdentifier, input.endTimeZoneIdentifier].compactMap({ $0 }) {
            guard TimeZone(identifier: identifier) != nil else {
                return "Choose a valid time zone."
            }
        }
        for destination in [input.location, input.origin].compactMap({ $0 }) {
            guard destinationIsValid(destination) else {
                return "Choose a valid place with a name and complete coordinates."
            }
        }
        for link in input.links {
            let trimmedURL = link.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmedURL),
                  let scheme = url.scheme?.lowercased(),
                  (scheme == "http" || scheme == "https"),
                  url.host?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return "Each link must use a valid http or https address."
            }
        }
        return nil
    }

    static func date(
        _ value: Date,
        preservingWallClockFrom sourceTimeZone: TimeZone,
        to destinationTimeZone: TimeZone
    ) -> Date {
        guard sourceTimeZone.identifier != destinationTimeZone.identifier else { return value }
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = sourceTimeZone
        var destinationCalendar = Calendar(identifier: .gregorian)
        destinationCalendar.timeZone = destinationTimeZone
        let components = sourceCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: value
        )
        return destinationCalendar.date(from: components) ?? value
    }

    static func movingScheduledDate(
        _ value: Date,
        from sourceDay: Date,
        to destinationDay: Date,
        sourceScheduleCalendar: Calendar,
        destinationScheduleCalendar: Calendar,
        valueTimeZoneIdentifier: String?
    ) -> Date {
        var valueCalendar = Calendar(identifier: .gregorian)
        valueCalendar.timeZone = valueTimeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? sourceScheduleCalendar.timeZone
        let sourceDayComponents = sourceScheduleCalendar.dateComponents(
            [.year, .month, .day],
            from: sourceDay
        )
        let destinationDayComponents = destinationScheduleCalendar.dateComponents(
            [.year, .month, .day],
            from: destinationDay
        )
        guard let sourceValueDay = valueCalendar.date(from: sourceDayComponents),
              let destinationValueDay = valueCalendar.date(from: destinationDayComponents) else {
            return value
        }
        let valueDayOffset = valueCalendar.dateComponents(
            [.day],
            from: valueCalendar.startOfDay(for: sourceValueDay),
            to: valueCalendar.startOfDay(for: value)
        ).day ?? 0
        let targetDay = valueCalendar.date(
            byAdding: .day,
            value: valueDayOffset,
            to: destinationValueDay
        ) ?? destinationValueDay
        let timeComponents = valueCalendar.dateComponents(
            [.hour, .minute, .second],
            from: value
        )
        var targetComponents = valueCalendar.dateComponents([.year, .month, .day], from: targetDay)
        targetComponents.hour = timeComponents.hour
        targetComponents.minute = timeComponents.minute
        targetComponents.second = timeComponents.second
        return valueCalendar.date(from: targetComponents) ?? value
    }

    static func isTimedDate(
        _ value: Date,
        on scheduledDay: Date,
        scheduleCalendar: Calendar,
        valueTimeZoneIdentifier: String?
    ) -> Bool {
        var valueCalendar = Calendar(identifier: .gregorian)
        valueCalendar.timeZone = valueTimeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? scheduleCalendar.timeZone
        let scheduleComponents = scheduleCalendar.dateComponents([.year, .month, .day], from: scheduledDay)
        let valueComponents = valueCalendar.dateComponents([.year, .month, .day], from: value)
        return scheduleComponents.year == valueComponents.year
            && scheduleComponents.month == valueComponents.month
            && scheduleComponents.day == valueComponents.day
    }

    static func createItem(
        input: TripItineraryItemInput,
        trip: PackingTrip,
        choiceGroups: [TripItineraryChoiceGroup],
        existingItems: [TripItineraryItem],
        context: ModelContext,
        caregiverName: String = CaregiverIdentityService.currentCaregiverName(),
        now: Date = Date()
    ) -> TripItineraryItem? {
        guard !trip.isArchived,
              validationMessage(for: input, trip: trip, choiceGroups: choiceGroups) == nil else {
            return nil
        }
        let item = TripItineraryItem(
            householdID: trip.householdID,
            tripID: trip.id,
            choiceGroupID: input.choiceGroupID,
            title: input.title.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: input.kind,
            scheduleKind: input.scheduleKind,
            scheduledDay: normalizedDay(input.scheduledDay, scheduleKind: input.scheduleKind, trip: trip),
            startDate: input.scheduleKind == .timed ? input.startDate : nil,
            endDate: input.scheduleKind == .timed ? input.endDate : nil,
            startTimeZoneIdentifier: input.startTimeZoneIdentifier ?? trip.timeZoneIdentifier,
            endTimeZoneIdentifier: input.endTimeZoneIdentifier ?? input.startTimeZoneIdentifier ?? trip.timeZoneIdentifier,
            location: input.location,
            origin: input.kind.supportsOrigin ? input.origin : nil,
            notes: input.notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            bookingStatus: input.bookingStatus,
            providerName: input.providerName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            confirmationNumber: input.confirmationNumber.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            assignedCaregiverName: input.assignedCaregiverName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            reminderEnabled: input.scheduleKind == .timed && input.reminderEnabled,
            reminderOffsetMinutes: input.reminderOffsetMinutes,
            createdBy: caregiverName,
            createdAt: now,
            updatedAt: now,
            sortOrder: (existingItems.filter { $0.tripID == trip.id }.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(item)
        insertLinks(input.links, item: item, trip: trip, context: context, caregiverName: caregiverName, now: now)
        trip.updatedAt = now
        guard PersistenceService.save(context: context) else { return nil }
        scheduleReminder(for: item, trip: trip, choiceGroups: choiceGroups)
        return item
    }

    @discardableResult
    static func updateItem(
        _ item: TripItineraryItem,
        input: TripItineraryItemInput,
        trip: PackingTrip,
        choiceGroups: [TripItineraryChoiceGroup],
        existingLinks: [TripItineraryLink],
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        guard !trip.isArchived, item.tripID == trip.id,
              validationMessage(for: input, trip: trip, choiceGroups: choiceGroups) == nil else {
            return false
        }
        let previousChoiceGroupID = item.choiceGroupID
        item.title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.kind = input.kind
        item.scheduleKind = input.scheduleKind
        item.scheduledDay = normalizedDay(input.scheduledDay, scheduleKind: input.scheduleKind, trip: trip)
        item.startDate = input.scheduleKind == .timed ? input.startDate : nil
        item.endDate = input.scheduleKind == .timed ? input.endDate : nil
        item.startTimeZoneIdentifier = input.startTimeZoneIdentifier ?? trip.timeZoneIdentifier
        item.endTimeZoneIdentifier = input.endTimeZoneIdentifier ?? input.startTimeZoneIdentifier ?? trip.timeZoneIdentifier
        item.location = input.location
        item.origin = input.kind.supportsOrigin ? input.origin : nil
        item.notes = input.notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.bookingStatus = input.bookingStatus
        item.providerName = input.providerName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.confirmationNumber = input.confirmationNumber.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.choiceGroupID = input.choiceGroupID
        for group in choiceGroups where group.selectedItemID == item.id && group.id != input.choiceGroupID {
            group.selectedItemID = nil
            group.updatedAt = now
        }
        item.assignedCaregiverName = input.assignedCaregiverName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.reminderEnabled = input.scheduleKind == .timed && input.reminderEnabled
        item.reminderOffsetMinutes = input.reminderOffsetMinutes
        if !input.kind.supportsCompletion {
            item.isCompleted = false
            item.completedBy = nil
            item.completedAt = nil
            item.lastReopenedAt = nil
        }
        item.updatedAt = now
        for link in existingLinks where link.itineraryItemID == item.id {
            context.delete(link)
        }
        insertLinks(
            input.links,
            item: item,
            trip: trip,
            context: context,
            caregiverName: CaregiverIdentityService.currentCaregiverName(),
            now: now
        )
        trip.updatedAt = now
        guard PersistenceService.save(context: context) else { return false }
        let affectedChoiceGroupIDs = Set([previousChoiceGroupID, item.choiceGroupID].compactMap { $0 })
        if affectedChoiceGroupIDs.isEmpty {
            scheduleReminder(for: item, trip: trip, choiceGroups: choiceGroups)
        } else {
            rescheduleChoiceGroupReminders(
                groupIDs: affectedChoiceGroupIDs,
                trip: trip,
                choiceGroups: choiceGroups,
                context: context
            )
        }
        return true
    }

    @discardableResult
    static func deleteItem(
        _ item: TripItineraryItem,
        trip: PackingTrip,
        choiceGroups: [TripItineraryChoiceGroup],
        links: [TripItineraryLink],
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        guard !trip.isArchived, item.tripID == trip.id else { return false }
        let previousChoiceGroupID = item.choiceGroupID
        for group in choiceGroups where group.selectedItemID == item.id {
            group.selectedItemID = nil
            group.updatedAt = now
        }
        for link in links where link.itineraryItemID == item.id {
            context.delete(link)
        }
        context.delete(item)
        trip.updatedAt = now
        guard PersistenceService.save(context: context) else { return false }
        Task { await NotificationManager.shared.cancelItineraryItemReminder(itemID: item.id) }
        if let previousChoiceGroupID {
            rescheduleChoiceGroupReminders(
                groupIDs: Set([previousChoiceGroupID]),
                trip: trip,
                choiceGroups: choiceGroups,
                context: context
            )
        }
        return true
    }

    @discardableResult
    static func setCompleted(
        _ item: TripItineraryItem,
        completed: Bool,
        trip: PackingTrip,
        context: ModelContext,
        caregiverName: String = CaregiverIdentityService.currentCaregiverName(),
        now: Date = Date()
    ) -> Bool {
        guard !trip.isArchived, item.tripID == trip.id, item.kind.supportsCompletion else { return false }
        item.isCompleted = completed
        item.completedBy = completed ? caregiverName : nil
        item.completedAt = completed ? now : nil
        item.lastReopenedAt = completed ? nil : now
        item.updatedAt = now
        trip.updatedAt = now
        guard PersistenceService.save(context: context) else { return false }
        let itemChoiceGroups: [TripItineraryChoiceGroup]
        if let choiceGroupID = item.choiceGroupID {
            itemChoiceGroups = ((try? context.fetch(FetchDescriptor<TripItineraryChoiceGroup>(
                predicate: #Predicate { $0.id == choiceGroupID }
            ))) ?? []).filter { $0.tripID == trip.id }
        } else {
            itemChoiceGroups = []
        }
        scheduleReminder(for: item, trip: trip, choiceGroups: itemChoiceGroups)
        return true
    }

    static func createChoiceGroup(
        title: String,
        notes: String,
        scheduledDay: Date?,
        trip: PackingTrip,
        existingGroups: [TripItineraryChoiceGroup],
        context: ModelContext,
        now: Date = Date()
    ) -> TripItineraryChoiceGroup? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trip.isArchived, !trimmed.isEmpty else { return nil }
        let day = scheduledDay.map { trip.tripCalendar.startOfDay(for: $0) }
        if let day {
            let range = trip.tripCalendar.startOfDay(for: trip.startDate)...trip.tripCalendar.startOfDay(for: trip.endDate)
            guard range.contains(day) else { return nil }
        }
        let group = TripItineraryChoiceGroup(
            householdID: trip.householdID,
            tripID: trip.id,
            title: trimmed,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            scheduledDay: day,
            createdBy: CaregiverIdentityService.currentCaregiverName(),
            createdAt: now,
            updatedAt: now,
            sortOrder: (existingGroups.filter { $0.tripID == trip.id }.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(group)
        trip.updatedAt = now
        return PersistenceService.save(context: context) ? group : nil
    }

    @discardableResult
    static func updateChoiceGroup(
        _ group: TripItineraryChoiceGroup,
        title: String,
        notes: String,
        scheduledDay: Date?,
        trip: PackingTrip,
        items: [TripItineraryItem],
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trip.isArchived, group.tripID == trip.id, !trimmed.isEmpty else { return false }
        let day = scheduledDay.map { trip.tripCalendar.startOfDay(for: $0) }
        if let day {
            let range = trip.tripCalendar.startOfDay(for: trip.startDate)...trip.tripCalendar.startOfDay(for: trip.endDate)
            guard range.contains(day) else { return false }
        }
        let previousDay = group.scheduledDay
        group.title = trimmed
        group.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        group.scheduledDay = day
        group.updatedAt = now
        for item in items where item.tripID == trip.id && item.choiceGroupID == group.id {
            align(item, withGroupDay: day, previousGroupDay: previousDay, trip: trip, now: now)
        }
        trip.updatedAt = now
        guard PersistenceService.save(context: context) else { return false }
        rescheduleReminders(
            for: trip,
            items: items.filter { $0.choiceGroupID == group.id },
            choiceGroups: [group]
        )
        return true
    }

    @discardableResult
    static func selectChoice(
        _ item: TripItineraryItem?,
        in group: TripItineraryChoiceGroup,
        trip: PackingTrip,
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        guard !trip.isArchived, group.tripID == trip.id,
              item == nil || (item?.tripID == trip.id && item?.choiceGroupID == group.id) else {
            return false
        }
        group.selectedItemID = item?.id
        group.updatedAt = now
        trip.updatedAt = now
        guard PersistenceService.save(context: context) else { return false }
        let groupID = group.id
        let options = (try? context.fetch(FetchDescriptor<TripItineraryItem>(
            predicate: #Predicate { $0.choiceGroupID == groupID }
        ))) ?? []
        rescheduleReminders(for: trip, items: options, choiceGroups: [group])
        return true
    }

    @discardableResult
    static func deleteChoiceGroup(
        _ group: TripItineraryChoiceGroup,
        trip: PackingTrip,
        items: [TripItineraryItem],
        context: ModelContext,
        now: Date = Date()
    ) -> Bool {
        guard !trip.isArchived, group.tripID == trip.id else { return false }
        let formerOptions = items.filter { $0.tripID == trip.id && $0.choiceGroupID == group.id }
        for item in formerOptions {
            item.choiceGroupID = nil
            item.updatedAt = now
        }
        context.delete(group)
        trip.updatedAt = now
        guard PersistenceService.save(context: context) else { return false }
        rescheduleReminders(
            for: trip,
            items: formerOptions,
            choiceGroups: []
        )
        return true
    }

    static func sortedItems(_ items: [TripItineraryItem]) -> [TripItineraryItem] {
        items.map { item in
            let scheduleKind = item.scheduleKind
            return (
                item: item,
                rank: scheduleKind.sortRank,
                time: scheduleKind == .timed ? item.startDate?.timeIntervalSinceReferenceDate ?? 0 : 0,
                sortOrder: item.sortOrder,
                title: item.title
            )
        }.sorted {
            ($0.rank, $0.time, $0.sortOrder, $0.title)
                < ($1.rank, $1.time, $1.sortOrder, $1.title)
        }.map(\.item)
    }

    static func reminderIsEligible(
        for item: TripItineraryItem,
        choiceGroups: [TripItineraryChoiceGroup]
    ) -> Bool {
        guard let choiceGroupID = item.choiceGroupID else { return true }
        guard let group = choiceGroups.first(where: { $0.id == choiceGroupID && $0.tripID == item.tripID }) else {
            return false
        }
        return group.selectedItemID == item.id
    }

    static func rescheduleReminders(
        for trip: PackingTrip,
        items: [TripItineraryItem],
        choiceGroups: [TripItineraryChoiceGroup]
    ) {
        let choiceGroupsByID = Dictionary(
            choiceGroups.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for item in items where item.tripID == trip.id {
            let choiceIsSelected = item.choiceGroupID.map {
                choiceGroupsByID[$0]?.selectedItemID == item.id
            } ?? true
            scheduleReminder(for: item, trip: trip, choiceIsSelected: choiceIsSelected)
        }
    }

    private static func rescheduleChoiceGroupReminders(
        groupIDs: Set<UUID>,
        trip: PackingTrip,
        choiceGroups: [TripItineraryChoiceGroup],
        context: ModelContext
    ) {
        guard !groupIDs.isEmpty else { return }
        let tripID = trip.id
        let items = ((try? context.fetch(FetchDescriptor<TripItineraryItem>(
            predicate: #Predicate { $0.tripID == tripID }
        ))) ?? []).filter { item in
            item.choiceGroupID.map(groupIDs.contains) == true
        }
        rescheduleReminders(for: trip, items: items, choiceGroups: choiceGroups)
    }

    private static func normalizedDay(
        _ value: Date?,
        scheduleKind: TripItineraryScheduleKind,
        trip: PackingTrip
    ) -> Date? {
        guard scheduleKind != .unscheduled, let value else { return nil }
        return trip.tripCalendar.startOfDay(for: value)
    }

    private static func destinationIsValid(_ destination: TripDestinationSelection) -> Bool {
        guard !destination.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        switch (destination.latitude, destination.longitude) {
        case (nil, nil):
            break
        case let (latitude?, longitude?):
            guard latitude.isFinite, longitude.isFinite,
                  (-90...90).contains(latitude), (-180...180).contains(longitude) else {
                return false
            }
        default:
            return false
        }
        if let identifier = destination.timeZoneIdentifier,
           TimeZone(identifier: identifier) == nil {
            return false
        }
        return true
    }

    private static func align(
        _ item: TripItineraryItem,
        withGroupDay groupDay: Date?,
        previousGroupDay: Date?,
        trip: PackingTrip,
        now: Date
    ) {
        guard let groupDay else {
            item.scheduleKind = .unscheduled
            item.scheduledDay = nil
            item.startDate = nil
            item.endDate = nil
            item.reminderEnabled = false
            item.updatedAt = now
            return
        }

        let normalizedGroupDay = trip.tripCalendar.startOfDay(for: groupDay)
        let sourceDay = item.scheduledDay ?? previousGroupDay ?? normalizedGroupDay
        if item.scheduleKind == .unscheduled {
            item.scheduleKind = .anytime
        }
        if item.scheduleKind == .timed {
            item.startDate = item.startDate.map {
                movingScheduledDate(
                    $0,
                    from: sourceDay,
                    to: normalizedGroupDay,
                    sourceScheduleCalendar: trip.tripCalendar,
                    destinationScheduleCalendar: trip.tripCalendar,
                    valueTimeZoneIdentifier: item.startTimeZoneIdentifier
                )
            }
            item.endDate = item.endDate.map {
                movingScheduledDate(
                    $0,
                    from: sourceDay,
                    to: normalizedGroupDay,
                    sourceScheduleCalendar: trip.tripCalendar,
                    destinationScheduleCalendar: trip.tripCalendar,
                    valueTimeZoneIdentifier: item.endTimeZoneIdentifier
                )
            }
        }
        item.scheduledDay = normalizedGroupDay
        item.updatedAt = now
    }

    private static func insertLinks(
        _ links: [TripItineraryLinkInput],
        item: TripItineraryItem,
        trip: PackingTrip,
        context: ModelContext,
        caregiverName: String,
        now: Date
    ) {
        for (index, value) in links.enumerated() {
            let title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = value.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            context.insert(TripItineraryLink(
                householdID: trip.householdID,
                tripID: trip.id,
                itineraryItemID: item.id,
                title: title.isEmpty ? "Open Link" : title,
                urlString: url,
                createdBy: caregiverName,
                createdAt: now,
                updatedAt: now,
                sortOrder: index
            ))
        }
    }

    private static func scheduleReminder(
        for item: TripItineraryItem,
        trip: PackingTrip,
        choiceGroups: [TripItineraryChoiceGroup]
    ) {
        let choiceIsSelected = reminderIsEligible(for: item, choiceGroups: choiceGroups)
        scheduleReminder(for: item, trip: trip, choiceIsSelected: choiceIsSelected)
    }

    private static func scheduleReminder(
        for item: TripItineraryItem,
        trip: PackingTrip,
        choiceIsSelected: Bool
    ) {
        Task {
            await NotificationManager.shared.rescheduleItineraryItemReminder(
                item: item,
                trip: trip,
                choiceIsSelected: choiceIsSelected
            )
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
