import Foundation
import SwiftUI

enum WidgetSnapshotReader {
    static func read() -> WidgetSnapshot {
        let url = SystemIntegrationConstants.sharedFileURL(
            SystemIntegrationConstants.widgetSnapshotFilename
        )
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }
}

enum LittleWindowsWidgetStyle {
    static let midnight = Color(red: 0.09, green: 0.08, blue: 0.24)
    static let indigo = Color(red: 0.35, green: 0.29, blue: 0.96)
    static let violet = Color(red: 0.54, green: 0.36, blue: 0.98)
    static let lavender = Color(red: 0.78, green: 0.75, blue: 1)

    static var background: some View {
        ZStack {
            LinearGradient(
                colors: [midnight, Color(red: 0.18, green: 0.13, blue: 0.42)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(violet.opacity(0.28))
                .frame(width: 180, height: 180)
                .blur(radius: 18)
                .offset(x: 92, y: -72)
            Circle()
                .fill(Color.blue.opacity(0.15))
                .frame(width: 120, height: 120)
                .blur(radius: 20)
                .offset(x: -86, y: 78)
        }
    }

    static func tint(for typeRawValue: String) -> Color {
        switch typeRawValue {
        case "sleep": lavender
        case "nursing": Color(red: 1, green: 0.58, blue: 0.78)
        case "feed": Color(red: 1, green: 0.72, blue: 0.35)
        case "activity", "tummyTime": Color(red: 0.45, green: 0.9, blue: 0.65)
        case "reading": Color(red: 0.47, green: 0.75, blue: 1)
        case "bath": Color(red: 0.4, green: 0.88, blue: 1)
        default: lavender
        }
    }
}

struct WidgetBrandLabel: View {
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.caption2.weight(.bold))
            if !compact {
                Text("LITTLE WINDOWS")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.7)
            }
        }
        .foregroundStyle(LittleWindowsWidgetStyle.lavender)
    }
}

struct WidgetIconBadge: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 42

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(.white.opacity(0.1), in: Circle())
            .overlay {
                Circle().stroke(tint.opacity(0.28), lineWidth: 1)
            }
    }
}
