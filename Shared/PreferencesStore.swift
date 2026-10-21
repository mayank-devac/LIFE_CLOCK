import Combine
import Foundation

struct LifePreferences: Codable, Equatable {
    var birth: BirthDetails?
    var cardFormat: DesktopCardFormat = .liveAge
    var targetAge = 80
    var subsecondUnits: Set<SubsecondUnit> = [.milliseconds, .microseconds, .picoseconds]
    var cardEnabled = true
    var alwaysOnTop = false
    var wallpaperMode = true
    var wallpaperGlass = false
    var wallpaperDisplay = 0
    var wallpaperCustomLayout = false
    var wallpaperOffsetX = 0.0     // -1 (left) … 1 (right), half-screen shift
    var wallpaperOffsetY = 0.0     // -1 (down) … 1 (up), half-screen shift
    var wallpaperSize = 1.0        // 1 = full width; 0.4 … 2.0
    var wallpaperRoundness = 1.4   // 0 = sharp corners; relative to pane padding
    var wallpaperGlassFullScreen = false // glass spans the screen instead of the digits pane
    var wallpaperGlassStrength = 0.4    // 0 = nearly clear, 1 = most veiled

    init(birth: BirthDetails? = nil, cardFormat: DesktopCardFormat = .liveAge, targetAge: Int = 80,
         subsecondUnits: Set<SubsecondUnit> = [.milliseconds, .microseconds, .picoseconds],
         cardEnabled: Bool = true,
         alwaysOnTop: Bool = false,
         wallpaperMode: Bool = true,
         wallpaperGlass: Bool = false,
         wallpaperDisplay: Int = 0,
         wallpaperCustomLayout: Bool = false,
         wallpaperOffsetX: Double = 0,
         wallpaperOffsetY: Double = 0,
         wallpaperSize: Double = 1,
         wallpaperRoundness: Double = 1.4,
         wallpaperGlassFullScreen: Bool = false,
         wallpaperGlassStrength: Double = 0.4) {
        self.birth = birth
        self.cardFormat = cardFormat
        self.targetAge = targetAge
        self.subsecondUnits = subsecondUnits
        self.cardEnabled = cardEnabled
        self.alwaysOnTop = alwaysOnTop
        self.wallpaperMode = wallpaperMode
        self.wallpaperGlass = wallpaperGlass
        self.wallpaperDisplay = wallpaperDisplay
        self.wallpaperCustomLayout = wallpaperCustomLayout
        self.wallpaperOffsetX = wallpaperOffsetX
        self.wallpaperOffsetY = wallpaperOffsetY
        self.wallpaperSize = wallpaperSize
        self.wallpaperRoundness = wallpaperRoundness
        self.wallpaperGlassFullScreen = wallpaperGlassFullScreen
        self.wallpaperGlassStrength = wallpaperGlassStrength
    }

    private enum CodingKeys: String, CodingKey {
        case birth, cardFormat, targetAge, subsecondUnits, cardEnabled, alwaysOnTop
        case wallpaperMode, wallpaperGlass, wallpaperDisplay
        case wallpaperCustomLayout, wallpaperOffsetX, wallpaperOffsetY, wallpaperSize, wallpaperRoundness
        case wallpaperGlassFullScreen
        case wallpaperGlassStrength
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case subsecondPrecision
    }

    private enum LegacySubsecondPrecision: String, Decodable {
        case seconds, milliseconds, microseconds, nanoseconds
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let legacyValues = try decoder.container(keyedBy: LegacyCodingKeys.self)
        birth = try values.decodeIfPresent(BirthDetails.self, forKey: .birth)
        cardFormat = try values.decodeIfPresent(DesktopCardFormat.self, forKey: .cardFormat) ?? .liveAge
        targetAge = min(150, max(1, try values.decodeIfPresent(Int.self, forKey: .targetAge) ?? 80))
        if let units = try values.decodeIfPresent(Set<SubsecondUnit>.self, forKey: .subsecondUnits) {
            subsecondUnits = units
        } else {
            switch try legacyValues.decodeIfPresent(LegacySubsecondPrecision.self, forKey: .subsecondPrecision) ?? .seconds {
            case .seconds: subsecondUnits = []
            case .milliseconds: subsecondUnits = [.milliseconds]
            case .microseconds: subsecondUnits = [.milliseconds, .microseconds]
            case .nanoseconds: subsecondUnits = [.milliseconds, .microseconds, .nanoseconds]
            }
        }
        cardEnabled = try values.decodeIfPresent(Bool.self, forKey: .cardEnabled) ?? true
        alwaysOnTop = try values.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? false
        wallpaperMode = try values.decodeIfPresent(Bool.self, forKey: .wallpaperMode) ?? true
        wallpaperGlass = try values.decodeIfPresent(Bool.self, forKey: .wallpaperGlass) ?? false
        wallpaperDisplay = try values.decodeIfPresent(Int.self, forKey: .wallpaperDisplay) ?? 0
        wallpaperCustomLayout = try values.decodeIfPresent(Bool.self, forKey: .wallpaperCustomLayout) ?? false
        wallpaperOffsetX = try values.decodeIfPresent(Double.self, forKey: .wallpaperOffsetX) ?? 0
        wallpaperOffsetY = try values.decodeIfPresent(Double.self, forKey: .wallpaperOffsetY) ?? 0
        wallpaperSize = try values.decodeIfPresent(Double.self, forKey: .wallpaperSize) ?? 1
        wallpaperRoundness = try values.decodeIfPresent(Double.self, forKey: .wallpaperRoundness) ?? 1.4
        wallpaperGlassFullScreen = try values.decodeIfPresent(Bool.self, forKey: .wallpaperGlassFullScreen) ?? false
        wallpaperGlassStrength = try values.decodeIfPresent(Double.self, forKey: .wallpaperGlassStrength) ?? 0.4
    }
}

final class PreferencesStore: ObservableObject {
    private static let preferencesKey = "lifePreferences.v1"
    private static let recoveryBackupKey = "lifePreferences.recoveryBackup.v1"
    private let defaults: UserDefaults
    private var unreadableData: Data?
    var recoveryNeeded: Bool { unreadableData != nil }
    @Published private(set) var preferences: LifePreferences
    @Published private(set) var readWarning: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.preferencesKey) {
            do {
                preferences = try JSONDecoder().decode(LifePreferences.self, from: data)
            } catch {
                preferences = LifePreferences()
                unreadableData = data
                readWarning = "Saved settings could not be read. Replace them explicitly to set up the desktop card again."
            }
        } else {
            preferences = LifePreferences()
        }
    }

    // Nil birth is a valid unconfigured state (fresh install). A present birth
    // must be a real past date; the picker nudges the user until it validates.
    func save(_ updated: LifePreferences) throws {
        guard !recoveryNeeded else { throw SettingsError.recoveryRequired }
        guard (1...150).contains(updated.targetAge) else { throw SettingsError.invalidTargetAge }
        if let birth = updated.birth {
            guard let date = birth.date, date <= Date() else {
                throw SettingsError.invalidBirthday
            }
        }
        let data = try JSONEncoder().encode(updated)
        defaults.set(data, forKey: Self.preferencesKey)
        preferences = updated
        readWarning = nil
    }

    enum BirthdayAction {
        case edit, confirm
    }

    /// Draft edits do not configure a new card; confirmation does.
    @discardableResult
    func saveBirthday(_ birth: BirthDetails, action: BirthdayAction) throws -> Bool {
        if action == .edit && preferences.birth == nil { return false }
        var updated = preferences
        updated.birth = birth
        try save(updated)
        return true
    }

    func replaceUnreadableSettings() throws {
        guard let unreadableData else { return }
        guard defaults.object(forKey: Self.recoveryBackupKey) == nil else {
            throw SettingsError.recoveryBackupExists
        }
        let reset = LifePreferences()
        let data = try JSONEncoder().encode(reset)
        defaults.set(unreadableData, forKey: Self.recoveryBackupKey)
        guard defaults.data(forKey: Self.recoveryBackupKey) == unreadableData else {
            throw SettingsError.recoveryBackupFailed
        }
        defaults.set(data, forKey: Self.preferencesKey)
        self.unreadableData = nil
        preferences = reset
        readWarning = nil
    }

    var lastCelebratedDay: String? {
        get { defaults.string(forKey: "lastCelebratedDay") }
        set { defaults.set(newValue, forKey: "lastCelebratedDay") }
    }

    enum SettingsError: LocalizedError {
        case invalidBirthday, invalidTargetAge, recoveryRequired, recoveryBackupExists, recoveryBackupFailed
        var errorDescription: String? {
            switch self {
            case .invalidBirthday:
                return "Choose a valid birthday that is not in the future. A birth time must exist in the selected timezone."
            case .invalidTargetAge:
                return "Choose a target age from 1 to 150 years."
            case .recoveryRequired:
                return "Your unreadable settings are protected. Use Replace unreadable settings before saving changes."
            case .recoveryBackupExists:
                return "A recovery backup already exists. Nothing was replaced, so both copies remain protected."
            case .recoveryBackupFailed:
                return "The recovery backup could not be saved. Your original settings have not been replaced."
            }
        }
    }
}
