import Foundation

/// Models the user picked recently, newest first, kept in user defaults.
enum RecentModelsStore {
    struct Entry: Codable, Equatable {
        let provider: String
        let model: String
    }

    static let defaultsKey = "recentModelSelections"
    static let limit = 5

    static func all(defaults: UserDefaults = .standard) -> [Entry] {
        guard let data = defaults.data(forKey: defaultsKey),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else {
            return []
        }
        return entries
    }

    static func record(provider: String, model: String, defaults: UserDefaults = .standard) {
        guard !provider.isEmpty, !model.isEmpty else { return }
        let entry = Entry(provider: provider, model: model)
        let entries = Array(([entry] + all(defaults: defaults).filter { $0 != entry }).prefix(limit))
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: defaultsKey)
        }
    }
}

/// Models offered by "Retry with another model": favorites first, then recent picks, skipping the current model
/// and providers that aren't configured.
enum RetryModelChoices {
    struct Choices: Equatable {
        var favorites: [ErrorModelChoice]
        var recent: [ErrorModelChoice]

        var isEmpty: Bool { favorites.isEmpty && recent.isEmpty }
    }

    static func build(
        favorites: [(provider: String, model: String)],
        recent: [RecentModelsStore.Entry],
        configuredProviders: [String: String],
        currentProvider: String?,
        currentModel: String?
    ) -> Choices {
        var seen = Set<String>()
        func choice(_ provider: String, _ model: String) -> ErrorModelChoice? {
            guard let name = configuredProviders[provider],
                  !(provider == currentProvider && model == currentModel)
            else {
                return nil
            }
            let choice = ErrorModelChoice(providerType: provider, providerName: name, modelId: model)
            return seen.insert(choice.id).inserted ? choice : nil
        }

        let favoriteChoices = favorites
            .sorted { ($0.provider, $0.model) < ($1.provider, $1.model) }
            .compactMap { choice($0.provider, $0.model) }
        let recentChoices = recent.compactMap { choice($0.provider, $0.model) }
        return Choices(favorites: favoriteChoices, recent: recentChoices)
    }
}
