import Foundation

/// A pre-built habit/chore the user can add to their schedule with one tap.
struct TaskTemplate: Identifiable, Codable, Hashable {
    let id: String
    let titleKey: String          // localization key; English value is in the catalog
    let detailsKey: String
    let kind: TaskKind
    let category: TaskCategory
    let symbolName: String
    let colorHue: Double
    let defaultFrequency: FrequencyRule

    var title: String { String(localized: String.LocalizationValue(titleKey)) }
    var details: String { String(localized: String.LocalizationValue(detailsKey)) }

    /// Builds a fresh `TaskItem` the user owns and can edit independently.
    func makeTaskItem(startDate: Date = .now) -> TaskItem {
        TaskItem(
            title: title,
            details: details,
            kind: kind,
            category: category,
            frequency: defaultFrequency,
            symbolName: symbolName,
            colorHue: colorHue,
            startDate: startDate,
            createdFromTemplateID: id
        )
    }
}

/// Loads and groups the built-in templates bundled in `Templates.json`.
enum TemplateLibrary {
    static let all: [TaskTemplate] = load()

    static func byCategory() -> [(category: TaskCategory, templates: [TaskTemplate])] {
        TaskCategory.allCases.compactMap { cat in
            let items = all.filter { $0.category == cat }
            return items.isEmpty ? nil : (cat, items)
        }
    }

    private static func load() -> [TaskTemplate] {
        guard let url = Bundle.main.url(forResource: "Templates", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("Templates.json missing from bundle")
            return []
        }
        do {
            return try JSONDecoder().decode([TaskTemplate].self, from: data)
        } catch {
            assertionFailure("Failed to decode Templates.json: \(error)")
            return []
        }
    }
}
