import SwiftUI

struct EventRow: View {
    let event: BabyEvent

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: event.type.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(event.type.tint)
                .frame(width: 42, height: 42)
                .background(event.type.tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(event.displayTitle)
                        .font(.body.weight(.semibold))
                    if event.isActiveTimer {
                        Text("LIVE")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green, in: Capsule())
                    }
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let notes = event.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 7)
    }

    private var detail: String {
        var pieces = [DateFormatting.time.string(from: event.startDate)]
        if let endDate = event.endDate {
            pieces[0] += "-\(DateFormatting.time.string(from: endDate))"
        }
        if let duration = event.duration, duration >= 60 {
            pieces.append(DurationFormatting.string(seconds: duration))
        }
        if event.type == .feed, let amount = event.amountOz {
            pieces.append(String(format: "%.1f oz", amount))
        }
        if event.type == .nursing, event.totalNursingDurationSeconds > 0 {
            pieces.append(DurationFormatting.string(seconds: event.totalNursingDurationSeconds))
        }
        if let caregiver = event.caregiverName, !caregiver.isEmpty {
            pieces.append(caregiver)
        }
        return pieces.joined(separator: " / ")
    }

}
