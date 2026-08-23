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

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.openSettings = { [weak self] in
            self?.openSettingsWindow()
        }
        store.onZonesChanged = { [weak self] in
            self?.updatePanelHeight()
        }
        store.onThemeChanged = { [weak self] in
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
        store.onEventsChanged = { [weak self] in
            // Importing events or selecting a day changes the events list
            // height; re-measure after layout so the window fits the content.
            DispatchQueue.main.async { self?.updatePanelHeight() }
        }
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
    static func panelContentHeight(zoneCount: Int, theme: Theme, maxContentHeight: CGFloat? = nil) -> CGFloat {
        let fixedChrome: CGFloat = theme == .editorial ? 400 : 360
        let wanted = max(460, fixedChrome + CGFloat(zoneCount) * theme.rowHeight + 24)
        guard let cap = maxContentHeight else { return wanted }
        return min(wanted, max(460, cap))
    }

    /// Largest content height that fits on the visible screen (menu bar and
    /// Dock excluded), leaving room for the title bar and a small margin.
    private var maxPanelContentHeight: CGFloat {
        guard let visible = NSScreen.main?.visibleFrame else { return .greatestFiniteMagnitude }
        return max(460, visible.height - 60)
    }

    /// Grows / shrinks the window so it exactly fits the number of zone rows.
    private func updatePanelHeight() {
        // setupPanel may not have run yet (e.g. a zones change during init),
        // so guard the implicit-unwrapped window.
        guard let panel = self.panel else { return }
        // Prefer the hosting view's natural content height over a hardcoded
        // chrome estimate — this tracks the real header/footer/row layout (and
        // theme differences) instead of the magic 360/400 constants in
        // panelContentHeight. fittingSize can read 0 before the first layout,
        // so fall back to the formula in that case.
        let natural: CGFloat
        // contentView is NSView?; fittingSize is an NSView property, so just
        // unwrap it (NSHostingView is generic over its content and can't be
        // inferred here, but the optional unwrap is all we need).
        if let hosting = panel.contentView, hosting.fittingSize.height > 0 {
            natural = hosting.fittingSize.height
        } else {
            var base = Self.panelContentHeight(zoneCount: store.zones.count, theme: store.theme)
            // Fallback path (before first layout): the calendar card adds a
            // fixed block of vertical space on top of the chrome estimate.
            if store.showCalendar { base += 140 }
            natural = base
        }
        let wanted = min(max(natural, 460), maxPanelContentHeight)
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

        // utilityWindow style: this is the combination the user has confirmed
        // actually renders on this machine. Borderless NSPanel and any
        // titlebar-true variants get blocked by the macOS 26 FrontBoard
        // scene fence for self-signed (no Team ID) apps.
        let p = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        p.title = "TravelTime"
        p.level = .normal
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.minSize = NSSize(width: 360, height: 460)
        p.setContentSize(NSSize(width: width, height: height))

        let hosting = NSHostingView(rootView: MenuPanelView().environmentObject(store).environmentObject(eventStore))
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
        let host = NSHostingController(rootView: SettingsView().environmentObject(store).environmentObject(eventStore))
        let window = NSWindow(contentViewController: host)
        window.title = "TravelTime Settings"
        window.setContentSize(NSSize(width: 480, height: 460))
        // `.resizable` is required for the user to drag the edges to resize —
        // the main panel uses the same mask. Without it, the window is fixed-size.
        // `.resizable` requires `.titled`, which is already present.
        window.styleMask = [.titled, .closable, .resizable]
        window.minSize = NSSize(width: 480, height: 460)
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
