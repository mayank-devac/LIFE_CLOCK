import CoreLocation
import ServiceManagement
import SwiftUI
import AppKit
import ColorSync
import CoreGraphics

extension NSScreen {
    var lifeClockDisplayID: Int? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? Int
    }

    var lifeClockDisplayUUID: String? {
        guard let id = lifeClockDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(id))?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

struct TimezoneMatch: Identifiable {
    var id: String { zone.identifier + label }
    let label: String
    let zone: TimeZone
}

struct ScreenChoice: Identifiable {
    let id: String       // UUID or numeric fallback; empty follows the primary display
    let displayID: Int
    let uuid: String?
    let name: String
}

extension ScreenChoice {
    static func current(preferences: LifePreferences = LifePreferences()) -> [ScreenChoice] {
        var choices: [ScreenChoice] = []
        for (index, screen) in NSScreen.screens.enumerated() {
            let name = screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName
            if index == 0 {
                choices.append(ScreenChoice(id: "", displayID: 0, uuid: nil, name: "\(name) (Primary)"))
            }
            guard let number = screen.lifeClockDisplayID else { continue }
            let uuid = screen.lifeClockDisplayUUID
            // A saved physical display stays distinct from following the primary display.
            if index != 0 || preferences.matchesWallpaperDisplay(id: number, uuid: uuid) {
                choices.append(ScreenChoice(id: LifePreferences.displaySelectionID(id: number, uuid: uuid),
                                            displayID: number, uuid: uuid, name: name))
            }
        }
        return choices
    }
}

struct SetupAndSettingsView: View {
    @ObservedObject var store: PreferencesStore
    @AppStorage("menuBarIconVisible") private var menuBarIconVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onResetCardSize: () -> Void
    let onSaved: () -> Void
    @State private var birth = BirthDetails(year: 2000, month: 1, day: 1,
                                           timeZoneID: TimeZone.current.identifier)
    @State private var layoutExpanded = false
    @State private var screenChoices = ScreenChoice.current()
    @State private var connectedScreenCount = NSScreen.screens.count
    @State private var launchAtLogin = false
    @State private var needsLoginApproval = false
    @State private var birthdayError: String?
    @State private var preferenceError: String?
    @State private var loginError: String?
    @State private var confirmRecovery = false
    @State private var recoveryMessage: String?
    @State private var cityQuery = ""
    @State private var cityResults: [TimezoneMatch] = []
    @State private var cityError: String?
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var geocoder = CLGeocoder()

    static var size: CGSize {
        let availableHeight = (NSScreen.main?.visibleFrame.height ?? 1060) - 60
        return CGSize(width: 620, height: min(1000, availableHeight))
    }

    private var birthTimeBinding: Binding<Date> {
        // Use a stable clock-only reference so changing time never changes the selected DOB.
        Binding(get: {
            Calendar(identifier: .gregorian).date(from: DateComponents(year: 2000, month: 1, day: 1,
                hour: birth.hour ?? 0, minute: birth.minute ?? 0))!
        }, set: { date in
            let parts = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: date)
            birth.hour = parts.hour
            birth.minute = parts.minute
            saveBirthday(.edit)
        })
    }

    // Display controls persist the saved preferences, never the birthday draft.
    private func preferenceBinding<T: Equatable>(_ keyPath: WritableKeyPath<LifePreferences, T>)
        -> Binding<T> {
        Binding(get: { store.preferences[keyPath: keyPath] },
                set: { value in
                    var updated = store.preferences
                    guard updated[keyPath: keyPath] != value else { return }
                    updated[keyPath: keyPath] = value
                    persist(updated)
                })
    }

    private func subsecondBinding(_ unit: SubsecondUnit) -> Binding<Bool> {
        Binding(get: { store.preferences.subsecondUnits.contains(unit) },
                set: { isEnabled in
                    var updated = store.preferences
                    if isEnabled {
                        updated.subsecondUnits.insert(unit)
                    } else {
                        updated.subsecondUnits.remove(unit)
                    }
                    persist(updated)
                })
    }

    private func saveBirthday(_ action: PreferencesStore.BirthdayAction) {
        do {
            guard try store.saveBirthday(birth, action: action) else { return }
            birthdayError = nil
            recoveryMessage = nil
        } catch {
            let savedStatus = store.preferences.birth == nil
                ? "No birthday has been saved yet."
                : "The card still uses your last valid birthday."
            birthdayError = "\(error.localizedDescription) \(savedStatus)"
        }
    }

    private func persist(_ updated: LifePreferences) {
        do {
            try store.save(updated)
            preferenceError = nil
        } catch {
            preferenceError = error.localizedDescription
        }
    }

    private func setLaunchAtLogin(_ want: Bool) -> Bool {
        do {
            let service = SMAppService.mainApp
            if want && service.status != .enabled && service.status != .requiresApproval {
                try service.register()
            } else if !want && (service.status == .enabled || service.status == .requiresApproval) {
                try service.unregister()
            }
            needsLoginApproval = service.status == .requiresApproval
            if needsLoginApproval {
                loginError = "macOS needs your approval in Login Items before automatic launch can work."
            } else {
                loginError = nil
            }
            return true
        } catch {
            loginError = "Launch at login could not be changed: \(error.localizedDescription)"
            return false
        }
    }

    private func replaceUnreadableSettings() {
        do {
            try store.replaceUnreadableSettings()
            birth = BirthDetails(year: 2000, month: 1, day: 1, timeZoneID: TimeZone.current.identifier)
            birthdayError = nil
            preferenceError = nil
            recoveryMessage = "Desktop card settings were reset. The unreadable settings are backed up. Set your birthday to continue."
        } catch {
            recoveryMessage = error.localizedDescription
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Section {
                    Toggle("Show menu bar icon", isOn: $menuBarIconVisible)
                        .toggleStyle(.switch)
                }
                Section("Date of birth") {
                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Day")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Day", selection: $birth.day) {
                                ForEach(1...daysInSelectedMonth, id: \.self) { Text("\($0)").tag($0) }
                            }
                            .labelsHidden()
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Month")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Month", selection: $birth.month) {
                                ForEach(1...12, id: \.self) { month in
                                    Text(String(format: "%02d", month)).tag(month)
                                }
                            }
                            .labelsHidden()
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Year")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Year", selection: $birth.year) {
                                ForEach((min(1900, birth.year)...currentYear).reversed(), id: \.self) {
                                    Text(String($0)).tag($0)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                    .onChange(of: birth.day) { _, _ in saveBirthday(.edit) }
                    .onChange(of: birth.month) { _, _ in clampDay(); saveBirthday(.edit) }
                    .onChange(of: birth.year) { _, _ in clampDay(); saveBirthday(.edit) }
                    Toggle("Add birth time", isOn: Binding(get: { birth.hasBirthTime }, set: { known in
                        birth.hour = known ? 0 : nil
                        birth.minute = known ? 0 : nil
                        saveBirthday(.edit)
                    }))
                    if birth.hasBirthTime {
                        DatePicker("Time", selection: birthTimeBinding, displayedComponents: .hourAndMinute)
                            .environment(\.calendar, Calendar(identifier: .gregorian))
                            .environment(\.timeZone, TimeZone.current)
                    } else {
                        Text("Time is approximate")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if store.preferences.birth == nil && !store.recoveryNeeded {
                        Button("Set birthday") { saveBirthday(.confirm) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                Section {
                    LabeledContent("Selected", value: timezoneLabel(birth.calendar.timeZone))
                    HStack {
                        TextField("Search city or town", text: $cityQuery)
                            .onSubmit(searchCity)
                            .onChange(of: cityQuery) { _, _ in cancelSearch() }
                        Button(action: searchCity) {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Search local timezones")
                        .help("Search the built-in timezone list on this Mac.")
                        .disabled(cityQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if isSearching { ProgressView().controlSize(.small) }
                    }
                    ForEach(cityResults) { place in
                        Button {
                            birth.timeZoneID = place.zone.identifier
                            cancelSearch()
                            saveBirthday(.edit)
                        } label: {
                            HStack {
                                Text(place.label)
                                Spacer()
                                Text(timezoneLabel(place.zone)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let cityError {
                        Text(cityError).font(.caption).foregroundStyle(.red)
                    }
                    Button("Search online with Apple") {
                        searchOnline()
                    }
                    .disabled(cityQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                    .help("Sends the city query to Apple for a timezone lookup.")
                } header: {
                    HStack {
                        Text("Birth timezone")
                        Spacer()
                        Button("Use Mac timezone") {
                            cancelSearch()
                            birth.timeZoneID = TimeZone.current.identifier
                            cityQuery = ""
                            saveBirthday(.edit)
                        }
                        .textCase(nil)
                    }
                }
                Section("Desktop card") {
                    Toggle("Show card", isOn: preferenceBinding(\.cardEnabled))
                    formatPicker("Display", selection: preferenceBinding(\.cardFormat))
                    if store.preferences.cardFormat == .countdown {
                        Stepper(value: preferenceBinding(\.targetAge), in: 1...150) {
                            HStack {
                                Text("Target age (personal estimate)")
                                Spacer()
                                TextField("", value: preferenceBinding(\.targetAge), format: .number.grouping(.never))
                                    .labelsHidden()
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 32)
                                    .accessibilityLabel("Target age in years")
                                Text("Years")
                            }
                        }
                        .help("Choose 1–150 years. This personal estimate is used by the display card countdown.")
                    }
                    if store.preferences.cardFormat == .liveAge || store.preferences.cardFormat == .countdown {
                        if reduceMotion {
                            Text("Subsecond counters are hidden while Reduce Motion is on.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 10) {
                                ForEach(SubsecondUnit.allCases) { unit in
                                    Toggle(unit.title, isOn: subsecondBinding(unit))
                                        .toggleStyle(.checkbox)
                                        .controlSize(.small)
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    HStack {
                        Text("Card size")
                        Spacer()
                        Button("Reset card size", action: onResetCardSize)
                            .disabled(store.preferences.wallpaperMode)
                            .help("Restore the default size for the selected display format.")
                    }
                    Toggle("Wallpaper mode (full screen)", isOn: Binding(
                        get: { store.preferences.wallpaperMode },
                        set: { on in
                            var updated = store.preferences
                            updated.wallpaperMode = on
                            if on { updated.alwaysOnTop = false }
                            persist(updated)
                        }))
                    if store.preferences.wallpaperMode {
                        Toggle("Frosted glass pane", isOn: preferenceBinding(\.wallpaperGlass))
                        if store.preferences.wallpaperGlass {
                            Toggle("Full-screen tint / veil", isOn: preferenceBinding(\.wallpaperGlassFullScreen))
                            if store.preferences.wallpaperGlassFullScreen {
                                Slider(value: preferenceBinding(\.wallpaperGlassStrength), in: 0...1)
                                    .accessibilityLabel("Glass strength")
                                Text("Glass strength · clear ↔ veiled").font(.caption2).foregroundStyle(.secondary)
                                Text("A tint / veil covers the whole screen behind the digits; the rounded frosted pane and its roundness slider apply only when this is off.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if connectedScreenCount > 1 {
                            Picker("Screen", selection: Binding(
                                get: {
                                    selectedScreenID
                                },
                                set: { id in
                                    // The disconnected placeholder represents the existing selection.
                                    guard let choice = screenChoices.first(where: { $0.id == id }) else { return }
                                    var updated = store.preferences
                                    updated.wallpaperDisplayUUID = choice.uuid
                                    updated.wallpaperDisplay = choice.displayID
                                    persist(updated)
                                })) {
                                ForEach(screenChoices) { choice in
                                    Text(choice.name).tag(choice.id)
                                }
                                if !selectedScreenID.isEmpty && !screenChoices.contains(where: { $0.id == selectedScreenID }) {
                                    Text("Saved display (disconnected)").tag(selectedScreenID)
                                }
                            }
                        }
                        HStack {
                            Text("Layout")
                            Spacer()
                            Button {
                                layoutExpanded.toggle()
                            } label: {
                                Image(systemName: layoutExpanded ? "chevron.up" : "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(layoutExpanded ? "Collapse layout controls" : "Expand layout controls")
                            .accessibilityValue(layoutExpanded ? "Expanded" : "Collapsed")
                            .help(layoutExpanded ? "Hide layout sliders" : "Show layout sliders")
                        }
                        if layoutExpanded {
                            VStack(alignment: .leading, spacing: 8) {
                                Slider(value: preferenceBinding(\.wallpaperOffsetX), in: -1...1)
                                    .accessibilityLabel("Move clock right and left")
                                Text("Horizontal · left ↔ right").font(.caption2).foregroundStyle(.secondary)
                                Slider(value: preferenceBinding(\.wallpaperOffsetY), in: -1...1)
                                    .accessibilityLabel("Move clock up and down")
                                Text("Vertical · down ↔ up").font(.caption2).foregroundStyle(.secondary)
                                Slider(value: preferenceBinding(\.wallpaperSize), in: 0.4...2)
                                    .accessibilityLabel("Clock size")
                                Text("Size · 1.0 = full width").font(.caption2).foregroundStyle(.secondary)
                                if store.preferences.wallpaperGlass && !store.preferences.wallpaperGlassFullScreen {
                                    Slider(value: preferenceBinding(\.wallpaperRoundness), in: 0...2.6)
                                        .accessibilityLabel("Pane roundness")
                                    Text("Roundness · 0 = sharp corners").font(.caption2).foregroundStyle(.secondary)
                                }
                                HStack {
                                    Button("Reset to centered full") {
                                        var updated = store.preferences
                                        updated.wallpaperOffsetX = 0
                                        updated.wallpaperOffsetY = 0
                                        updated.wallpaperSize = 1
                                        updated.wallpaperRoundness = 1.4
                                        persist(updated)
                                    }
                                    Spacer()
                                    Text(String(format: "h %.2f · v %.2f · size %.2f · round %.2f",
                                                store.preferences.wallpaperOffsetX,
                                                store.preferences.wallpaperOffsetY,
                                                store.preferences.wallpaperSize,
                                                store.preferences.wallpaperRoundness))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    Toggle("Keep on top", isOn: preferenceBinding(\.alwaysOnTop))
                        .disabled(store.preferences.wallpaperMode)
                    Toggle("Open at login", isOn: Binding(
                        get: { launchAtLogin },
                        set: { want in if setLaunchAtLogin(want) { launchAtLogin = want } }))
                    if needsLoginApproval {
                        Button("Allow in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
            }
            .formStyle(.grouped)
            if let warning = store.readWarning {
                Text(warning).font(.caption).foregroundStyle(.orange)
                Button("Replace unreadable settings…") { confirmRecovery = true }
            }
            if let recoveryMessage {
                Text(recoveryMessage).font(.caption)
                    .accessibilityLabel("Settings recovery: \(recoveryMessage)")
            }
            if let birthdayError {
                Text(birthdayError).font(.caption).foregroundStyle(.red)
                    .accessibilityLabel("Birthday error: \(birthdayError)")
            }
            if let preferenceError {
                Text(preferenceError).font(.caption).foregroundStyle(.red)
                    .accessibilityLabel("Preference save error: \(preferenceError)")
            }
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
                    .accessibilityLabel("Login error: \(loginError)")
            }
        }
        .padding(20)
        .frame(width: Self.size.width)
        .frame(maxHeight: .infinity)
        .alert("Replace unreadable settings?", isPresented: $confirmRecovery) {
            Button("Cancel", role: .cancel) { }
            Button("Replace settings", role: .destructive, action: replaceUnreadableSettings)
        } message: {
            Text("This resets your desktop card settings and birthday. The unreadable settings are backed up first. Widget settings and Open at login are unchanged.")
        }
        .onAppear {
            connectedScreenCount = NSScreen.screens.count
            screenChoices = ScreenChoice.current(preferences: store.preferences)
            load()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            connectedScreenCount = NSScreen.screens.count
            screenChoices = ScreenChoice.current(preferences: store.preferences)
        }
        .onDisappear(perform: cancelSearch)
    }

    private var currentYear: Int { birth.calendar.component(.year, from: Date()) }

    private var selectedScreenID: String {
        let identities = screenChoices.map { (id: $0.displayID, uuid: $0.uuid) }
        if let index = store.preferences.wallpaperDisplayIndex(in: identities) {
            return screenChoices[index].id
        }
        return store.preferences.wallpaperDisplaySelectionID
    }

    private var daysInSelectedMonth: Int {
        let first = birth.calendar.date(from: DateComponents(year: birth.year, month: birth.month, day: 1))!
        return birth.calendar.range(of: .day, in: .month, for: first)!.count
    }

    private func clampDay() {
        birth.day = min(birth.day, daysInSelectedMonth)
    }

    private func timezoneLabel(_ zone: TimeZone) -> String {
        let city = zone.identifier.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: "_", with: " ") ?? zone.identifier
        let offset = zone.secondsFromGMT() / 60
        return String(format: "%@ · GMT%@%02d:%02d", city, offset < 0 ? "−" : "+", abs(offset) / 60, abs(offset) % 60)
    }

    private func placeLabel(_ place: CLPlacemark) -> String {
        [place.locality ?? place.name, place.administrativeArea, place.country]
            .compactMap { $0 }.joined(separator: ", ")
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        geocoder.cancelGeocode()
        isSearching = false
        cityResults = []
        cityError = nil
    }

    private func searchCity() {
        let query = cityQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        searchTask?.cancel()
        geocoder.cancelGeocode()
        cityError = nil
        isSearching = false
        cityResults = findLocalTimezones(query: query)
        if cityResults.isEmpty {
            cityError = "No local timezone match. Search online with Apple if you want to try the internet."
        }
    }

    private func searchOnline() {
        let query = cityQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        searchTask?.cancel()
        geocoder.cancelGeocode()
        cityError = nil
        isSearching = true
        let localMatches = findLocalTimezones(query: query)
        cityResults = localMatches
        searchTask = Task { @MainActor in
            do {
                let places = try await geocoder.geocodeAddressString(query)
                guard !Task.isCancelled else { return }
                var updated = localMatches
                var seen = Set(localMatches.map(\.zone.identifier))
                for place in places {
                    if let zone = place.timeZone, !seen.contains(zone.identifier) {
                        seen.insert(zone.identifier)
                        updated.append(TimezoneMatch(label: placeLabel(place), zone: zone))
                    }
                }
                cityResults = updated
                if cityResults.isEmpty {
                    cityError = "No city found. Try adding the country or a major city name."
                }
            } catch {
                guard !Task.isCancelled else { return }
                if cityResults.isEmpty {
                    cityError = "Couldn’t find that city online. Check your connection or add the country."
                }
            }
            isSearching = false
        }
    }

    private func findLocalTimezones(query: String) -> [TimezoneMatch] {
        let q = query.lowercased()
        var results: [TimezoneMatch] = []
        var seen = Set<String>()

        let aliases: [String: String] = [
            "ist": "Asia/Kolkata", "est": "America/New_York", "edt": "America/New_York",
            "cst": "America/Chicago", "cdt": "America/Chicago", "mst": "America/Denver",
            "mdt": "America/Denver", "pst": "America/Los_Angeles", "pdt": "America/Los_Angeles",
            "utc": "UTC", "gmt": "GMT", "bst": "Europe/London", "cet": "Europe/Paris",
            "cest": "Europe/Paris", "jst": "Asia/Tokyo", "kst": "Asia/Seoul",
            "sgt": "Asia/Singapore", "hkt": "Asia/Hong_Kong", "aest": "Australia/Sydney",
            "delhi": "Asia/Kolkata", "mumbai": "Asia/Kolkata", "bangalore": "Asia/Kolkata",
            "bengaluru": "Asia/Kolkata", "chennai": "Asia/Kolkata", "hyderabad": "Asia/Kolkata",
            "pune": "Asia/Kolkata", "san francisco": "America/Los_Angeles",
            "seattle": "America/Los_Angeles", "chicago": "America/Chicago",
            "new york": "America/New_York", "los angeles": "America/Los_Angeles",
            "london": "Europe/London", "paris": "Europe/Paris", "berlin": "Europe/Berlin",
            "tokyo": "Asia/Tokyo", "sydney": "Australia/Sydney", "dubai": "Asia/Dubai",
            "singapore": "Asia/Singapore", "toronto": "America/Toronto",
            "india": "Asia/Kolkata", "new delhi": "Asia/Kolkata", "calcutta": "Asia/Kolkata",
            "ahmedabad": "Asia/Kolkata", "jaipur": "Asia/Kolkata", "lucknow": "Asia/Kolkata",
            "kochi": "Asia/Kolkata", "goa": "Asia/Kolkata", "chandigarh": "Asia/Kolkata",
            "kathmandu": "Asia/Kathmandu", "dhaka": "Asia/Dhaka", "colombo": "Asia/Colombo",
            "karachi": "Asia/Karachi", "lahore": "Asia/Karachi", "islamabad": "Asia/Karachi",
            "beijing": "Asia/Shanghai", "shanghai": "Asia/Shanghai", "hong kong": "Asia/Hong_Kong",
            "seoul": "Asia/Seoul", "osaka": "Asia/Tokyo", "taipei": "Asia/Taipei",
            "bangkok": "Asia/Bangkok", "hanoi": "Asia/Ho_Chi_Minh", "ho chi minh city": "Asia/Ho_Chi_Minh",
            "jakarta": "Asia/Jakarta", "bali": "Asia/Makassar", "manila": "Asia/Manila",
            "kuala lumpur": "Asia/Kuala_Lumpur", "abu dhabi": "Asia/Dubai",
            "riyadh": "Asia/Riyadh", "doha": "Asia/Qatar", "istanbul": "Europe/Istanbul",
            "rome": "Europe/Rome", "madrid": "Europe/Madrid", "barcelona": "Europe/Madrid",
            "amsterdam": "Europe/Amsterdam", "brussels": "Europe/Brussels", "zurich": "Europe/Zurich",
            "vienna": "Europe/Vienna", "prague": "Europe/Prague", "stockholm": "Europe/Stockholm",
            "dublin": "Europe/Dublin", "lisbon": "Europe/Lisbon", "athens": "Europe/Athens",
            "boston": "America/New_York", "washington dc": "America/New_York", "miami": "America/New_York",
            "atlanta": "America/New_York", "dallas": "America/Chicago", "houston": "America/Chicago",
            "austin": "America/Chicago", "denver": "America/Denver", "phoenix": "America/Phoenix",
            "las vegas": "America/Los_Angeles", "san diego": "America/Los_Angeles",
            "vancouver": "America/Vancouver", "montreal": "America/Toronto", "ottawa": "America/Toronto",
            "mexico city": "America/Mexico_City", "sao paulo": "America/Sao_Paulo",
            "rio de janeiro": "America/Sao_Paulo", "buenos aires": "America/Argentina/Buenos_Aires",
            "lima": "America/Lima", "bogota": "America/Bogota", "santiago": "America/Santiago",
            "cairo": "Africa/Cairo", "lagos": "Africa/Lagos", "nairobi": "Africa/Nairobi",
            "johannesburg": "Africa/Johannesburg", "cape town": "Africa/Johannesburg",
            "melbourne": "Australia/Melbourne", "brisbane": "Australia/Brisbane",
            "perth": "Australia/Perth", "adelaide": "Australia/Adelaide", "auckland": "Pacific/Auckland"
        ]

        if let id = aliases[q], let zone = TimeZone(identifier: id) {
            let cityName = id.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: "_", with: " ") ?? id
            results.append(TimezoneMatch(label: cityName, zone: zone))
            seen.insert(zone.identifier)
        }

        for id in TimeZone.knownTimeZoneIdentifiers {
            guard !seen.contains(id) else { continue }
            let cityName = id.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: "_", with: " ") ?? id
            let lowerCity = cityName.lowercased()
            let lowerID = id.lowercased()

            guard let zone = TimeZone(identifier: id) else { continue }
            let abbrev = (zone.abbreviation() ?? "").lowercased()

            if lowerCity == q || lowerCity.hasPrefix(q) || lowerCity.contains(q) || lowerID.contains(q) || abbrev == q {
                results.append(TimezoneMatch(label: cityName, zone: zone))
                seen.insert(id)
                if results.count >= 8 { break }
            }
        }

        return results
    }

    private func formatPicker(_ title: String, selection: Binding<DesktopCardFormat>) -> some View {
        Picker(title, selection: selection) {
            ForEach(DesktopCardFormat.allCases) { format in Text(format.title).tag(format) }
        }
    }

    private func load() {
        if let savedBirth = store.preferences.birth { birth = savedBirth }
        launchAtLogin = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
        needsLoginApproval = SMAppService.mainApp.status == .requiresApproval
    }
}
