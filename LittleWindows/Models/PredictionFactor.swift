import Foundation
import SwiftData

@Model
final class PredictionFactor {
    var id: UUID = UUID()
    var name: String = ""
    var valueDescription: String = ""
    var impactMinutes: Double = 0
    var confidenceImpact: Double = 0
    var explanation: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        valueDescription: String,
        impactMinutes: Double,
        confidenceImpact: Double,
        explanation: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.valueDescription = valueDescription
        self.impactMinutes = impactMinutes
        self.confidenceImpact = confidenceImpact
        self.explanation = explanation
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct PredictionFactorValue: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var valueDescription: String
    var impactMinutes: Double
    var confidenceImpact: Double
    var explanation: String
}
