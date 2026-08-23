import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Menu bar status item — best-effort. On macOS 26 the scene manager may
    // not display this for self-signed/ad-hoc builds (no Team ID), but we
    // still try — when it does work, the user can click it to open the panel.
    private var statusItem: NSStatusItem?

    // Primary UI: a regular NSWindow with .utilityWindow style. macOS 26
    // applies the system corner radius to it (smaller than the macOS 26
    // squircle, but it's the only style that consistently renders for
    // self-signed apps). We deliberately stay away from borderless and
    // transparent-titlebar variants because both trip the macOS 26
    // FrontBoard scene fence for self-signed builds.
    private var panel: NSWindow!

    private var settingsWindowController: NSWindowController?
    private var timerCancellable: AnyCancellable?
    private let store = TimeZoneStore()
    private let eventStore = EventStore()
    private let holidayStore = HolidayStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.openSettings = { [weak self] in
            self?.openSettingsWindow()
        }
        store.onZonesChanged = { [weak self] in
            self?.updatePanelHeight()
        }
        store.onMenuBarConfigChanged = { [weak self] in
            // The status-item title is rebuilt from menuBarText; refresh it
            // immediately on toggle instead of waiting for the next minute tick.
            self?.statusItem?.button?.title = " " + (self?.store.menuBarText ?? "")
        }
        store.onCalendarChanged = { [weak self] in
            // The card adds/removes a fixed block; re-measure after the next
            // layout pass so the hosting view's fittingSize reflects the new
            // content height.
            DispatchQueue.main.async { self?.updatePanelHeight() }
        }
        store.onCalendarDetailChanged = { [weak self] in
            DispatchQueue.main.async { self?.updatePanelHeight() }
        }
        store.onEventsChanged = { [weak self] in
            // Importing events or selecting a day changes the events list
            // height; re-measure after layout so the window fits the content.
            DispatchQueue.main.async { self?.updatePanelHeight() }
        }
        // Refresh enabled offline calendars on every catalogue upgrade, not
        // only after the user happens to open Settings.
        holidayStore.installEnabledHolidays(into: eventStore)
        store.chooseAvatar = { [weak self] in
            self?.chooseAvatarFile()
        }
        setupStatusItem()
        setupPanel()
        startTimer()
        // Silently probe the location once at launch; if the detected zone
        // differs from the displayed one, the panel shows a confirmation card
        // (the admin-gated system switch only happens on user confirmation).
        store.autoDetectOnLaunch()
        // Do NOT auto-show the panel on launch — in Dock mode the app opens
        // quietly and the user opens the window by clicking the Dock icon.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        // When the user closes the window with the red traffic light, the
        // panel-visibility flag (which gates the auto-timezone poll) follows.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.store.setPanelVisible(false)
            }
        }
    }

    /// Content height (points) for a given zone count and theme.
    ///
    /// Pure function so the sizing rule is unit-testable. The "fixed chrome"
    /// estimate covers header (~180-240) + list top/bottom padding (~20) +
    /// footer (~150), with extra allowance for the editorial header layout.
    /// Pass `maxContentHeight` to clamp against the visible screen; without it
    /// (tests) the raw formula is returned.
    static func panelContentHeight(zoneCount: Int, eventDetailCount: Int = 0,
                                   calendarVisible: Bool = false,
                                   maxContentHeight: CGFloat? = nil) -> CGFloat {
        // Includes header, tabs, footer and the always-present “Add time zone”
        // row. The old 292-point estimate omitted that final row, so a normal
        // five-zone list overflowed by almost exactly one row.
        // Include the 16-point traffic-light safe inset applied by the root
        // view; omitting it pushed the footer below the window edge.
        let fixedChrome: CGFloat = 366
        let visibleRows = min(max(eventDetailCount, 0), 3)
        let clockHeight = max(560, fixedChrome + CGFloat(zoneCount) * 58)
        // 780 pt fits the header, tabs, a six-week month grid and the empty
        // state without leaving a large dead zone above the shared footer.
        // When events exist, their detail rows add the space they need below.
        // the empty-state row), and the footer. Further event rows grow from
        // that baseline instead of stealing space from the calendar grid.
        // The first detail row includes title, region and a two-line holiday
        // explanation. Additional rows reserve the same readable footprint.
        let firstEventExpansion: CGFloat = visibleRows > 0 ? 34 : 0
        let calendarHeight: CGFloat = 770 + firstEventExpansion
            + CGFloat(max(visibleRows - 1, 0)) * 56
        let wanted = calendarVisible ? calendarHeight : clockHeight
        guard let cap = maxContentHeight else { return wanted }
        return min(wanted, max(560, cap))
    }

    /// Largest content height that fits on the visible screen (menu bar and
    /// Dock excluded), leaving room for the title bar and a small margin.
    private var maxPanelContentHeight: CGFloat {
        guard let visible = NSScreen.main?.visibleFrame else { return .greatestFiniteMagnitude }
        // Use the actual screen instead of a hard 760 pt cap. Calendar event
        // details should grow the window until it genuinely reaches the
        // display boundary; only then does the inner ScrollView take over.
        return max(560, visible.height - 40)
    }

    /// Grows / shrinks the window so it exactly fits the number of zone rows.
    private func updatePanelHeight() {
        // setupPanel may not have run yet (e.g. a zones change during init),
        // so guard the implicit-unwrapped window.
        guard let panel = self.panel else { return }
        let wanted = Self.panelContentHeight(zoneCount: store.zones.count,
                                             eventDetailCount: store.calendarEventDetailCount,
                                             calendarVisible: store.isCalendarSectionActive,
                                             maxContentHeight: maxPanelContentHeight)
        let width = panel.frame.width
        panel.setContentSize(NSSize(width: width, height: wanted))
        panel.layoutIfNeeded()
    }

    @objc private func handleWake(_ notification: Notification) {
        store.now = Date()
        statusItem?.button?.title = " " + store.menuBarText
    }

    // Dock icon click → show / hide the panel
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        togglePanel()
        return true
    }

    // Closing the window does not quit the app — the Dock icon stays and
    // clicking it reopens the panel.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "clock", accessibilityDescription: "TravelTime") {
                image.isTemplate = true
                button.image = image
            }
            button.imagePosition = .imageLeft
            button.title = " " + store.menuBarText
            button.target = self
            button.action = #selector(statusItemClicked(_:))
        }
        self.statusItem = item
    }

    @objc private func statusItemClicked(_ sender: AnyObject?) {
        togglePanel()
    }

    private func setupPanel() {
        let width: CGFloat = 400
        let height: CGFloat = 640

        // Keep a real titled window for reliable LaunchServices registration,
        // but extend content beneath its transparent title bar. This preserves
        // native traffic-light controls while avoiding a separate white title
        // strip, matching modern first-party macOS apps.
        let p = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.title = "TravelTime"
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.titlebarSeparatorStyle = .none
        p.isMovableByWindowBackground = true
        p.backgroundColor = NSColor(red: 247 / 255, green: 248 / 255, blue: 244 / 255, alpha: 1)
        p.level = .normal
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.minSize = NSSize(width: 420, height: 560)
        p.maxSize = NSSize(width: 520, height: maxPanelContentHeight)
        p.setContentSize(NSSize(width: 460, height: max(560, height)))

        let hosting = NSHostingView(rootView: MenuPanelView()
            .environmentObject(store)
            .environmentObject(eventStore)
            .environmentObject(holidayStore))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting
        p.center()
        self.panel = p
        // Size the window for the *current* zone list. The store's
        // onZonesChanged callback is assigned in applicationDidFinishLaunching,
        // which runs after `private let store = TimeZoneStore()` has already
        // loaded the zones (and fired their didSet), so the callback could
        // never size the initial window — it stayed at the hardcoded height
        // above no matter how many zones were loaded. This call closes that gap.
        updatePanelHeight()
    }

    private func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
            store.setPanelVisible(false)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        store.setPanelVisible(true)
        // Re-sync the auto-timezone warning banner with System Settings on
        // every open — `MenuPanelView.onAppear` only fires once, so toggling
        // "Set time zone automatically" while the panel was closed would
        // otherwise not be reflected until a relaunch.
        store.refreshAutoTimezoneFlag()
        // Errors from a previous interaction shouldn't linger on the next open.
        store.lastError = nil
    }

    private func startTimer() {
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                // Timer.publish(..., on: .main) guarantees main-thread delivery
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // The UI only displays down to the minute (HH:mm), so only
                    // publish when the minute actually changes. This collapses
                    // 60 redraws per minute into 1.
                    let now = Date()
                    guard !Calendar.current.isDate(now, equalTo: self.store.now, toGranularity: .minute) else { return }
                    self.store.now = now
                    self.statusItem?.button?.title = " " + self.store.menuBarText
                }
            }
    }

    private func openSettingsWindow() {
        if let existing = settingsWindowController {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: SettingsView()
            .environmentObject(store)
            .environmentObject(eventStore)
            .environmentObject(holidayStore))
        let window = NSWindow(contentViewController: host)
        window.title = "TravelTime Settings"
        window.setContentSize(NSSize(width: 760, height: 600))
        // `.resizable` is required for the user to drag the edges to resize —
        // the main panel uses the same mask. Without it, the window is fixed-size.
        // `.resizable` requires `.titled`, which is already present.
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 700, height: 540)
        window.center()
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        settingsWindowController = controller
    }

    /// Open panel for picking a custom avatar. The picked image is copied
    /// into Application Support/TravelTime/avatar.jpg and the store reloads
    /// its avatar path so the panel updates.
    private func chooseAvatarFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose Avatar"
        panel.prompt = "Choose"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]   // any image

        // Run modally; if user picks, copy into Application Support.
        let response = panel.runModal()
        guard response == .OK, let src = panel.url else { return }

        do {
            let fm = FileManager.default
            let support = try fm.url(for: .applicationSupportDirectory,
                                      in: .userDomainMask,
                                      appropriateFor: nil,
                                      create: true)
            let dir = support.appendingPathComponent("TravelTime", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let dst = dir.appendingPathComponent("avatar.jpg")

            // Replace any existing avatar atomically.
            if fm.fileExists(atPath: dst.path) {
                try fm.removeItem(at: dst)
            }
            try fm.copyItem(at: src, to: dst)

            store.reloadAvatar()
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
