import Combine
import Foundation

struct LifePreferences: Codable, Equatable {
    var birth: BirthDetails?
    var cardFormat: AgeFormat = .detailed
    var cardEnabled = true
    var alwaysOnTop = false
}

final class PreferencesStore: ObservableObject {
    private static let preferencesKey = "lifePreferences.v1"
    private let defaults = UserDefaults.standard
    @Published private(set) var preferences: LifePreferences
    @Published private(set) var readWarning: String?

    init() {
        if let data = defaults.data(forKey: Self.preferencesKey) {
            do {
                preferences = try JSONDecoder().decode(LifePreferences.self, from: data)
            } catch {
                preferences = LifePreferences()
                readWarning = "Saved settings could not be read. Save your birthday again to replace them."
            }
        } else {
            preferences = LifePreferences()
        }
    }

    func save(_ updated: LifePreferences) throws {
        guard let birth = updated.birth, let date = birth.date, date <= Date() else {
            throw SettingsError.invalidBirthday
        }
        let data = try JSONEncoder().encode(updated)
        defaults.set(data, forKey: Self.preferencesKey)
        preferences = updated
        readWarning = nil
    }

    var lastCelebratedDay: String? {
        get { defaults.string(forKey: "lastCelebratedDay") }
        set { defaults.set(newValue, forKey: "lastCelebratedDay") }
    }

    enum SettingsError: LocalizedError {
        case invalidBirthday
        var errorDescription: String? {
            "Choose a valid birthday that is not in the future. A birth time must exist in the selected timezone."
        }
    }
}
