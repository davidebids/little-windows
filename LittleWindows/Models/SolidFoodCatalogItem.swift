import Foundation
import SwiftData

@Model
final class SolidFoodCatalogItem {
    var id: UUID = UUID()
    var name: String = ""
    var normalizedName: String = ""
    var photoAttachmentID: UUID?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        photoAttachmentID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        let cleanedName = SolidFoodSelection.cleanedName(name)
        self.id = id
        self.name = cleanedName
        self.normalizedName = SolidFoodSelection.normalizedName(cleanedName)
        self.photoAttachmentID = photoAttachmentID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum SolidFoodIdeaCategory: String, CaseIterable, Identifiable {
    case fruit
    case vegetables
    case proteinAndIron
    case grainsAndStarches
    case dairy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fruit: "Fruit"
        case .vegetables: "Vegetables"
        case .proteinAndIron: "Protein & iron"
        case .grainsAndStarches: "Grains & starches"
        case .dairy: "Dairy"
        }
    }
}

struct SolidFoodIdea: Identifiable, Equatable {
    var id: String { SolidFoodSelection.normalizedName(name) }
    var name: String
    var emoji: String
    var category: SolidFoodIdeaCategory
}

enum SolidFoodIdeaCatalog {
    static let foods: [SolidFoodIdea] = [
        // Fruit
        SolidFoodIdea(name: "Avocado", emoji: "🥑", category: .fruit),
        SolidFoodIdea(name: "Banana", emoji: "🍌", category: .fruit),
        SolidFoodIdea(name: "Apple", emoji: "🍎", category: .fruit),
        SolidFoodIdea(name: "Pear", emoji: "🍐", category: .fruit),
        SolidFoodIdea(name: "Peach", emoji: "🍑", category: .fruit),
        SolidFoodIdea(name: "Mango", emoji: "🥭", category: .fruit),
        SolidFoodIdea(name: "Strawberry", emoji: "🍓", category: .fruit),
        SolidFoodIdea(name: "Blueberry", emoji: "🫐", category: .fruit),
        SolidFoodIdea(name: "Prune", emoji: "🟣", category: .fruit),
        SolidFoodIdea(name: "Plum", emoji: "🟣", category: .fruit),
        SolidFoodIdea(name: "Orange", emoji: "🍊", category: .fruit),
        SolidFoodIdea(name: "Melon", emoji: "🍈", category: .fruit),

        // Vegetables
        SolidFoodIdea(name: "Sweet potato", emoji: "🍠", category: .vegetables),
        SolidFoodIdea(name: "Carrot", emoji: "🥕", category: .vegetables),
        SolidFoodIdea(name: "Peas", emoji: "🫛", category: .vegetables),
        SolidFoodIdea(name: "Green beans", emoji: "🫛", category: .vegetables),
        SolidFoodIdea(name: "Spinach", emoji: "🥬", category: .vegetables),
        SolidFoodIdea(name: "Broccoli", emoji: "🥦", category: .vegetables),
        SolidFoodIdea(name: "Butternut squash", emoji: "🎃", category: .vegetables),
        SolidFoodIdea(name: "Zucchini", emoji: "🥒", category: .vegetables),
        SolidFoodIdea(name: "Cauliflower", emoji: "🥦", category: .vegetables),
        SolidFoodIdea(name: "Potato", emoji: "🥔", category: .vegetables),
        SolidFoodIdea(name: "Beet", emoji: "🟣", category: .vegetables),
        SolidFoodIdea(name: "Pumpkin", emoji: "🎃", category: .vegetables),

        // Protein and iron-rich foods, including common allergen food families.
        SolidFoodIdea(name: "Egg", emoji: "🥚", category: .proteinAndIron),
        SolidFoodIdea(name: "Chicken", emoji: "🍗", category: .proteinAndIron),
        SolidFoodIdea(name: "Beef", emoji: "🥩", category: .proteinAndIron),
        SolidFoodIdea(name: "Turkey", emoji: "🍗", category: .proteinAndIron),
        SolidFoodIdea(name: "Lamb", emoji: "🍖", category: .proteinAndIron),
        SolidFoodIdea(name: "Salmon", emoji: "🐟", category: .proteinAndIron),
        SolidFoodIdea(name: "White fish", emoji: "🐟", category: .proteinAndIron),
        SolidFoodIdea(name: "Shrimp", emoji: "🍤", category: .proteinAndIron),
        SolidFoodIdea(name: "Lentils", emoji: "🫘", category: .proteinAndIron),
        SolidFoodIdea(name: "Beans", emoji: "🫘", category: .proteinAndIron),
        SolidFoodIdea(name: "Chickpeas", emoji: "🫘", category: .proteinAndIron),
        SolidFoodIdea(name: "Tofu", emoji: "🍱", category: .proteinAndIron),
        SolidFoodIdea(name: "Hummus", emoji: "🧆", category: .proteinAndIron),
        SolidFoodIdea(name: "Peanut butter", emoji: "🥜", category: .proteinAndIron),
        SolidFoodIdea(name: "Almond butter", emoji: "🌰", category: .proteinAndIron),
        SolidFoodIdea(name: "Tahini", emoji: "🫙", category: .proteinAndIron),

        // Grains and starches
        SolidFoodIdea(name: "Oatmeal", emoji: "🥣", category: .grainsAndStarches),
        SolidFoodIdea(name: "Infant cereal", emoji: "🥣", category: .grainsAndStarches),
        SolidFoodIdea(name: "Pasta", emoji: "🍝", category: .grainsAndStarches),
        SolidFoodIdea(name: "Toast", emoji: "🍞", category: .grainsAndStarches),
        SolidFoodIdea(name: "Rice", emoji: "🍚", category: .grainsAndStarches),
        SolidFoodIdea(name: "Quinoa", emoji: "🌾", category: .grainsAndStarches),
        SolidFoodIdea(name: "Barley cereal", emoji: "🌾", category: .grainsAndStarches),

        // Pasteurized dairy foods without added sugar are distinct from cow's milk as a drink.
        SolidFoodIdea(name: "Yogurt", emoji: "🥛", category: .dairy),
        SolidFoodIdea(name: "Cheese", emoji: "🧀", category: .dairy),
        SolidFoodIdea(name: "Cottage cheese", emoji: "🥣", category: .dairy)
    ]
}

enum SolidFoodSelection {
    static func names(from foodDescription: String?) -> [String] {
        guard let foodDescription else { return [] }
        return deduplicatedNames(
            foodDescription
                .components(separatedBy: CharacterSet(charactersIn: ",\n"))
                .map(cleanedName)
        )
    }

    static func description(from names: [String]) -> String? {
        let names = deduplicatedNames(names)
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    static func cleanedName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func normalizedName(_ value: String) -> String {
        cleanedName(value).folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    static func deduplicatedNames(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let cleaned = cleanedName(value)
            guard !cleaned.isEmpty else { return nil }
            return seen.insert(normalizedName(cleaned)).inserted ? cleaned : nil
        }
    }
}
