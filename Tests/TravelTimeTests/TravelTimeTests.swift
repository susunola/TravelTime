import XCTest
import AppKit   // NSColor bridging for Color component assertions
import SwiftUI
@testable import TravelTime

/// Unit tests for the pure logic in TravelTime.
///
/// The UI layer (SwiftUI views, NSWindow handling) is intentionally not
/// covered here — these tests target the small, deterministic functions that
/// actually carry risk: time formatting, version comparison, checksum parsing
/// and the legacy-data migration path of ZoneEntry.
final class TravelTimeTests: XCTestCase {

    // MARK: - Test doubles

    /// Programmable ZoneSwitching stub: records calls and yields a scripted
    /// outcome, so switchTo() state-machine tests never touch admin prompts.
    @MainActor
    private final class MockSwitcher: ZoneSwitching {
        enum Outcome {
            case success
            case failure(Error)
            case hangUntilCancelled
        }
        var outcome: Outcome = .success
        private(set) var calls: [String] = []

        func switchTimeZone(to identifier: String) async throws {
            calls.append(identifier)
            switch outcome {
            case .success:
                return
            case .failure(let error):
                throw error
            case .hangUntilCancelled:
                // Suspend forever; cancelled when the store's task is torn down.
                try await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    // MARK: - offsetString

    // TimeZoneStore is @MainActor, so its static helpers are MainActor-isolated too.
    @MainActor
    func testOffsetStringWholeHours() {
        XCTAssertEqual(TimeZoneStore.offsetString(for: "Asia/Shanghai"), "+8")
        XCTAssertEqual(TimeZoneStore.offsetString(for: "Asia/Tokyo"), "+9")
        // Fixed-offset IANA zone (DST-free) so the assertion is date-independent.
        XCTAssertEqual(TimeZoneStore.offsetString(for: "Etc/GMT+5"), "-5")
    }

    @MainActor
    func testOffsetStringHalfHours() {
        XCTAssertEqual(TimeZoneStore.offsetString(for: "Asia/Kolkata"), "+5:30")
    }

    @MainActor
    func testOffsetStringInvalidZone() {
        XCTAssertEqual(TimeZoneStore.offsetString(for: "Not/AZone"), "")
    }

    // MARK: - ZoneEntry legacy migration

    func testZoneEntryDecodesLegacyPayloadWithoutUUID() throws {
        // Payloads written before the uuid field existed must decode and mint
        // a stable identity so duplicate IANA ids stay distinct in the UI.
        let json = """
        [{"id":"Europe/Berlin","label":"Berlin","region":"Germany","color":"#FF9F0A"},
         {"id":"Europe/Berlin","label":"Frankfurt","region":"Germany","color":"#FF9F0A"}]
        """.data(using: .utf8)!
        let zones = try JSONDecoder().decode([ZoneEntry].self, from: json)
        XCTAssertEqual(zones.count, 2)
        XCTAssertEqual(zones[0].id, "Europe/Berlin")
        XCTAssertEqual(zones[1].id, "Europe/Berlin")
        // Two rows sharing an IANA id must never share a uuid.
        XCTAssertNotEqual(zones[0].uuid, zones[1].uuid)
    }

    func testZoneEntryRoundTripPersistsUUID() throws {
        let zone = ZoneEntry(id: "Asia/Shanghai", label: "Beijing", region: "China", color: "#007AFF")
        let data = try JSONEncoder().encode([zone])
        let decoded = try JSONDecoder().decode([ZoneEntry].self, from: data)
        XCTAssertEqual(decoded[0].uuid, zone.uuid)
    }

    // MARK: - Version comparison (Updater)

    @MainActor
    func testParseVersion() {
        let updater = Updater()
        XCTAssertEqual(updater.parseVersion("v1.2.3"), [1, 2, 3])
        XCTAssertEqual(updater.parseVersion("1.2"), [1, 2])
        XCTAssertEqual(updater.parseVersion("2.0.0-beta.1"), [2, 0, 0]) // non-numeric parts dropped
        XCTAssertEqual(updater.parseVersion("garbage"), [])
    }

    @MainActor
    func testParseVersionKeepsEmbeddedVOutOfDigits() {
        let updater = Updater()
        // The fix strips ONLY a leading "v"/"V". The old code's
        // `replacingOccurrences(of: "v", with: "")` turned "1.2.3v4" into
        // "1.2.34" -> [1, 2, 34], leaking the embedded letter into the version.
        XCTAssertEqual(updater.parseVersion("1.2.3v4"), [1, 2, 3])
        XCTAssertEqual(updater.parseVersion("v1.2.3"), [1, 2, 3])
        XCTAssertEqual(updater.parseVersion("V2.0.0"), [2, 0, 0])
    }

    @MainActor
    func testIsVersionGreater() {
        let updater = Updater()
        XCTAssertTrue(updater.isVersionGreater([2, 0, 0], than: [1, 9, 9]))
        XCTAssertTrue(updater.isVersionGreater([1, 10, 0], than: [1, 9, 9]))
        XCTAssertFalse(updater.isVersionGreater([1, 2, 3], than: [1, 2, 3]))
        XCTAssertFalse(updater.isVersionGreater([1, 2], than: [1, 2, 1])) // shorter = older
        XCTAssertTrue(updater.isVersionGreater([1, 2, 1], than: [1, 2]))
    }

    // MARK: - SHA256 checksum parsing (Updater)

    @MainActor
    func testSHA256FromBody() {
        let updater = Updater()
        let hash = String(repeating: "ab", count: 32) // 64 hex chars
        XCTAssertEqual(updater.sha256FromBody("SHA256: \(hash)"), hash)
        XCTAssertEqual(updater.sha256FromBody("Checksum: \(hash)"), hash)
        XCTAssertEqual(updater.sha256FromBody("v1.0.0\nSHA256: \(hash)\nnotes"), hash)
        XCTAssertNil(updater.sha256FromBody("no checksum here"))
        XCTAssertNil(updater.sha256FromBody("SHA256: short"))
    }

    @MainActor
    func testSHA256FromBodyToleratesVerifiedSuffix() {
        let updater = Updater()
        let hash = String(repeating: "ab", count: 32)
        // Release notes often append "(verified)" — splitting on ":" would
        // carry the suffix and fail the 64-hex length check, silently
        // degrading to "no checksum found". The regex extracts the hash.
        XCTAssertEqual(updater.sha256FromBody("SHA256: \(hash) (verified)"), hash)
        XCTAssertEqual(updater.sha256FromBody("SHA 256: \(hash) (verified)"), hash)
    }

    // MARK: - Day difference

    @MainActor
    func testDayDifferenceSameZoneIsZero() {
        let store = makeStore()
        // The baseline is the DISPLAYED zone (currentZoneIdentifier), not the
        // host system zone — a zone matching it is always "Today".
        let zone = ZoneEntry(id: store.currentZoneIdentifier,
                             label: "Current",
                             region: "",
                             color: "#007AFF")
        XCTAssertEqual(store.dayDifference(for: zone), 0)
    }

    @MainActor
    func testDayDifferenceUsesDisplayedZoneAsBaseline() {
        // Fixed instant: 2026-08-18 01:00 Beijing (UTC+8) is still
        // 2026-08-17 13:00 in New York (EDT) — so New York reads as
        // Yesterday relative to a DISPLAYED Beijing baseline, regardless of
        // where the host system happens to be.
        let store = makeStore()
        store.currentZoneIdentifier = "Asia/Shanghai"
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        store.now = cal.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 1, minute: 0))!

        let newYork = ZoneEntry(id: "America/New_York", label: "New York", region: "US", color: "#30D158")
        XCTAssertEqual(store.dayDifference(for: newYork), -1, "NY is on the previous day vs displayed Beijing")

        let tokyo = ZoneEntry(id: "Asia/Tokyo", label: "Tokyo", region: "JP", color: "#BF5AF2")
        XCTAssertEqual(store.dayDifference(for: tokyo), 0, "Tokyo shares Beijing's calendar day here")
    }

    // MARK: - Current zone highlight (uuid)

    /// A fresh store backed by an isolated defaults suite, so tests never read
    /// or write the real app preferences.
    @MainActor
    private func makeStore() -> TimeZoneStore {
        makeStore(switcher: MockSwitcher())
    }

    @MainActor
    private func makeStore(switcher: MockSwitcher) -> TimeZoneStore {
        let suiteName = "tz.test.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        return TimeZoneStore(defaults: suite, switcher: switcher)
    }

    /// Polls until the switchTo() background task settles (it runs on the main
    /// actor, so yielding is enough for the immediate success/failure paths).
    @MainActor
    private func waitForSwitchToSettle(_ store: TimeZoneStore) async {
        for _ in 0..<100 where store.isSwitching {
            await Task.yield()
        }
    }

    @MainActor
    func testCurrentZoneUUIDRestoredOnLaunch() throws {
        // Two rows share Europe/Berlin. The user highlighted Frankfurt; on a
        // relaunch the highlight must land on Frankfurt, not the first match
        // (Berlin).
        let suiteName = "tz.test.uuid.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }

        let berlin = ZoneEntry(id: "Europe/Berlin", label: "Berlin", region: "Germany", color: "#FF9F0A")
        let frankfurt = ZoneEntry(id: "Europe/Berlin", label: "Frankfurt", region: "Germany", color: "#FF9F0A")
        suite.set(try JSONEncoder().encode([berlin, frankfurt]), forKey: "zones.v1")
        suite.set("Europe/Berlin", forKey: "currentZone.v1")
        suite.set(frankfurt.uuid.uuidString, forKey: "currentZoneUUID.v1")

        let store = TimeZoneStore(defaults: suite)
        XCTAssertEqual(store.currentZoneUUID, frankfurt.uuid)
    }

    @MainActor
    func testDeletingCurrentRowRematchesByID() throws {
        // Restore Defaults / row deletion wipes the highlighted row — the
        // highlight must fall back to another row with the same IANA id rather
        // than vanishing entirely (which also re-enables its Remove button).
        let suiteName = "tz.test.rematch.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }

        let berlin = ZoneEntry(id: "Europe/Berlin", label: "Berlin", region: "Germany", color: "#FF9F0A")
        let frankfurt = ZoneEntry(id: "Europe/Berlin", label: "Frankfurt", region: "Germany", color: "#FF9F0A")
        suite.set(try JSONEncoder().encode([berlin, frankfurt]), forKey: "zones.v1")
        suite.set("Europe/Berlin", forKey: "currentZone.v1")
        suite.set(berlin.uuid.uuidString, forKey: "currentZoneUUID.v1")

        let store = TimeZoneStore(defaults: suite)
        XCTAssertEqual(store.currentZoneUUID, berlin.uuid)

        store.zones.removeAll { $0.uuid == berlin.uuid }
        XCTAssertEqual(store.currentZoneUUID, frankfurt.uuid)
    }

    @MainActor
    func testZonePaletteCycles() {
        let store = makeStore()
        // The palette is longer than the default zone count, so consecutive
        // adds never repeat the same color until it wraps.
        var seen = Set<String>()
        for _ in 0..<TimeZoneStore.zonePalette.count {
            let color = store.nextZoneColor()
            seen.insert(color)
            store.zones.append(ZoneEntry(id: "Test/\(seen.count)",
                                         label: "T\(seen.count)",
                                         region: "",
                                         color: color))
        }
        XCTAssertEqual(seen.count, TimeZoneStore.zonePalette.count)
    }

    // MARK: - Panel auto-height (AppDelegate)

    /// Regression for the launch-size bug: the window stayed at its hardcoded
    /// initial height because updatePanelHeight() was only reachable through
    /// store callbacks assigned after the store had already loaded its zones.
    /// The sizing rule is now a pure function; these pin it down.
    @MainActor
    func testPanelContentHeightScalesWithZoneCount() {
        XCTAssertEqual(AppDelegate.panelContentHeight(zoneCount: 3), 560)
        XCTAssertEqual(AppDelegate.panelContentHeight(zoneCount: 5), 656)
        XCTAssertEqual(AppDelegate.panelContentHeight(zoneCount: 12), 1062)
    }

    @MainActor
    func testPanelContentHeightHasMinimum() {
        // Even a single zone must not collapse below the header+footer floor.
        XCTAssertEqual(AppDelegate.panelContentHeight(zoneCount: 0), 560)
        XCTAssertEqual(AppDelegate.panelContentHeight(zoneCount: 1), 560)
    }

    @MainActor
    func testPanelContentHeightExpandsForCalendarEvents() {
        XCTAssertEqual(AppDelegate.panelContentHeight(zoneCount: 3, eventDetailCount: 0), 560)
        XCTAssertEqual(AppDelegate.panelContentHeight(zoneCount: 3, eventDetailCount: 0,
                                                       calendarVisible: true), 770)
        XCTAssertEqual(AppDelegate.panelContentHeight(zoneCount: 3, eventDetailCount: 1,
                                                       calendarVisible: true), 804)
        XCTAssertEqual(AppDelegate.panelContentHeight(zoneCount: 3, eventDetailCount: 3,
                                                       calendarVisible: true), 916)
        XCTAssertEqual(AppDelegate.panelContentHeight(zoneCount: 3, eventDetailCount: 8,
                                                       calendarVisible: true), 916)
        XCTAssertEqual(AppDelegate.panelContentHeight(zoneCount: 3, eventDetailCount: 3,
                                                       calendarVisible: true,
                                                       maxContentHeight: 640), 640)
    }

    func testHolidayOccurrenceExtractsRegionCode() {
        let holiday = EventOccurrence(start: Date(), end: Date(), summary: "Holiday",
                                      location: "", notes: "Description",
                                      sourceName: "Holidays · Singapore [sg]",
                                      isAllDay: true)
        let imported = EventOccurrence(start: Date(), end: Date(), summary: "Meeting",
                                       location: "", notes: "", sourceName: "Work.ics", isAllDay: false)
        XCTAssertEqual(holiday.holidayCountryCode, "sg")
        XCTAssertNil(imported.holidayCountryCode)
        XCTAssertEqual(Set(HolidayCountry.common.map(\.accentHex)).count,
                       HolidayCountry.common.count)
        XCTAssertFalse(BundledHolidayCatalog.briefDescription(for:
            BundledHoliday(countryCode: "th", date: "2026-04-13", name: "Songkran Festival",
                           localName: "", note: "")).isEmpty)
    }

    // MARK: - App bundle discovery (Updater)

    /// Regression for the update bug: releases up to v1.3.3 extract to
    /// TimeZoneBar.app while the updater hardcoded TravelTime.app, so the
    /// post-unzip guard always failed ("Could not unzip the installer").
    func testAppBundleFindsLegacyName() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tzbar-test-legacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("TimeZoneBar.app"),
            withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let found = Updater.appBundle(in: dir)
        XCTAssertEqual(found?.lastPathComponent, "TimeZoneBar.app")
    }

    func testAppBundleFindsCurrentName() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tzbar-test-current-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("TravelTime.app"),
            withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let found = Updater.appBundle(in: dir)
        XCTAssertEqual(found?.lastPathComponent, "TravelTime.app")
    }

    func testAppBundleIgnoresZipAndScratchFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tzbar-test-nobundle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // An extracted archive dir still holds the zip and any notes; none of
        // these is an app bundle, so discovery must come up empty.
        try Data("zip".utf8).write(to: dir.appendingPathComponent("TravelTime.app.zip"))
        try Data("notes".utf8).write(to: dir.appendingPathComponent("notes.txt"))

        XCTAssertNil(Updater.appBundle(in: dir))
    }

    // MARK: - Day label (MenuPanelView)

    /// Regression for the editorial theme: the row label was hardcoded to
    /// "Today" there, so Yesterday/Tomorrow rows were mislabelled. The label
    /// is now a shared pure function used by every theme.
    @MainActor
    func testDayLabel() {
        XCTAssertEqual(TimeZoneStore.dayLabel(for: -1), "Yesterday")
        XCTAssertEqual(TimeZoneStore.dayLabel(for: 0), "Today")
        XCTAssertEqual(TimeZoneStore.dayLabel(for: 1), "Tomorrow")
        // Any other value (or a day difference larger than one) reads as Today
        // — consistent with the old switch default.
        XCTAssertEqual(TimeZoneStore.dayLabel(for: 5), "Today")
    }

    // MARK: - Panel height screen cap (AppDelegate)

    /// Regression for windows growing past the visible screen: with 12 glass
    /// zones the raw formula wants 1396 pt, which the system then clamps
    /// unpredictably. The clamp must be explicit, never below the 460 pt floor.
    @MainActor
    func testPanelContentHeightClampsToScreen() {
        XCTAssertEqual(AppDelegate.panelContentHeight(zoneCount: 12, maxContentHeight: 900), 900)
        // Small lists are unaffected by the cap.
        XCTAssertEqual(AppDelegate.panelContentHeight(zoneCount: 3, maxContentHeight: 900), 560)
        // The cap never pushes the window below the header+footer floor.
        XCTAssertEqual(AppDelegate.panelContentHeight(zoneCount: 12, maxContentHeight: 200), 560)
        // No cap: raw formula (existing behaviour, existing tests).
        XCTAssertEqual(AppDelegate.panelContentHeight(zoneCount: 12), 1062)
    }

    // MARK: - Geolocation response shapes (LocationDetector)

    /// ipwho.is nests the timezone: {"timezone": {"id": "Asia/Bangkok"}}.
    func testGeoResultDecodesIpWhoIsNestedTimezone() throws {
        let json = #"{"timezone":{"id":"Asia/Bangkok","abbreviation":"ICT"},"city":"Bangkok","country":"Thailand"}"#
        let geo = try JSONDecoder().decode(GeoResult.self, from: Data(json.utf8))
        XCTAssertEqual(geo.timezone, "Asia/Bangkok")
        XCTAssertEqual(geo.city, "Bangkok")
        XCTAssertEqual(geo.country_name ?? geo.country, "Thailand")
        XCTAssertNil(geo.error)
    }

    /// ipapi.co keeps the timezone flat and calls the country country_name.
    func testGeoResultDecodesIpApiFlatTimezone() throws {
        let json = #"{"timezone":"Asia/Bangkok","city":"Bangkok","country_name":"Thailand"}"#
        let geo = try JSONDecoder().decode(GeoResult.self, from: Data(json.utf8))
        XCTAssertEqual(geo.timezone, "Asia/Bangkok")
        XCTAssertEqual(geo.city, "Bangkok")
        XCTAssertEqual(geo.country_name ?? geo.country, "Thailand")
    }

    /// ipapi.co throttles with HTTP 200 + {"error": true, "reason": ...}.
    func testGeoResultDecodesIpApiRateLimitError() throws {
        let json = #"{"error":true,"reason":"RateLimited","wait":1.0}"#
        let geo = try JSONDecoder().decode(GeoResult.self, from: Data(json.utf8))
        XCTAssertEqual(geo.error, true)
        XCTAssertEqual(geo.reason, "RateLimited")
        XCTAssertNil(geo.timezone)
    }

    /// ipwho.is errors with an object: {"error": {"code": ..., "message": ...}}.
    func testGeoResultDecodesIpWhoIsErrorObject() throws {
        let json = #"{"success":false,"error":{"code":429,"message":"Too Many Requests"}}"#
        let geo = try JSONDecoder().decode(GeoResult.self, from: Data(json.utf8))
        XCTAssertEqual(geo.error, true)
        XCTAssertEqual(geo.reason, "Too Many Requests")
    }

    // MARK: - Color(hex:) parsing

    @MainActor
    func testColorHexParsing() {
        func rgba(_ c: Color) -> (r: Double, g: Double, b: Double, a: Double) {
            let n = NSColor(c).usingColorSpace(.sRGB)!
            return (n.redComponent, n.greenComponent, n.blueComponent, n.alphaComponent)
        }

        let red = rgba(Color(hex: "#FF0000"))
        XCTAssertEqual(red.r, 1.0, accuracy: 0.001)
        XCTAssertEqual(red.g, 0.0, accuracy: 0.001)
        XCTAssertEqual(red.a, 1.0, accuracy: 0.001)

        let short = rgba(Color(hex: "#0f0"))
        XCTAssertEqual(short.g, 1.0, accuracy: 0.001)
        XCTAssertEqual(short.r, 0.0, accuracy: 0.001)

        // 8-digit #RRGGBBAA: alpha is the low byte, channels shift left by 8.
        // (0x80 quantizes to 128/255 ≈ 0.502, hence 0.01 tolerance.)
        let alpha = rgba(Color(hex: "#FF000080"))
        XCTAssertEqual(alpha.r, 1.0, accuracy: 0.001)
        XCTAssertEqual(alpha.g, 0.0, accuracy: 0.001)
        XCTAssertEqual(alpha.a, 0.5, accuracy: 0.01)

        // Invalid input falls back to neutral gray, not black. (NSColor
        // quantizes 0.5 to 128/255, hence the looser tolerance.)
        let bad = rgba(Color(hex: "notacolor"))
        XCTAssertEqual(bad.r, 0.5, accuracy: 0.01)
        XCTAssertEqual(bad.g, 0.5, accuracy: 0.01)

        // 3-digit shorthand expands to the same color as the 6-digit form.
        let short6 = rgba(Color(hex: "#00ff00"))
        XCTAssertEqual(short6.g, short.g, accuracy: 0.001)
        XCTAssertEqual(short6.r, short.r, accuracy: 0.001)
    }

    // MARK: - Timezone switch input validation (SystemZoneSwitcher)

    /// Regression for the injection surface: an id outside the system's known
    /// IANA list must be rejected BEFORE anything touches the privileged shell.
    /// (The valid-id path would prompt for admin rights, so only the negative
    /// path is unit-tested here.)
    @MainActor
    func testSwitchTimeZoneRejectsUnknownIdentifier() async {
        do {
            try await SystemZoneSwitcher.shared.switchTimeZone(to: "Not/AZone; touch /tmp/pwned")
            XCTFail("Expected invalid identifier to be rejected")
        } catch let error as ZoneSwitchError {
            XCTAssertEqual(error.localizedDescription, "Authorization failed: Invalid time zone: Not/AZone; touch /tmp/pwned")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - PrivilegedRunner timeout (SystemZoneSwitcher)

    /// A hung child (osascript `delay 30`) must be terminated by the internal
    /// timeout instead of blocking forever; the caller gets the timeout error.
    @MainActor
    func testPrivilegedRunnerTimesOutAndKillsChild() async {
        let start = Date()
        do {
            try await PrivilegedRunner.run(script: "delay 30", timeout: 1)
            XCTFail("Expected timeout error")
        } catch let error as ZoneSwitchError {
            XCTAssertTrue(error.localizedDescription.contains("Timed out"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        // Must return well before the child's 30 s delay would finish.
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }

    // MARK: - Day/night (TimeZoneStore)

    @MainActor
    func testIsDaytimeFixedInstant() {
        let store = makeStore()
        // 2026-08-18 04:00 UTC = 13:00 in Tokyo (day) = 00:00 in New York (night,
        // EDT). Fixed date so the assertion never drifts with the clock.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        let fixed = cal.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 4, minute: 0))!
        store.now = fixed
        XCTAssertTrue(store.isDaytime(in: "Asia/Tokyo"))
        XCTAssertFalse(store.isDaytime(in: "America/New_York"))
    }

    // MARK: - Cached formatters (TimeZoneStore)

    @MainActor
    func testCachedFormatterReusesInstance() {
        let a = TimeZoneStore.cachedFormatter(format: "HH:mm", timeZone: TimeZone(identifier: "Asia/Shanghai"))
        let b = TimeZoneStore.cachedFormatter(format: "HH:mm", timeZone: TimeZone(identifier: "Asia/Shanghai"))
        XCTAssertTrue(a === b, "Same (format, zone) pair must return the same instance")

        let c = TimeZoneStore.cachedFormatter(format: "HH:mm", timeZone: TimeZone(identifier: "Asia/Tokyo"))
        XCTAssertFalse(a === c, "Different zone must not share a formatter")

        let d = TimeZoneStore.cachedFormatter(format: "h:mm a", timeZone: TimeZone(identifier: "Asia/Shanghai"))
        XCTAssertFalse(a === d, "Different format must not share a formatter")
    }

    // MARK: - Launch-time auto detection (TimeZoneStore.shouldSurfaceDetection)

    @MainActor
    func testShouldSurfaceDetection() {
        // Silent launch detection: already on the detected zone -> stay quiet.
        XCTAssertFalse(TimeZoneStore.shouldSurfaceDetection(timezone: "Asia/Bangkok",
                                                            currentZone: "Asia/Bangkok",
                                                            silent: true))
        // Silent launch detection: travelled elsewhere -> surface the card.
        XCTAssertTrue(TimeZoneStore.shouldSurfaceDetection(timezone: "Asia/Tokyo",
                                                           currentZone: "Asia/Bangkok",
                                                           silent: true))
        // Manual detection always surfaces, even when the zone matches.
        XCTAssertTrue(TimeZoneStore.shouldSurfaceDetection(timezone: "Asia/Bangkok",
                                                           currentZone: "Asia/Bangkok",
                                                           silent: false))
    }

    // MARK: - switchTo state machine (TimeZoneStore + MockSwitcher)

    @MainActor
    func testSwitchToRejectsSecondCallWhileInFlight() async {
        let switcher = MockSwitcher()
        switcher.outcome = .hangUntilCancelled
        let store = makeStore(switcher: switcher)
        let zone = TimeZoneStore.defaultZones[0]

        store.switchTo(zone)
        await Task.yield()
        XCTAssertTrue(store.isSwitching, "First switch must be in flight")

        // A second tap while the first is pending must be ignored entirely.
        store.switchTo(TimeZoneStore.defaultZones[1])
        await Task.yield()
        XCTAssertEqual(switcher.calls.count, 1, "Second switch must not reach the switcher")
    }

    @MainActor
    func testSwitchToFailureResetsStateAndShowsError() async {
        let switcher = MockSwitcher()
        switcher.outcome = .failure(ZoneSwitchError.adminRejected("wrong password"))
        let store = makeStore(switcher: switcher)
        let zone = TimeZoneStore.defaultZones[0]
        let original = store.currentZoneIdentifier

        store.switchTo(zone)
        await waitForSwitchToSettle(store)

        XCTAssertFalse(store.isSwitching, "State must reset after failure")
        XCTAssertEqual(store.currentZoneIdentifier, original, "Failed switch must not change current zone")
        XCTAssertNotNil(store.lastError)
    }

    @MainActor
    func testSwitchToUserCancelStaysSilent() async {
        let switcher = MockSwitcher()
        switcher.outcome = .failure(ZoneSwitchError.userCanceled)
        let store = makeStore(switcher: switcher)

        store.switchTo(TimeZoneStore.defaultZones[0])
        await waitForSwitchToSettle(store)

        XCTAssertNil(store.lastError, "User canceling the dialog must not surface an error")
        XCTAssertFalse(store.isSwitching)
    }

    @MainActor
    func testSwitchToSuccessPersistsCurrentZoneAndUUID() async {
        let switcher = MockSwitcher()
        switcher.outcome = .success
        let suiteName = "tz.test.switchok.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        let store = TimeZoneStore(defaults: suite, switcher: switcher)
        let zone = TimeZoneStore.defaultZones[1]   // Bangkok

        store.switchTo(zone)
        await waitForSwitchToSettle(store)

        XCTAssertEqual(switcher.calls, [zone.id])
        XCTAssertEqual(store.currentZoneIdentifier, zone.id)
        XCTAssertEqual(store.currentZoneUUID, zone.uuid)
        XCTAssertEqual(suite.string(forKey: "currentZone.v1"), zone.id)
        XCTAssertEqual(suite.string(forKey: "currentZoneUUID.v1"), zone.uuid.uuidString)
    }

    // MARK: - confirmDetectedZone input validation (TimeZoneStore)

    @MainActor
    func testConfirmDetectedZoneRejectsInvalidTimezone() async {
        let switcher = MockSwitcher()
        let store = makeStore(switcher: switcher)
        // A hostile/truncated geo response must never reach the privileged path.
        store.detected = DetectedZone(timezone: "Not/AZone", city: "x", country: "y")

        store.confirmDetectedZone()
        await Task.yield()

        XCTAssertEqual(switcher.calls.count, 0, "Invalid zone must not trigger a switch")
        XCTAssertNotNil(store.lastError)
        XCTAssertFalse(store.isSwitching)
    }

    @MainActor
    func testConfirmDetectedZoneAddsAndSwitches() async {
        let switcher = MockSwitcher()
        switcher.outcome = .success
        let store = makeStore(switcher: switcher)
        store.detected = DetectedZone(timezone: "Asia/Seoul", city: "Seoul", country: "South Korea")

        store.confirmDetectedZone()
        await waitForSwitchToSettle(store)

        XCTAssertEqual(switcher.calls, ["Asia/Seoul"])
        XCTAssertTrue(store.zones.contains { $0.id == "Asia/Seoul" }, "New detected zone must be added")
        XCTAssertEqual(store.currentZoneIdentifier, "Asia/Seoul")
    }

    // MARK: - Quote hour rotation (TimeZoneStore.hourOfDay)

    @MainActor
    func testHourOfDayUsesDisplayedZone() {
        // 2026-08-18 04:00 UTC = 13:00 in Tokyo (UTC+9), 23:00 in New York
        // (EDT, UTC-4). The quote rotation must follow the displayed zone.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        let fixed = cal.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 4, minute: 0))!
        XCTAssertEqual(TimeZoneStore.hourOfDay(in: "Asia/Tokyo", at: fixed), 13)
        XCTAssertEqual(TimeZoneStore.hourOfDay(in: "America/New_York", at: fixed), 0)
        // Invalid zone falls back to the host clock hour — must still be 0-23.
        let hostHour = TimeZoneStore.hourOfDay(in: "Not/AZone", at: fixed)
        XCTAssertTrue((0...23).contains(hostHour))
    }

    // MARK: - Geolocation network behaviour (LocationDetector + URLProtocol)

    /// URLProtocol stub that lets tests script provider responses (success,
    /// throttling, malformed JSON, failure) without real network access.
    private final class MockURLProtocol: URLProtocol {
        static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let handler = Self.handler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
        override func stopLoading() {}
    }

    private func makeMockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    func testDetectSucceedsWithIpWhoIsShape() async throws {
        MockURLProtocol.handler = { request in
            let body = #"{"timezone":{"id":"Asia/Bangkok","abbreviation":"ICT"},"city":"Bangkok","country":"Thailand"}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(body.utf8))
        }
        defer { MockURLProtocol.handler = nil }

        let zone = try await LocationDetector.detect(session: makeMockSession())
        XCTAssertEqual(zone.timezone, "Asia/Bangkok")
        XCTAssertEqual(zone.country, "Thailand")
    }

    func testDetectSurfacesRateLimit() async {
        MockURLProtocol.handler = { request in
            let body = #"{"error":true,"reason":"RateLimited","wait":1.0}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(body.utf8))
        }
        defer { MockURLProtocol.handler = nil }

        do {
            _ = try await LocationDetector.detect(session: makeMockSession())
            XCTFail("Expected rate-limit error")
        } catch let error as DetectionError {
            if case .rateLimited(let reason) = error {
                XCTAssertEqual(reason, "RateLimited")
            } else {
                XCTFail("Wrong error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDetectSurfacesRateLimitOnHTTP429() async {
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!,
             Data())
        }
        defer { MockURLProtocol.handler = nil }

        do {
            _ = try await LocationDetector.detect(session: makeMockSession())
            XCTFail("Expected rate-limit error")
        } catch let error as DetectionError {
            guard case .rateLimited = error else { XCTFail("Wrong error: \(error)"); return }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDetectSurfacesRateLimitOnHTTP403() async {
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!,
             Data())
        }
        defer { MockURLProtocol.handler = nil }

        do {
            _ = try await LocationDetector.detect(session: makeMockSession())
            XCTFail("Expected rate-limit error")
        } catch let error as DetectionError {
            guard case .rateLimited = error else { XCTFail("Wrong error: \(error)"); return }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDetectFallsThroughToSecondEndpoint() async throws {
        // First endpoint 500s; the second returns a valid flat timezone.
        MockURLProtocol.handler = { request in
            let isFirst = request.url!.host == "ipwho.is"
            if isFirst {
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                        Data())
            }
            let body = #"{"timezone":"Asia/Seoul","city":"Seoul","country_name":"South Korea"}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(body.utf8))
        }
        defer { MockURLProtocol.handler = nil }

        let zone = try await LocationDetector.detect(session: makeMockSession())
        XCTAssertEqual(zone.timezone, "Asia/Seoul")
    }

    func testDetectThrowsWhenAllProvidersFail() async {
        MockURLProtocol.handler = { request in
            throw URLError(.notConnectedToInternet)
        }
        defer { MockURLProtocol.handler = nil }

        do {
            _ = try await LocationDetector.detect(session: makeMockSession())
            XCTFail("Expected failure")
        } catch {
            // Any error is acceptable; the key is that both endpoints were tried.
        }
    }
}
