import CoreLocation
import ServiceManagement
import SwiftUI

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
    @State private var cityResults: [CLPlacemark] = []
    @State private var cityError: String?
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var geocoder = CLGeocoder()

    static let size = CGSize(width: 520, height: 610)

    private var birthdayBinding: Binding<Date> {
        Binding(get: { birth.date ?? Date() }, set: { date in
            let parts = birth.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            birth.year = parts.year!
            birth.month = parts.month!
            birth.day = parts.day!
            if birth.hasBirthTime {
                birth.hour = parts.hour
                birth.minute = parts.minute
            }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Section("Date of birth") {
                    HStack(spacing: 8) {
                        Picker("Day", selection: $birth.day) {
                            ForEach(1...daysInSelectedMonth, id: \.self) { Text("\($0)").tag($0) }
                        }
                        Picker("Month", selection: $birth.month) {
                            ForEach(1...12, id: \.self) { month in
                                Text(birth.calendar.shortMonthSymbols[month - 1]).tag(month)
                            }
                        }
                        Picker("Year", selection: $birth.year) {
                            ForEach((min(1900, birth.year)...currentYear).reversed(), id: \.self) {
                                Text(String($0)).tag($0)
                            }
                        }
                    }
                    .onChange(of: birth.month) { _, _ in clampDay() }
                    .onChange(of: birth.year) { _, _ in clampDay() }
                    Toggle("Add birth time", isOn: Binding(get: { birth.hasBirthTime }, set: { known in
                        birth.hour = known ? 0 : nil
                        birth.minute = known ? 0 : nil
                    }))
                    if birth.hasBirthTime {
                        DatePicker("Time", selection: birthdayBinding, displayedComponents: .hourAndMinute)
                            .environment(\.calendar, birth.calendar)
                            .environment(\.timeZone, birth.calendar.timeZone)
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
                        .accessibilityLabel("Find timezone for city")
                        .disabled(cityQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                        if isSearching { ProgressView().controlSize(.small) }
                    }
                    ForEach(cityResults.indices, id: \.self) { index in
                        let place = cityResults[index]
                        if let zone = place.timeZone {
                            Button {
                                birth.timeZoneID = zone.identifier
                                cancelSearch()
                            } label: {
                                HStack {
                                    Text(placeLabel(place))
                                    Spacer()
                                    Text(timezoneLabel(zone)).foregroundStyle(.secondary)
                                }
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
                    Toggle("Keep on top", isOn: $draft.alwaysOnTop)
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
        cancelSearch()
        isSearching = true
        searchTask = Task { @MainActor in
            do {
                let places = try await geocoder.geocodeAddressString(query)
                guard !Task.isCancelled else { return }
                cityResults = places.filter { $0.timeZone != nil }
                if cityResults.isEmpty { cityError = "No city found. Try adding the country." }
            } catch {
                guard !Task.isCancelled else { return }
                cityError = "Couldn’t find that city. Check your connection or add the country."
            }
            isSearching = false
        }
    }

    private func formatPicker(_ title: String, selection: Binding<AgeFormat>) -> some View {
        Picker(title, selection: selection) {
            ForEach(AgeFormat.allCases) { format in Text(format.title).tag(format) }
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
                onSaved()
            }
        } catch {
            errorMessage = "Birthday saved, but launch at login could not be changed: \(error.localizedDescription)"
        }
    }
}
