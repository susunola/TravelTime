import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

/// macOS System Settings–style window: sidebar of 6 categories on the left,
/// detail page on the right. The user's last-selected category is persisted.
struct SettingsView: View {
    @EnvironmentObject var store: TimeZoneStore
    @State private var category: SettingsCategory = .preferences

    private static let categoryKey = "settings.category"

    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    /// Common-zone list — duplicated in AppDelegate/SettingsView only as a
    /// picker source, not as a data source. Kept here so the Settings can
    /// suggest zones without coupling to the main panel's own data.
    static let commonZones: [(id: String, label: String, region: String)] = [
        ("Asia/Shanghai", "Beijing / Shanghai", "China"),
        ("Asia/Bangkok", "Bangkok", "Thailand"),
        ("Asia/Jakarta", "Jakarta", "Indonesia"),
        ("Asia/Hong_Kong", "Hong Kong", "China"),
        ("Asia/Taipei", "Taipei", "Taiwan, China"),
        ("Asia/Tokyo", "Tokyo", "Japan"),
        ("Asia/Seoul", "Seoul", "South Korea"),
        ("Asia/Singapore", "Singapore", "Singapore"),
        ("Asia/Dubai", "Dubai", "UAE"),
        ("Asia/Kolkata", "New Delhi", "India"),
        ("Australia/Sydney", "Sydney", "Australia"),
        ("Pacific/Auckland", "Auckland", "New Zealand"),
        ("Europe/London", "London", "United Kingdom"),
        ("Europe/Paris", "Paris", "France"),
        ("Europe/Berlin", "Berlin", "Germany"),
        ("Europe/Berlin", "Frankfurt", "Germany"),
        ("Europe/Madrid", "Madrid", "Spain"),
        ("Europe/Rome", "Rome", "Italy"),
        ("Europe/Amsterdam", "Amsterdam", "Netherlands"),
        ("America/New_York", "New York", "United States"),
        ("America/Los_Angeles", "Los Angeles", "United States"),
        ("America/Chicago", "Chicago", "United States"),
        ("America/Sao_Paulo", "São Paulo", "Brazil"),
        ("UTC", "Coordinated Universal Time", "")
    ]

    var body: some View {
        NavigationSplitView {
            // Sidebar: list of categories. Width pinned to a comfortable range.
            List(SettingsCategory.allCases, selection: $category) { cat in
                Label(cat.title, systemImage: cat.systemImage)
                    .tag(cat)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 176, max: 190)
        } detail: {
            // Detail: the selected category.
            Group {
                switch category {
                case .preferences: PreferencesPage()
                case .cities: CitiesPage()
                case .calendar: CalendarHolidaysPage()
                case .about: AboutPage()
                }
            }
            .frame(minWidth: 520, minHeight: 520)
        }
        .tint(store.palette.accent)
        .onAppear {
            // Restore the last selected category.
            if let raw = UserDefaults.standard.string(forKey: Self.categoryKey),
               let saved = SettingsCategory(rawValue: raw) {
                category = saved
            }
        }
        .onChange(of: category) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.categoryKey)
        }
    }
}

/// Sidebar categories. The raw value is persisted so the user's last
/// selected category is restored on the next launch.
enum SettingsCategory: String, CaseIterable, Identifiable {
    case preferences, cities, calendar, about
    var id: Self { self }

    var title: String {
        switch self {
        case .preferences: return "Preferences"
        case .cities: return "Cities & Time Zones"
        case .calendar: return "Calendar & Holidays"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .preferences: return "slider.horizontal.3"
        case .cities: return "globe.asia.australia.fill"
        case .calendar: return "calendar"
        case .about: return "info.circle"
        }
    }
}

private struct PreferencesPage: View {
    var body: some View {
        SettingsPage(title: "Preferences", subtitle: "Choose how TravelTime looks and behaves.") {
            SettingsSection(title: "General") { CategoryGeneral() }
        }
    }
}

private struct CitiesPage: View {
    var body: some View {
        SettingsPage(title: "Cities & Time Zones", subtitle: "Manage the cities shown in your world clock.") {
            SettingsSection(title: "Your cities") { CategoryTimeZones() }
        }
    }
}

private struct CalendarHolidaysPage: View {
    var body: some View {
        SettingsPage(title: "Calendar & Holidays", subtitle: "Control calendar display, imported events, and public holidays.") {
            SettingsSection(title: "Calendar") { CategoryDisplay() }
            SettingsSection(title: "Public holidays") { CategoryHolidays() }
        }
    }
}

private struct AboutPage: View {
    var body: some View {
        SettingsPage(title: "About TravelTime", subtitle: "Version information, updates, and app management.") {
            SettingsSection(title: "TravelTime") { CategoryAbout() }
            SettingsSection(title: "Software update") { CategoryUpdate() }
            SettingsSection(title: "Danger zone", isDestructive: true) { CategoryUninstall() }
        }
    }
}

private struct CategoryHolidays: View {
    @EnvironmentObject var holidayStore: HolidayStore
    @EnvironmentObject var eventStore: EventStore
    @EnvironmentObject var store: TimeZoneStore

    var body: some View {
        SettingsForm {
            HStack(alignment: .firstTextBaseline) {
                Text("Offline public holidays").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(BundledHolidayCatalog.edition) edition")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.05)))
            }
            Text("Choose the countries and regions you want to see. Holiday data is included with TravelTime and works without an account, API key, or internet connection.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            if !BundledHolidayCatalog.covers(year: Calendar.current.component(.year, from: Date())) {
                Label("This calendar does not cover the current year. Update TravelTime for newer holiday data.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.orange.opacity(0.09)))
            }

            Divider()

            ForEach(Array(HolidayCountry.common.enumerated()), id: \.element.id) { index, country in
                let regionColor = Color(hex: country.accentHex)
                HStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(regionColor)
                            .frame(width: 9, height: 9)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(country.localName).font(.system(size: 13, weight: .medium))
                            Text("\(country.name) · \(country.id.uppercased())")
                                .font(.system(size: 10)).foregroundColor(.secondary)
                        }
                    }
                    Spacer(minLength: 24)
                    Toggle("", isOn: enabledBinding(for: country))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(regionColor)
                }
                .frame(maxWidth: .infinity)
                if index < HolidayCountry.common.count - 1 { Divider() }
            }

            Text("Coverage: \(BundledHolidayCatalog.coverageYears.lowerBound)–\(BundledHolidayCatalog.coverageYears.upperBound). Malaysia includes federal holidays only. Holiday definitions are refreshed with TravelTime updates.")
                .font(.system(size: 11)).foregroundColor(.secondary)
        }
        .onAppear {
            holidayStore.installEnabledHolidays(into: eventStore)
            store.onEventsChanged()
        }
    }

    private func enabledBinding(for country: HolidayCountry) -> Binding<Bool> {
        Binding(get: { holidayStore.isEnabled(country) }, set: { enabled in
            holidayStore.setEnabled(enabled, country: country, eventStore: eventStore)
            store.onEventsChanged()
        })
    }
}

// MARK: - Category pages

private struct CategoryGeneral: View {
    @EnvironmentObject var store: TimeZoneStore
    @State private var launchAtLogin = false

    var body: some View {
        SettingsForm {
            Toggle("Automatic location detection", isOn: $store.automaticLocationDetection)
            Text("When enabled, TravelTime periodically contacts ipwho.is or ipapi.co to suggest your current time zone. It never changes the system time zone without confirmation.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Divider()
            if Bundle.main.bundleIdentifier != nil {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue
                            let alert = NSAlert()
                            alert.messageText = "Failed to \(newValue ? "enable" : "disable") launch at login"
                            alert.informativeText = error.localizedDescription
                            alert.alertStyle = .warning
                            alert.runModal()
                        }
                    }
            } else {
                Text("Launch at login requires a bundled app (the .app must be in /Applications).")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            if Bundle.main.bundleIdentifier != nil {
                launchAtLogin = (SMAppService.mainApp.status == .enabled)
            }
        }
    }
}

private struct CategoryDisplay: View {
    @EnvironmentObject var store: TimeZoneStore
    @EnvironmentObject var eventStore: EventStore
    @State private var showImporter = false

    private var importedSources: [ImportedEvent] {
        eventStore.sources.filter { !$0.fileName.hasPrefix("Holidays · ") }
    }

    var body: some View {
        SettingsForm {
            Toggle("Show calendar (阳历 + 农历)", isOn: $store.showCalendar)
            Toggle("Show date in the menu bar", isOn: $store.showDateInMenuBar)
            Picker("Time format", selection: $store.use24Hour) {
                Text("24-hour").tag(true)
                Text("12-hour").tag(false)
            }
            .pickerStyle(.menu)

            Divider()

            Toggle("Show events (ICS)", isOn: $store.showEvents)
            Button("Import .ics…") { showImporter = true }
                .fileImporter(
                    isPresented: $showImporter,
                    allowedContentTypes: [UTType(filenameExtension: "ics") ?? .data],
                    allowsMultipleSelection: true
                ) { result in
                    switch result {
                    case .success(let urls):
                        importFiles(urls)
                    case .failure:
                        break
                    }
                }

            if !importedSources.isEmpty {
                Divider()
                Text("Imported calendars").font(.system(size: 12, weight: .medium))
                    .foregroundColor(store.palette.textSecondary)
                ForEach(importedSources) { source in
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(store.palette.accent)
                        Text(source.fileName)
                            .foregroundColor(store.palette.textPrimary)
                        Spacer(minLength: 0)
                        Text("\(source.events.count)")
                            .font(.system(size: 11))
                            .foregroundColor(store.palette.textTertiary)
                        Button(action: { removeSource(source.id) }) {
                            Image(systemName: "trash")
                                .foregroundColor(store.palette.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func importFiles(_ urls: [URL]) {
        for url in urls {
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let count = eventStore.importICS(text, fileName: url.lastPathComponent)
            if count > 0 { store.onEventsChanged() }
        }
    }

    private func removeSource(_ id: UUID) {
        eventStore.removeSource(id: id)
        store.onEventsChanged()
    }
}

private struct CategoryTimeZones: View {
    @EnvironmentObject var store: TimeZoneStore
    @State private var addSelection = 0

    var body: some View {
        SettingsForm {
            HStack {
                Picker("Add a time zone", selection: $addSelection) {
                    // Index tags keep Berlin & Frankfurt (same tz id, different
                    // names) both selectable.
                    ForEach(Array(SettingsView.commonZones.enumerated()), id: \.offset) { i, item in
                        Text(item.region.isEmpty ? item.label : "\(item.label) · \(item.region)")
                            .tag(i)
                    }
                }
                .labelsHidden()
                .frame(width: 220)

                Button("Add") {
                    guard addSelection < SettingsView.commonZones.count else { return }
                    let item = SettingsView.commonZones[addSelection]
                    // Dedupe by (id, label) — the same rule as the main panel,
                    // so Berlin and Frankfurt can both exist.
                    guard !store.zones.contains(where: { $0.id == item.id && $0.label == item.label }) else { return }
                    store.zones.append(ZoneEntry(id: item.id,
                                                 label: item.label,
                                                 region: item.region,
                                                 color: store.nextZoneColor()))
                }
                .disabled(addSelection >= SettingsView.commonZones.count
                          || store.zones.contains {
                              $0.id == SettingsView.commonZones[addSelection].id
                                  && $0.label == SettingsView.commonZones[addSelection].label
                          })
            }

            Divider()

            ForEach(store.zones, id: \.uuid) { zone in
                HStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: zone.color))
                        .frame(width: 4, height: 16)
                    Text("\(zone.label) (\(zone.id))")
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Spacer()
                    if zone.uuid == store.currentZoneUUID {
                        Text("Current")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                    }
                    Button("Remove") {
                        store.zones.removeAll { $0.uuid == zone.uuid }
                    }
                    .disabled(zone.uuid == store.currentZoneUUID)
                    .accessibilityLabel("Remove \(zone.label)")
                }
                .padding(.vertical, 2)
            }

            Button("Restore Defaults") {
                store.zones = TimeZoneStore.defaultZones
            }
        }
    }
}

private struct CategoryUpdate: View {
    @StateObject private var updater = Updater()

    var body: some View {
        SettingsForm {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13))
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Software Update")
                        .font(.system(size: 13, weight: .medium))
                    Text(updateStatusText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(updateButtonTitle) {
                    switch updater.state {
                    case .available(_, let release):
                        Task { await updater.update(release: release) }
                    default:
                        Task { await updater.check() }
                    }
                }
                .disabled(updater.isBusy)
            }
        }
    }

    private var updateStatusText: String {
        switch updater.state {
        case .idle: return "Check GitHub for a new version"
        case .checking: return "Checking…"
        case .available(let v, _): return "Version \(v) is available — click Update to install it in place"
        case .downloading: return "Downloading and installing, the app will relaunch…"
        case .upToDate: return "You are running the latest version"
        case .error(let msg): return msg
        }
    }

    private var updateButtonTitle: String { updater.state.buttonTitle }
}

private struct CategoryUninstall: View {
    @State private var showUninstallConfirm = false
    @State private var isUninstalling = false

    var body: some View {
        SettingsForm {
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uninstall TravelTime")
                        .font(.system(size: 13, weight: .medium))
                    Text("Removes the app and all local data (requires authorization)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Uninstall…", role: .destructive) {
                    showUninstallConfirm = true
                }
                .disabled(isUninstalling)
            }
            .confirmationDialog("Uninstall TravelTime?",
                                isPresented: $showUninstallConfirm,
                                titleVisibility: .visible) {
                Button("Uninstall and Delete Data", role: .destructive) {
                    uninstall()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The app will be deleted and quit immediately. If the icon lingers in Launchpad, run killall Dock in Terminal or log out and back in.")
            }
        }
    }

    /// Uninstall: clear all local data, deregister login item, delete the bundle, then quit
    private func uninstall() {
        guard !isUninstalling else { return }
        isUninstalling = true

        let fm = FileManager.default
        let home = NSHomeDirectory()
        let bundleID = Bundle.main.bundleIdentifier ?? "com.atom.tzbar"

        // 1. UserDefaults (preferences)
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        // Also remove the plist file directly in case it lingers
        let prefsPlist = "\(home)/Library/Preferences/\(bundleID).plist"
        try? fm.removeItem(atPath: prefsPlist)

        // 2. Application Support
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TravelTime", isDirectory: true) {
            try? fm.removeItem(at: appSupport)
        }

        // 3. Caches
        if let cachesDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? fm.removeItem(at: cachesDir.appendingPathComponent(bundleID))
            try? fm.removeItem(at: cachesDir.appendingPathComponent("TravelTime"))
        }

        // 4. Saved Application State (window restore)
        let savedState = "\(home)/Library/Saved Application State/\(bundleID).savedState"
        try? fm.removeItem(atPath: savedState)

        // 5. HTTPStorages (URLSession cookies/cache)
        let httpStorages = "\(home)/Library/HTTPStorages/\(bundleID)"
        try? fm.removeItem(atPath: httpStorages)

        // 6. Logs
        try? fm.removeItem(atPath: "\(home)/Library/Logs/TravelTime")

        // 7. Containers (sandbox, if any)
        try? fm.removeItem(atPath: "\(home)/Library/Containers/\(bundleID)")

        // 8. Temporary files (update leftovers)
        let tmpBase = NSTemporaryDirectory()
        if let tmpItems = try? fm.contentsOfDirectory(atPath: tmpBase) {
            for item in tmpItems where item.hasPrefix("tzbar-update-") {
                try? fm.removeItem(atPath: "\(tmpBase)/\(item)")
            }
        }

        // 9. Deregister the login item
        if Bundle.main.bundleIdentifier != nil {
            try? SMAppService.mainApp.unregister()
        }

        // 10. Delete the app bundle (admin rights)
        //     Also kill Dock to clear Launchpad tile cache
        let appPath = Bundle.main.bundlePath
        let script = """
            do shell script "rm -rf " & quoted form of "\(appPath)" & " && killall Dock" with administrator privileges
            """
        Task {
            do {
                try await PrivilegedRunner.run(script: script)
                // App bundle deleted; quit so the process exits cleanly.
                // isUninstalling is not reset here because the app terminates immediately.
                NSApp.terminate(nil)
            } catch {
                isUninstalling = false
                NSAlert(error: error).runModal()
            }
        }
    }
}

// MARK: - Reusable container

/// One page of the settings (used inside the NavigationSplitView detail).
/// Plain padded scroll card; the SwiftUI Form style was avoided because it
/// changes visual density per-macOS-SDK and fights the rest of the app's
/// styling on 14 / 26.
struct SettingsForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 22, weight: .bold))
                    Text(subtitle).font(.system(size: 11.5)).foregroundColor(.secondary)
                }.padding(.bottom, 2)
                content
            }
            // The Settings window uses a transparent full-size title bar. A
            // fixed top inset keeps long, scrolled pages below the traffic
            // lights/title-bar region on every supported macOS release.
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    var isDestructive = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 12, weight: .semibold))
                .foregroundColor(isDestructive ? .red : .secondary)
            content
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(isDestructive ? Color.red.opacity(0.2) : Color.primary.opacity(0.07), lineWidth: 1))
    }
}

// MARK: - About

private struct CategoryAbout: View {
    var body: some View {
        SettingsForm {
            VStack(spacing: 14) {
                // App icon (the bundled .icns when present, generic otherwise).
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(spacing: 3) {
                    Text("TravelTime")
                        .font(.system(size: 17, weight: .semibold))
                    Text(versionText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

            Divider()

            LabeledContent("Author") {
                Text("susunola")
            }
            LabeledContent("Email") {
                if let url = URL(string: "mailto:atomwangnus@hotmail.com") {
                    Link("atomwangnus@hotmail.com", destination: url)
                        .foregroundColor(.blue)
                }
            }

            Text("Made for travellers juggling time zones across the world.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
    }

    private var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(short) (\(build))"
    }
}
