import XCTest
@testable import TravelTime

final class HolidayStoreTests: XCTestCase {
    func testCatalogContainsExactlySupportedRegions() {
        XCTAssertEqual(Set(HolidayCountry.common.map(\.id)), Set(["cn", "hk", "sg", "my", "th"]))
        for country in HolidayCountry.common {
            XCTAssertFalse(BundledHolidayCatalog.events(for: country).isEmpty, country.id)
        }
    }

    func testCatalogCreatesStableAllDayEvents() {
        let china = HolidayCountry.common.first { $0.id == "cn" }!
        let events = BundledHolidayCatalog.events(for: china)
        XCTAssertTrue(events.allSatisfy(\.isAllDay))
        XCTAssertTrue(events.allSatisfy { $0.end.timeIntervalSince($0.start) == 86_400 })
        XCTAssertEqual(Set(events.map(\.uid)).count, events.count)
        XCTAssertTrue(events.contains { $0.summary.contains("国庆节") })
    }

    @MainActor
    func testTogglePersistsAndUpdatesEventSource() {
        let suite = "HolidayStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let eventStore = EventStore(persistent: false)
        let singapore = HolidayCountry.common.first { $0.id == "sg" }!
        let store = HolidayStore(defaults: defaults)

        store.setEnabled(true, country: singapore, eventStore: eventStore)
        XCTAssertTrue(store.isEnabled(singapore))
        XCTAssertEqual(eventStore.sources.count, 1)
        XCTAssertFalse(eventStore.sources[0].events.isEmpty)

        let restored = HolidayStore(defaults: defaults)
        XCTAssertTrue(restored.isEnabled(singapore))

        restored.setEnabled(false, country: singapore, eventStore: eventStore)
        XCTAssertFalse(restored.isEnabled(singapore))
        XCTAssertTrue(eventStore.sources.isEmpty)
    }

    @MainActor
    func testInstallingAgainReplacesInsteadOfDuplicating() {
        let suite = "HolidayStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let eventStore = EventStore(persistent: false)
        let thailand = HolidayCountry.common.first { $0.id == "th" }!
        let store = HolidayStore(defaults: defaults)
        store.setEnabled(true, country: thailand, eventStore: eventStore)
        store.installEnabledHolidays(into: eventStore)
        XCTAssertEqual(eventStore.sources.count, 1)
    }
}
