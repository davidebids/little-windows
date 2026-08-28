import XCTest
import SwiftData
@testable import LittleWindows

final class CareStoryServiceTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testRepeatedSymptomsAfterPlanChangeProduceNonCausalTimingObservation() {
        let changeDate = day(3)
        let snapshot = CareStoryService.makeSnapshot(
            events: [
                symptom("Dizziness", day: 4),
                symptom("Dizziness", day: 6),
                symptom("Dizziness", day: 8),
                symptom("Headache", day: 5)
            ],
            medicationChanges: [CareStoryMedicationChangeRecord(
                date: changeDate,
                medicationName: "Sample Medication",
                changeKind: .updated,
                source: .clinician,
                beforeDose: "5 mg",
                afterDose: "10 mg"
            )],
            doseRecords: [],
            startDate: start,
            endDate: day(30),
            calendar: calendar
        )

        let observation = snapshot.observations.first { $0.kind == .timing }
        XCTAssertEqual(
            observation?.statement,
            "3 dizziness entries were recorded in the seven days after Sample Medication’s plan changed."
        )
        XCTAssertTrue(observation?.caution.contains("does not show what caused") == true)
    }

    func testSingleSymptomDoesNotProduceWeakTimingObservation() {
        let snapshot = CareStoryService.makeSnapshot(
            events: [symptom("Dizziness", day: 4)],
            medicationChanges: [CareStoryMedicationChangeRecord(
                date: day(3),
                medicationName: "Sample Medication",
                changeKind: .updated,
                source: .caregiver
            )],
            doseRecords: [],
            startDate: start,
            endDate: day(30),
            calendar: calendar
        )

        XCTAssertFalse(snapshot.observations.contains { $0.kind == .timing })
    }

    func testPainComparisonUsesRecordedDaysAndIncludesLimitation() {
        let snapshot = CareStoryService.makeSnapshot(
            events: [
                pain(2, day: 2), activity(day: 2),
                pain(4, day: 4), activity(day: 4),
                pain(7, day: 6),
                pain(5, day: 8)
            ],
            medicationChanges: [],
            doseRecords: [],
            startDate: start,
            endDate: day(30),
            calendar: calendar
        )

        let observation = snapshot.observations.first { $0.kind == .comparison }
        XCTAssertEqual(
            observation?.statement,
            "Recorded pain scores averaged lower on days that also had activity logs (3.0 vs 6.0 on other recorded days)."
        )
        XCTAssertTrue(observation?.caution.contains("does not show that activity changed pain") == true)
    }

    func testBloodPressureAndMissedDosesArePresentedForDiscussion() {
        let snapshot = CareStoryService.makeSnapshot(
            events: [
                vital("Blood pressure 120/80", day: 3),
                vital("Blood pressure 118/76", day: 5)
            ],
            medicationChanges: [],
            doseRecords: [
                CareStoryDoseRecord(
                    date: day(4),
                    medicationName: "Sample Medication",
                    status: .missed,
                    reason: .asleep
                )
            ],
            startDate: start,
            endDate: day(30),
            calendar: calendar
        )

        let observation = snapshot.observations.first { $0.kind == .discussion }
        XCTAssertEqual(
            observation?.statement,
            "2 blood-pressure readings and 1 missed dose are shown together for discussion at the next visit."
        )
        XCTAssertTrue(observation?.caution.contains("does not imply") == true)
    }

    func testTimelineShowsPlanChangesAndExceptionalDosesButNotRoutineTakenDoses() {
        let snapshot = CareStoryService.makeSnapshot(
            events: [],
            medicationChanges: [CareStoryMedicationChangeRecord(
                date: day(3),
                medicationName: "Sample Medication",
                changeKind: .updated,
                source: .prescriptionLabel,
                beforeDose: "1 tablet",
                afterDose: "2 tablets"
            )],
            doseRecords: [
                CareStoryDoseRecord(
                    date: day(4),
                    medicationName: "Sample Medication",
                    status: .taken
                ),
                CareStoryDoseRecord(
                    date: day(5),
                    medicationName: "Sample Medication",
                    status: .taken,
                    timing: .late
                )
            ],
            startDate: start,
            endDate: day(30),
            calendar: calendar
        )

        XCTAssertEqual(snapshot.timelineItems.count, 2)
        XCTAssertTrue(snapshot.timelineItems.contains {
            $0.isMedicationPlanChange && $0.title == "Dose or schedule changed for Sample Medication"
        })
        XCTAssertTrue(snapshot.timelineItems.contains { $0.title == "Sample Medication: Taken late" })
    }

    func testGeneratedStatementsAvoidDiagnosticOrCausalClaims() {
        let snapshot = CareStoryService.makeSnapshot(
            events: [
                symptom("Dizziness", day: 4),
                symptom("Dizziness", day: 5),
                pain(2, day: 2), activity(day: 2),
                pain(3, day: 4), activity(day: 4),
                pain(7, day: 6), pain(8, day: 8),
                vital("Blood pressure 120/80", day: 3)
            ],
            medicationChanges: [CareStoryMedicationChangeRecord(
                date: day(3),
                medicationName: "Sample Medication",
                changeKind: .updated,
                source: .clinician
            )],
            doseRecords: [CareStoryDoseRecord(
                date: day(4),
                medicationName: "Sample Medication",
                status: .missed
            )],
            startDate: start,
            endDate: day(30),
            calendar: calendar
        )

        let prohibitedClaims = ["caused", "causes", "diagnosis", "treat", "because of"]
        for statement in snapshot.observations.map(\.statement) {
            for claim in prohibitedClaims {
                XCTAssertFalse(statement.localizedCaseInsensitiveContains(claim), "Unsafe claim: \(statement)")
            }
        }
    }

    func testPainAndActivityDataIsAggregatedByRecordedDay() {
        let snapshot = CareStoryService.makeSnapshot(
            events: [
                pain(2, day: 2),
                pain(4, day: 2),
                activity(day: 2),
                activity(day: 2),
                activity(day: 4)
            ],
            medicationChanges: [],
            doseRecords: [],
            startDate: start,
            endDate: day(30),
            calendar: calendar
        )

        XCTAssertEqual(snapshot.painActivityDays.count, 2)
        XCTAssertEqual(snapshot.painActivityDays[0].averagePainScore ?? -1, 3, accuracy: 0.001)
        XCTAssertEqual(snapshot.painActivityDays[0].painEntryCount, 2)
        XCTAssertEqual(snapshot.painActivityDays[0].activityEntryCount, 2)
        XCTAssertNil(snapshot.painActivityDays[1].averagePainScore)
        XCTAssertEqual(snapshot.painActivityDays[1].activityEntryCount, 1)
    }

    func testBloodPressureReadingsAndMissedDoseMarkersPreserveExactTiming() {
        let readingID = UUID()
        let missedID = UUID()
        let snapshot = CareStoryService.makeSnapshot(
            events: [CareStoryEventRecord(
                id: readingID,
                date: day(3),
                category: .vital,
                title: "Blood Pressure: 122/78 mmHg",
                systolicBloodPressure: 122,
                diastolicBloodPressure: 78
            )],
            medicationChanges: [],
            doseRecords: [
                CareStoryDoseRecord(
                    id: missedID,
                    date: day(4),
                    medicationName: "Sample Medication",
                    status: .missed,
                    reason: .away
                ),
                CareStoryDoseRecord(
                    date: day(5),
                    medicationName: "Sample Medication",
                    status: .held
                )
            ],
            startDate: start,
            endDate: day(30),
            calendar: calendar
        )

        XCTAssertEqual(snapshot.bloodPressureReadings.count, 1)
        XCTAssertEqual(snapshot.bloodPressureReadings.first?.id, readingID)
        XCTAssertEqual(snapshot.bloodPressureReadings.first?.systolic, 122)
        XCTAssertEqual(snapshot.bloodPressureReadings.first?.diastolic, 78)
        XCTAssertEqual(snapshot.missedDoseMarkers.count, 1)
        XCTAssertEqual(snapshot.missedDoseMarkers.first?.id, missedID)
        XCTAssertEqual(snapshot.missedDoseMarkers.first?.date, day(4))
    }

    func testMedicationChangeCreatesBeforeAndAfterStoryChapter() {
        let snapshot = CareStoryService.makeSnapshot(
            events: [
                symptom("Dizziness", day: 5),
                symptom("Dizziness", day: 11),
                symptom("Dizziness", day: 12),
                pain(3, day: 6),
                pain(5, day: 11),
                activity(day: 7),
                activity(day: 13),
                CareStoryEventRecord(
                    date: day(8),
                    category: .vital,
                    title: "Blood Pressure: 118/76 mmHg",
                    systolicBloodPressure: 118,
                    diastolicBloodPressure: 76
                )
            ],
            medicationChanges: [CareStoryMedicationChangeRecord(
                date: day(10),
                medicationName: "Sample Medication",
                changeKind: .updated,
                source: .clinician,
                beforeDose: "5 mg",
                afterDose: "10 mg"
            )],
            doseRecords: [
                CareStoryDoseRecord(
                    date: day(8),
                    medicationName: "Sample Medication",
                    status: .missed
                ),
                CareStoryDoseRecord(
                    date: day(12),
                    medicationName: "Sample Medication",
                    status: .skipped
                )
            ],
            startDate: start,
            endDate: day(30),
            calendar: calendar
        )

        let chapter = snapshot.chapters.first { $0.kind == .medicationChange }
        XCTAssertEqual(chapter?.title, "Dose or schedule changed for Sample Medication")
        XCTAssertEqual(chapter?.changeDetail, "Dose: 5 mg → 10 mg")
        XCTAssertEqual(chapter?.before.symptomEntries, 1)
        XCTAssertEqual(chapter?.after.symptomEntries, 2)
        XCTAssertEqual(chapter?.before.averagePainScore ?? -1, 3, accuracy: 0.001)
        XCTAssertEqual(chapter?.after.averagePainScore ?? -1, 5, accuracy: 0.001)
        XCTAssertEqual(chapter?.before.missedDoseCount, 1)
        XCTAssertEqual(chapter?.after.missedDoseCount, 1)
        XCTAssertTrue(chapter?.signals.contains { $0.dayOffset < 0 } == true)
        XCTAssertTrue(chapter?.signals.contains { $0.dayOffset > 0 } == true)
        XCTAssertTrue(chapter?.sourceRecords.contains {
            $0.category == .medication && $0.title == "Sample Medication: Skipped"
        } == true)
        XCTAssertTrue(chapter?.highlights.contains { $0.contains("2 dizziness entries") } == true)
        XCTAssertFalse(chapter?.highlights.joined().localizedCaseInsensitiveContains("caused") == true)
    }

    func testRepeatedSymptomsCreateACareEpisodeWithoutMedicationChanges() {
        let snapshot = CareStoryService.makeSnapshot(
            events: [
                symptom("Dizziness", day: 10),
                symptom("Dizziness", day: 12),
                symptom("Dizziness", day: 14),
                activity(day: 8),
                activity(day: 15)
            ],
            medicationChanges: [],
            doseRecords: [],
            startDate: start,
            endDate: day(30),
            calendar: calendar
        )

        let chapter = snapshot.chapters.first { $0.kind == .symptomEpisode }
        XCTAssertEqual(chapter?.title, "Dizziness episode")
        XCTAssertEqual(chapter?.sourceLabel, "Detected from symptom entries")
        XCTAssertEqual(chapter?.changeDetail, "3 entries across 3 recorded days")
        XCTAssertEqual(chapter?.beforeLabel, "Before")
        XCTAssertEqual(chapter?.afterLabel, "After")
        XCTAssertEqual(chapter?.medicationName, "")
    }

    func testCompletedAppointmentCreatesACareVisitChapter() {
        let snapshot = CareStoryService.makeSnapshot(
            events: [
                pain(3, day: 7),
                pain(5, day: 12)
            ],
            medicationChanges: [],
            doseRecords: [],
            appointments: [CareStoryAppointmentRecord(
                date: day(10),
                title: "Follow-up visit",
                typeName: "Primary care",
                summary: "Reviewed current routines and follow-up questions."
            )],
            startDate: start,
            endDate: day(30),
            calendar: calendar
        )

        let chapter = snapshot.chapters.first { $0.kind == .appointment }
        XCTAssertEqual(chapter?.title, "Follow-up visit")
        XCTAssertEqual(chapter?.sourceLabel, "Primary care")
        XCTAssertEqual(
            chapter?.changeDetail,
            "Reviewed current routines and follow-up questions."
        )
        XCTAssertEqual(chapter?.before.averagePainScore ?? -1, 3, accuracy: 0.001)
        XCTAssertEqual(chapter?.after.averagePainScore ?? -1, 5, accuracy: 0.001)
        XCTAssertEqual(chapter?.sourceRecords.count, 2)
        XCTAssertEqual(
            chapter?.domainShifts.first { $0.domain == .pain }?.direction,
            .insufficient,
            "One pain day on each side is context, not a reliable shift."
        )
        XCTAssertEqual(
            chapter?.domainShifts.first { $0.domain == .symptoms }?.direction,
            .insufficient
        )
        XCTAssertEqual(
            chapter?.domainShifts.first { $0.domain == .activity }?.direction,
            .insufficient
        )
    }

    func testEpisodeEvidenceAndDomainShiftsStayDescriptiveAndNonCausal() {
        let snapshot = CareStoryService.makeSnapshot(
            events: [
                symptom("Fatigue", day: 4),
                pain(2, day: 5),
                pain(3, day: 8),
                sleep(hours: 7.5, day: 6),
                sleep(hours: 7, day: 8),
                activity(day: 7),
                bloodPressure(116, 74, day: 7),
                bloodPressure(118, 76, day: 8),
                symptom("Fatigue", day: 11),
                symptom("Fatigue", day: 13),
                pain(6, day: 12),
                pain(7, day: 14),
                sleep(hours: 5.5, day: 13),
                sleep(hours: 6, day: 15),
                bloodPressure(126, 82, day: 14),
                bloodPressure(128, 84, day: 16)
            ],
            medicationChanges: [],
            doseRecords: [
                CareStoryDoseRecord(
                    date: day(7),
                    medicationName: "Sample Medication",
                    status: .taken
                ),
                CareStoryDoseRecord(
                    date: day(8),
                    medicationName: "Sample Medication",
                    status: .taken
                ),
                CareStoryDoseRecord(
                    date: day(12),
                    medicationName: "Sample Medication",
                    status: .missed
                ),
                CareStoryDoseRecord(
                    date: day(14),
                    medicationName: "Sample Medication",
                    status: .taken
                )
            ],
            appointments: [CareStoryAppointmentRecord(
                date: day(10),
                title: "Care review",
                typeName: "Primary care"
            )],
            startDate: start,
            endDate: day(30),
            calendar: calendar
        )

        let chapter = try! XCTUnwrap(snapshot.chapters.first { $0.kind == .appointment })
        XCTAssertEqual(
            chapter.domainShifts.first { $0.domain == .pain }?.direction,
            .higher
        )
        XCTAssertEqual(
            chapter.domainShifts.first { $0.domain == .sleep }?.direction,
            .lower
        )
        XCTAssertEqual(
            chapter.domainShifts.first { $0.domain == .bloodPressure }?.direction,
            .higher
        )
        XCTAssertEqual(
            chapter.domainShifts.first { $0.domain == .doseConsistency }?.changeLabel,
            "More exceptions"
        )
        XCTAssertGreaterThanOrEqual(chapter.evidence.comparableDomainCount, 4)
        XCTAssertFalse(chapter.pulseHeadline.isEmpty)
        XCTAssertFalse(chapter.discussionPrompts.isEmpty)

        let generatedLanguage = ([chapter.pulseHeadline]
            + chapter.discussionPrompts
            + chapter.domainShifts.map(\.insight))
            .joined(separator: " ")
        for unsafeClaim in ["caused", "because of", "diagnosis", "better", "worse"] {
            XCTAssertFalse(
                generatedLanguage.localizedCaseInsensitiveContains(unsafeClaim),
                "Unsafe Care Story claim: \(generatedLanguage)"
            )
        }
    }

    func testContinuousSymptomHistoryProducesAtMostTwoRecentChaptersPerSymptom() {
        let events = stride(from: 2, through: 28, by: 2).map {
            symptom("Fatigue", day: $0)
        }
        let snapshot = CareStoryService.makeSnapshot(
            events: events,
            medicationChanges: [],
            doseRecords: [],
            startDate: start,
            endDate: day(40),
            calendar: calendar
        )

        let fatigueChapters = snapshot.chapters.filter { $0.kind == .symptomEpisode }
        XCTAssertEqual(fatigueChapters.count, 2)
        XCTAssertTrue(fatigueChapters.allSatisfy { $0.title == "Fatigue episode" })
        XCTAssertTrue(fatigueChapters[0].date > fatigueChapters[1].date)
    }

    func testSymptomSeverityUsesRecordedIntensityWhenEnoughDaysExist() {
        let snapshot = CareStoryService.makeSnapshot(
            events: [
                symptom("Fatigue", severity: 1, day: 5),
                symptom("Fatigue", severity: 2, day: 7),
                symptom("Fatigue", severity: 4, day: 12),
                symptom("Fatigue", severity: 5, day: 14)
            ],
            medicationChanges: [],
            doseRecords: [],
            appointments: [CareStoryAppointmentRecord(
                date: day(10),
                title: "Care review",
                typeName: "Primary Care"
            )],
            startDate: start,
            endDate: day(30),
            calendar: calendar
        )

        let chapter = try! XCTUnwrap(snapshot.chapters.first { $0.kind == .appointment })
        let shift = try! XCTUnwrap(
            chapter.domainShifts.first { $0.domain == .symptoms }
        )
        XCTAssertEqual(shift.direction, .higher)
        XCTAssertEqual(shift.beforeValue, "1.5/5 avg")
        XCTAssertEqual(shift.afterValue, "4.5/5 avg")
    }

    func testSnapshotDisclosesWhenWorkerLimitsInputData() {
        let snapshot = CareStoryService.makeSnapshot(
            events: [],
            medicationChanges: [],
            doseRecords: [],
            dataWasLimited: true,
            startDate: start,
            endDate: day(30),
            calendar: calendar
        )

        XCTAssertTrue(snapshot.dataWasLimited)
    }

    func testChapterOnlySnapshotSkipsUnusedOverviewCollections() {
        let snapshot = CareStoryService.makeSnapshot(
            events: [symptom("Fatigue", day: 4), symptom("Fatigue", day: 6)],
            medicationChanges: [],
            doseRecords: [],
            content: .chaptersOnly,
            startDate: start,
            endDate: day(30),
            calendar: calendar
        )

        XCTAssertFalse(snapshot.chapters.isEmpty)
        XCTAssertTrue(snapshot.timelineItems.isEmpty)
        XCTAssertTrue(snapshot.observations.isEmpty)
        XCTAssertTrue(snapshot.painActivityDays.isEmpty)
        XCTAssertTrue(snapshot.bloodPressureReadings.isEmpty)
        XCTAssertTrue(snapshot.missedDoseMarkers.isEmpty)
    }

    @MainActor
    func testDiscussionQuestionsAppendToAppointmentWithoutDuplicates() throws {
        let container = try ModelContainer(
            for: DoctorAppointment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let appointment = DoctorAppointment(
            title: "Follow-up",
            questionsToAsk: "Does the recorded pain shift match day-to-day experience?"
        )
        context.insert(appointment)
        XCTAssertTrue(PersistenceService.save(context: context))

        let added = HouseholdAttentionService.addAppointmentQuestions(
            [
                "Does the recorded pain shift match day-to-day experience?",
                "Was anything else different on the days when sleep changed?"
            ],
            to: appointment,
            context: context,
            now: day(1)
        )

        XCTAssertEqual(added, 1)
        XCTAssertEqual(
            AppointmentQuestionList.parse(appointment.questionsToAsk),
            [
                "Does the recorded pain shift match day-to-day experience?",
                "Was anything else different on the days when sleep changed?"
            ]
        )
        XCTAssertEqual(
            HouseholdAttentionService.addAppointmentQuestions(
                ["Was anything else different on the days when sleep changed?"],
                to: appointment,
                context: context
            ),
            0
        )
    }

    func testRecentMedicationChangeUsesIncompleteAfterWindowLabel() {
        let snapshot = CareStoryService.makeSnapshot(
            events: [
                symptom("Fatigue", day: 25),
                symptom("Dizziness", day: 28)
            ],
            medicationChanges: [CareStoryMedicationChangeRecord(
                date: day(27),
                medicationName: "Sample Medication",
                changeKind: .stopped,
                source: .dischargePaperwork
            )],
            doseRecords: [],
            startDate: start,
            endDate: day(30),
            calendar: calendar
        )

        XCTAssertEqual(snapshot.chapters.count, 1)
        XCTAssertFalse(snapshot.chapters[0].afterWindowIsComplete)
        XCTAssertEqual(
            snapshot.chapters[0].domainShifts.first { $0.domain == .symptoms }?.direction,
            .insufficient,
            "Partial follow-up windows must not compare raw symptom counts with a full week."
        )
    }

    func testProductionScaleChapterSnapshotPerformance() {
        let interval = Double(180 * 24 * 60 * 60) / 5_000
        let events = (0..<5_000).map { index in
            let date = start.addingTimeInterval(Double(index) * interval)
            return switch index % 6 {
            case 0:
                CareStoryEventRecord(
                    date: date,
                    category: .symptom,
                    title: "Fatigue",
                    symptomName: "Fatigue",
                    symptomSeverity: index % 5
                )
            case 1:
                CareStoryEventRecord(
                    date: date,
                    category: .pain,
                    title: "Pain",
                    painScore: index % 10
                )
            case 2:
                CareStoryEventRecord(
                    date: date,
                    category: .sleep,
                    title: "Sleep",
                    durationMinutes: 420
                )
            case 3:
                CareStoryEventRecord(date: date, category: .activity, title: "Walk")
            case 4:
                CareStoryEventRecord(
                    date: date,
                    category: .vital,
                    title: "Blood pressure",
                    systolicBloodPressure: 118 + index % 8,
                    diastolicBloodPressure: 72 + index % 6
                )
            default:
                CareStoryEventRecord(date: date, category: .vital, title: "Heart rate")
            }
        }
        let doses = (0..<5_000).map { index in
            CareStoryDoseRecord(
                date: start.addingTimeInterval(Double(index) * interval),
                medicationName: "Sample Medication",
                status: index.isMultiple(of: 9) ? .missed : .taken,
                reason: index.isMultiple(of: 9) ? .asleep : nil
            )
        }
        let changes = (0..<20).map { index in
            CareStoryMedicationChangeRecord(
                date: day(index * 8 + 2),
                medicationName: "Sample Medication \(index % 3 + 1)",
                changeKind: index == 0 ? .added : .updated,
                source: .clinician
            )
        }
        var chapterCount = 0
        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            chapterCount = CareStoryService.makeSnapshot(
                events: events,
                medicationChanges: changes,
                doseRecords: doses,
                content: .chaptersOnly,
                startDate: start,
                endDate: day(181),
                calendar: calendar
            ).chapters.count
        }

        XCTAssertEqual(chapterCount, 12)
        let regressionStartedAt = ContinuousClock.now
        _ = CareStoryService.makeSnapshot(
            events: events,
            medicationChanges: changes,
            doseRecords: doses,
            content: .chaptersOnly,
            startDate: start,
            endDate: day(181),
            calendar: calendar
        )
        XCTAssertLessThan(
            regressionStartedAt.duration(to: .now),
            .milliseconds(750),
            "A 10,000-record Care Story snapshot must remain comfortably subsecond."
        )
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: start)!
    }

    private func symptom(
        _ name: String,
        severity: Int? = nil,
        day offset: Int
    ) -> CareStoryEventRecord {
        CareStoryEventRecord(
            date: day(offset),
            category: .symptom,
            title: name,
            symptomName: name,
            symptomSeverity: severity
        )
    }

    private func pain(_ score: Int, day offset: Int) -> CareStoryEventRecord {
        CareStoryEventRecord(
            date: day(offset),
            category: .pain,
            title: "Pain \(score)/10",
            painScore: score
        )
    }

    private func activity(day offset: Int) -> CareStoryEventRecord {
        CareStoryEventRecord(date: day(offset), category: .activity, title: "Exercise")
    }

    private func sleep(hours: Double, day offset: Int) -> CareStoryEventRecord {
        CareStoryEventRecord(
            date: day(offset),
            category: .sleep,
            title: "Sleep",
            durationMinutes: hours * 60
        )
    }

    private func bloodPressure(
        _ systolic: Int,
        _ diastolic: Int,
        day offset: Int
    ) -> CareStoryEventRecord {
        CareStoryEventRecord(
            date: day(offset),
            category: .vital,
            title: "Blood Pressure: \(systolic)/\(diastolic) mmHg",
            systolicBloodPressure: systolic,
            diastolicBloodPressure: diastolic
        )
    }

    private func vital(_ title: String, day offset: Int) -> CareStoryEventRecord {
        CareStoryEventRecord(date: day(offset), category: .vital, title: title)
    }
}
