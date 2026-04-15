import Foundation

struct VaultRecentsStore {
    static let storageKey = "recentVaultPaths"

    private let defaults: UserDefaults
    private let limit: Int

    init(defaults: UserDefaults = .standard, limit: Int = 10) {
        self.defaults = defaults
        self.limit = limit
    }

    func load() -> [String] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return paths.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func record(path: String) {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }

        let existing = load().filter { $0 != trimmedPath }
        save(Array(([trimmedPath] + existing).prefix(limit)))
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func save(_ paths: [String]) {
        guard let data = try? JSONEncoder().encode(paths) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
