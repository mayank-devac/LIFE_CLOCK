import CoreLocation
import ServiceManagement
import SwiftUI

struct TimezoneMatch: Identifiable {
    var id: String { zone.identifier + label }
    let label: String
    let zone: TimeZone
}

struct SetupAndSettingsView: View {
    @ObservedObject var store: PreferencesStore
    let onSaved: () -> Void
    @State private var draft = LifePreferences()
    @State private var birth = BirthDetails(year: 2000, month: 1, day: 1,
                                           timeZoneID: TimeZone.current.identifier)
    @State private var launchAtLogin = false
    @State private var needsLoginApproval = false
    @State private var errorMessage: String?
    @State private var cityQuery = ""
    @State private var cityResults: [TimezoneMatch] = []
    @State private var cityError: String?
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var geocoder = CLGeocoder()

    static let size = CGSize(width: 620, height: 700)

    private var birthTimeBinding: Binding<Date> {
        // Use a stable clock-only reference so changing time never changes the selected DOB.
        Binding(get: {
            Calendar(identifier: .gregorian).date(from: DateComponents(year: 2000, month: 1, day: 1,
                hour: birth.hour ?? 0, minute: birth.minute ?? 0))!
        }, set: { date in
            let parts = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: date)
            birth.hour = parts.hour
            birth.minute = parts.minute
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
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
                    .onChange(of: birth.month) { _, _ in clampDay() }
                    .onChange(of: birth.year) { _, _ in clampDay() }
                    Toggle("Add birth time", isOn: Binding(get: { birth.hasBirthTime }, set: { known in
                        birth.hour = known ? 0 : nil
                        birth.minute = known ? 0 : nil
                    }))
                    if birth.hasBirthTime {
                        DatePicker("Time", selection: birthTimeBinding, displayedComponents: .hourAndMinute)
                            .environment(\.calendar, Calendar(identifier: .gregorian))
                            .environment(\.timeZone, TimeZone.current)
                    }
                }
                Section("Birth timezone") {
                    LabeledContent("Selected", value: timezoneLabel(birth.calendar.timeZone))
                    HStack {
                        TextField("Search city or town", text: $cityQuery)
                            .onSubmit(searchCity)
                            .onChange(of: cityQuery) { _, _ in cancelSearch() }
                        Button(action: searchCity) {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Find timezone for city")
                        .disabled(cityQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                        if isSearching { ProgressView().controlSize(.small) }
                    }
                    ForEach(cityResults) { place in
                        Button {
                            birth.timeZoneID = place.zone.identifier
                            cancelSearch()
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
                    Button("Use Mac timezone · \(timezoneLabel(.current))") {
                        cancelSearch()
                        birth.timeZoneID = TimeZone.current.identifier
                        cityQuery = ""
                    }
                }
                Section("Desktop card") {
                    Toggle("Show card", isOn: $draft.cardEnabled)
                    formatPicker("Display", selection: $draft.cardFormat)
                    if draft.cardFormat == .liveAge || draft.cardFormat == .countdown {
                        HStack(spacing: 10) {
                            ForEach(SubsecondUnit.allCases) { unit in
                                Toggle(unit.title, isOn: Binding(
                                    get: { draft.subsecondUnits.contains(unit) },
                                    set: { isEnabled in
                                        if isEnabled {
                                            draft.subsecondUnits.insert(unit)
                                        } else {
                                            draft.subsecondUnits.remove(unit)
                                        }
                                    }))
                                    .toggleStyle(.checkbox)
                                    .controlSize(.small)
                                    .font(.caption2)
                            }
                        }
                    }
                    Toggle("Wallpaper mode (full screen)", isOn: Binding(
                        get: { draft.wallpaperMode },
                        set: { on in
                            draft.wallpaperMode = on
                            if on { draft.alwaysOnTop = false }
                        }))
                    if draft.wallpaperMode {
                        Toggle("Frosted glass pane", isOn: $draft.wallpaperGlass)
                        Text("Fills the whole screen behind the desktop icons: above the wallpaper, below every window and icon, clicks pass through. The card's drag, resize and gear controls do nothing here — use the menu-bar hourglass to reopen these settings. The screen frame is used, so digits can sit behind the menu bar and Dock.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Keep on top", isOn: $draft.alwaysOnTop)
                        .disabled(draft.wallpaperMode)
                    Toggle("Open at login", isOn: $launchAtLogin)
                    if needsLoginApproval {
                        Button("Allow in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
            }
            .formStyle(.grouped)
            if let warning = store.readWarning {
                Text(warning).font(.caption).foregroundStyle(.orange)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
                    .accessibilityLabel("Settings error: \(errorMessage)")
            }
            HStack {
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSearching || !cityResults.isEmpty)
            }
        }
        .padding(20)
        .frame(width: Self.size.width, height: Self.size.height)
        .onAppear(perform: load)
        .onDisappear(perform: cancelSearch)
    }

    private var currentYear: Int { birth.calendar.component(.year, from: Date()) }

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
                    cityError = "Couldn’t find that city. Check your connection or add the country."
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
            "singapore": "Asia/Singapore", "toronto": "America/Toronto"
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
        draft = store.preferences
        if let savedBirth = draft.birth { birth = savedBirth }
        launchAtLogin = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
        needsLoginApproval = SMAppService.mainApp.status == .requiresApproval
        errorMessage = nil
    }

    private func save() {
        draft.birth = birth
        do {
            try store.save(draft)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        do {
            let service = SMAppService.mainApp
            if launchAtLogin && service.status != .enabled && service.status != .requiresApproval {
                try service.register()
            } else if !launchAtLogin && (service.status == .enabled || service.status == .requiresApproval) {
                try service.unregister()
            }
            needsLoginApproval = service.status == .requiresApproval
            if needsLoginApproval {
                errorMessage = "Birthday saved. macOS needs your approval in Login Items before automatic launch can work."
            } else {
                errorMessage = nil
            }
        } catch {
            errorMessage = "Birthday saved, but launch at login could not be changed: \(error.localizedDescription)"
        }
    }
}
