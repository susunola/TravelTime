import SwiftUI
import ServiceManagement

/// macOS System Settings–style window: sidebar of 6 categories on the left,
/// detail page on the right. The user's last-selected category is persisted.
struct SettingsView: View {
    @EnvironmentObject var store: TimeZoneStore
    @State private var category: SettingsCategory = .display

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
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 280)
        } detail: {
            // Detail: the selected category.
            Group {
                switch category {
                case .general:    CategoryGeneral()
                case .display:    CategoryDisplay()
                case .timeZones:  CategoryTimeZones()
                case .appearance: CategoryAppearance()
                case .update:     CategoryUpdate()
                case .uninstall:  CategoryUninstall()
                case .about:      CategoryAbout()
                }
            }
            .frame(minWidth: 480, minHeight: 460)
        }
        .navigationTitle("TravelTime Settings")
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
    case general, display, timeZones, appearance, update, uninstall, about
    var id: Self { self }

    var title: String {
        switch self {
        case .general:    return "General"
        case .display:    return "Display"
        case .timeZones:  return "Time Zones"
        case .appearance: return "Appearance"
        case .update:     return "Software Update"
        case .uninstall:  return "Uninstall"
        case .about:      return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general:    return "gearshape"
        case .display:    return "rectangle.on.rectangle"
        case .timeZones:  return "globe"
        case .appearance: return "paintbrush"
        case .update:     return "arrow.down.circle"
        case .uninstall:  return "trash"
        case .about:      return "info.circle"
        }
    }
}

// MARK: - Category pages

private struct CategoryGeneral: View {
    @EnvironmentObject var store: TimeZoneStore
    @State private var launchAtLogin = false

    var body: some View {
        SettingsForm {
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

    var body: some View {
        SettingsForm {
            Toggle("Show calendar (阳历 + 农历)", isOn: $store.showCalendar)
            Toggle("Show date in the menu bar", isOn: $store.showDateInMenuBar)
            Picker("Time format", selection: $store.use24Hour) {
                Text("24-hour").tag(true)
                Text("12-hour").tag(false)
            }
            .pickerStyle(.menu)
        }
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

private struct CategoryAppearance: View {
    @EnvironmentObject var store: TimeZoneStore

    var body: some View {
        SettingsForm {
            // NOTE: .pickerStyle(.menu) only reads the Text inside each option
            // as the menu item title — any other views (ThemeSwatch, VStacks,
            // custom checkmarks) are silently dropped, and the system draws
            // its own checkmark on the selected item. So the menu holds plain
            // theme names only; the live preview is rendered below the picker
            // (ThemeSwatch is pointless inside the menu and caused the
            // duplicate-checkmark + time-only-label bug).
            Picker("Theme", selection: $store.theme) {
                ForEach(Theme.allCases) { theme in
                    Text(theme.displayName)
                        .tag(theme)
                }
            }
            .pickerStyle(.menu)

            // Live preview of the currently selected theme.
            HStack(spacing: 12) {
                ThemeSwatch(theme: store.theme)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.theme.displayName)
                        .font(.system(size: 13, weight: .medium))
                    Text(themeDescription(store.theme))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

// MARK: - Theme picker helpers

func themeDescription(_ theme: Theme) -> String {
    switch theme {
    case .minimal: return "White, hairline rows, compact"
    case .glass: return "Frosted cards, generous spacing"
    case .midnight: return "Dark with cyan accent"
    case .editorial: return "Serif type, lots of whitespace"
    }
}

struct ThemeSwatch: View {
    @EnvironmentObject var store: TimeZoneStore
    let theme: Theme

    /// Show the real current time (via the cached formatter) instead of a
    /// hardcoded "01:42" placeholder. Uses store.now so the preview keeps up
    /// with the minute tick like the real panel does.
    private var timeText: String {
        TimeZoneStore.cachedFormatter(format: "HH:mm").string(from: store.now)
    }

    var body: some View {
        ZStack {
            // Background surface per theme
            RoundedRectangle(cornerRadius: 6)
                .fill(bgColor)
                .frame(width: 44, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(borderColor, lineWidth: 0.5)
                )
            // Mini "dial" ring (matches real panel's accent ring)
            Circle()
                .stroke(accentColor, lineWidth: 2)
                .frame(width: 30, height: 30)
            // Mini time text in theme's typography
            Text(timeText)
                .font(.system(size: 11, weight: .semibold, design: previewDesign))
                .monospacedDigit()
                .foregroundColor(textColor)
        }
    }

    private var previewDesign: Font.Design {
        // Editorial is the only theme that uses serif for the time display.
        theme == .editorial ? .serif : .rounded
    }

    private var bgColor: Color {
        switch theme {
        case .minimal: return Color(hex: "#FFFFFF")
        case .glass: return Color(hex: "#F5F7FA")
        case .midnight: return Color(hex: "#1C1C1E")
        case .editorial: return Color(hex: "#FAFAF8")
        }
    }

    private var borderColor: Color {
        switch theme {
        case .minimal: return Color(hex: "#E5E5EA")
        case .glass: return Color(hex: "#E0E6ED")
        case .midnight: return Color(hex: "#3A3A3C")
        case .editorial: return Color(hex: "#E2E2DC")
        }
    }

    private var textColor: Color {
        switch theme {
        case .midnight: return Color(hex: "#F5F5F7")
        default: return Color(hex: "#1D1D1F")
        }
    }

    private var accentColor: Color {
        switch theme {
        case .minimal, .glass: return Color(hex: "#0A84FF")
        case .midnight: return Color(hex: "#64D2FF")
        case .editorial: return Color(hex: "#C41E3A")
        }
    }
}
