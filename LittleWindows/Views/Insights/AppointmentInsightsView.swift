import SwiftUI

struct AppointmentInsightsView: View {
    let appointments: [DoctorAppointment]
    let period: ClosedRange<Date>

    private var upcoming: [DoctorAppointment] {
        appointments
            .filter { !$0.isCompleted && $0.startDate >= Date() }
            .sorted { $0.startDate < $1.startDate }
    }

    private var completedInPeriod: [DoctorAppointment] {
        appointments.filter {
            $0.isCompleted && period.contains(Calendar.current.startOfDay(for: $0.startDate))
        }
    }

    private var lastPediatrician: DoctorAppointment? {
        appointments
            .filter { $0.appointmentType == .pediatrician || $0.appointmentType == .wellnessCheck }
            .filter { $0.startDate <= Date() }
            .sorted { $0.startDate > $1.startDate }
            .first
    }

    var body: some View {
        Group {
            InsightMetricGrid(metrics: [
                InsightMetric(
                    title: "Upcoming",
                    value: "\(upcoming.count)",
                    interpretation: "Scheduled appointments that are not marked complete.",
                    systemImage: "calendar.badge.clock"
                ),
                InsightMetric(
                    title: "Completed visits",
                    value: "\(completedInPeriod.count)",
                    interpretation: "Completed visits within the selected Insights range.",
                    systemImage: "checkmark.circle.fill"
                ),
                InsightMetric(
                    title: "Next visit",
                    value: upcoming.first.map {
                        DateFormatting.day.string(from: $0.startDate)
                    } ?? "-",
                    interpretation: upcoming.first?.displayTitle ?? "No upcoming visit scheduled.",
                    systemImage: "arrow.forward.circle.fill"
                ),
                InsightMetric(
                    title: "Last pediatrician",
                    value: lastPediatrician.map {
                        DateFormatting.day.string(from: $0.startDate)
                    } ?? "-",
                    interpretation: lastPediatrician?.displayTitle ?? "No pediatrician visit logged.",
                    systemImage: "stethoscope"
                ),
                InsightMetric(
                    title: "Vaccine notes",
                    value: "\(appointments.filter { ($0.vaccinesGiven ?? "").isEmpty == false }.count)",
                    interpretation: "Visits with vaccine notes entered.",
                    systemImage: "syringe.fill"
                ),
                InsightMetric(
                    title: "Linked growth",
                    value: "\(appointments.filter { $0.growthEntryID != nil }.count)",
                    interpretation: "Appointments linked to a growth entry.",
                    systemImage: "ruler.fill"
                )
            ])

            VStack(alignment: .leading, spacing: 14) {
                Text("Upcoming appointments")
                    .font(.headline)
                if upcoming.isEmpty {
                    Text("No upcoming appointments scheduled.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(upcoming.prefix(5)) { appointment in
                        AppointmentCard(appointment: appointment, style: .row)
                    }
                }
                Text("Appointment insights are organizational only and do not interpret symptoms, medicines, vaccines, or visit instructions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .appSurface()
        }
    }
}
