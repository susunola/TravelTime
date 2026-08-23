import XCTest
@testable import TravelTime

final class EventStoreTests: XCTestCase {

    /// A UTC Gregorian calendar, matching how the expander is exercised in tests.
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1
        return c
    }

    // MARK: ICSImporter

    func testParseSingleTimedEvent() {
        let ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//EN
        BEGIN:VEVENT
        UID:single-1
        DTSTART:20260401T100000Z
        DTEND:20260401T110000Z
        SUMMARY:Lunch with Ada
        LOCATION:Canteen
        DESCRIPTION:Monthly sync
        END:VEVENT
        END:VCALENDAR
        """
        let events = ICSImporter.parse(ics)
        XCTAssertEqual(events.count, 1)
        let e = events[0]
        XCTAssertEqual(e.uid, "single-1")
        XCTAssertFalse(e.isAllDay)
        XCTAssertEqual(e.summary, "Lunch with Ada")
        XCTAssertEqual(e.location, "Canteen")
        XCTAssertEqual(e.notes, "Monthly sync")
        let cal = utc
        XCTAssertEqual(cal.component(.day, from: e.start), 1)
        XCTAssertEqual(cal.component(.month, from: e.start), 4)
        XCTAssertEqual(cal.component(.hour, from: e.start), 10)
    }

    func testParseAllDayEvent() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:allday-1
        DTSTART;VALUE=DATE:20260520
        DTEND;VALUE=DATE:20260521
        SUMMARY:Holiday
        END:VEVENT
        END:VCALENDAR
        """
        let events = ICSImporter.parse(ics)
        XCTAssertEqual(events.count, 1)
        let e = events[0]
        XCTAssertTrue(e.isAllDay)
        let cal = utc
        XCTAssertEqual(cal.component(.day, from: e.start), 20)
        XCTAssertEqual(cal.component(.month, from: e.start), 5)
    }

    func testParseRRULE() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:rrule-1
        DTSTART:20260406T090000Z
        DTEND:20260406T093000Z
        SUMMARY:Standup
        RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,WE;COUNT=6
        END:VEVENT
        END:VCALENDAR
        """
        let events = ICSImporter.parse(ics)
        XCTAssertEqual(events.count, 1)
        let rule = events[0].rrule
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.frequency, .weekly)
        XCTAssertEqual(rule?.interval, 1)
        XCTAssertEqual(rule?.count, 6)
        XCTAssertEqual(rule?.byDay?.count, 2)
        XCTAssertEqual(rule?.byDay?[0].weekday, 2)   // MO
        XCTAssertEqual(rule?.byDay?[1].weekday, 4)   // WE
    }

    func testParseLineUnfoldingAndEscape() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:fold-1
        DTSTART:20260401T100000Z
        SUMMARY:Line one\\nLine two\\, with comma
        END:VEVENT
        END:VCALENDAR
        """
        let events = ICSImporter.parse(ics)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].summary, "Line one\nLine two, with comma")
    }

    // MARK: RRULEExpander

    func testExpandDailyCount3() {
        let start = utc.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 9))!
        let ev = CalendarEvent(uid: "d", summary: "", location: "", notes: "", isAllDay: false,
                               start: start, end: start.addingTimeInterval(1800),
                               rrule: RecurrenceRule(frequency: .daily, interval: 1, count: 3))
        // Query the whole month.
        let from = utc.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        let to = utc.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let starts = RRULEExpander.occurrenceStarts(event: ev, from: from, to: to, calendar: utc)
        XCTAssertEqual(starts.count, 3)
        XCTAssertEqual(utc.component(.day, from: starts[0]), 1)
        XCTAssertEqual(utc.component(.day, from: starts[1]), 2)
        XCTAssertEqual(utc.component(.day, from: starts[2]), 3)
    }

    func testExpandWeeklyBYDAY6Occurrences() {
        // 2026-04-06 is a Monday. Weekly MO,WE for 3 weeks => 6 occurrences.
        let start = utc.date(from: DateComponents(year: 2026, month: 4, day: 6, hour: 9))!
        let rule = RecurrenceRule(frequency: .weekly, interval: 1, count: 6,
                                  byDay: [.init(weekday: 2, ordinal: nil), .init(weekday: 4, ordinal: nil)])
        let ev = CalendarEvent(uid: "w", summary: "", location: "", notes: "", isAllDay: false,
                               start: start, end: start.addingTimeInterval(1800), rrule: rule)
        let from = utc.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        let to = utc.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let starts = RRULEExpander.occurrenceStarts(event: ev, from: from, to: to, calendar: utc)
        XCTAssertEqual(starts.count, 6)
        let days = starts.map { utc.component(.day, from: $0) }.sorted()
        XCTAssertEqual(days, [6, 8, 13, 15, 20, 22])
        let weekdays = starts.map { utc.component(.weekday, from: $0) }.sorted()
        XCTAssertEqual(weekdays, [2, 2, 2, 4, 4, 4])   // three Mondays + three Wednesdays
    }

    func testExpandMonthlyFirstMonday() {
        // First Monday of every month, from Jan 2026.
        let start = utc.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 9))! // a Monday
        let rule = RecurrenceRule(frequency: .monthly,
                                  byDay: [.init(weekday: 2, ordinal: 1)])
        let ev = CalendarEvent(uid: "m", summary: "", location: "", notes: "", isAllDay: false,
                               start: start, end: start.addingTimeInterval(1800), rrule: rule)
        let from = utc.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let to = utc.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        let starts = RRULEExpander.occurrenceStarts(event: ev, from: from, to: to, calendar: utc)
        XCTAssertEqual(starts.count, 3)
        // Jan 5, Feb 2, Mar 2 are the first Mondays.
        let days = starts.map { utc.component(.day, from: $0) }
        XCTAssertEqual(days, [5, 2, 2])
        XCTAssertEqual(utc.component(.weekday, from: starts[0]), 2)
    }

    func testExpandYearly() {
        let start = utc.date(from: DateComponents(year: 2026, month: 7, day: 4, hour: 9))!
        let ev = CalendarEvent(uid: "y", summary: "", location: "", notes: "", isAllDay: false,
                               start: start, end: start.addingTimeInterval(1800),
                               rrule: RecurrenceRule(frequency: .yearly, interval: 1))
        let from = utc.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let to = utc.date(from: DateComponents(year: 2029, month: 1, day: 1))!
        let starts = RRULEExpander.occurrenceStarts(event: ev, from: from, to: to, calendar: utc)
        XCTAssertEqual(starts.count, 3)
        let years = starts.map { utc.component(.year, from: $0) }
        XCTAssertEqual(years, [2026, 2027, 2028])
        let months = starts.map { utc.component(.month, from: $0) }
        XCTAssertEqual(months, [7, 7, 7])
    }

    func testEventStoreQuery() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:q1
        DTSTART:20260406T090000Z
        DTEND:20260406T093000Z
        SUMMARY:Standup
        RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=2
        END:VEVENT
        END:VCALENDAR
        """
        let store = EventStore(persistent: false)
        _ = store.importICS(ics, fileName: "test.ics")
        defer { for s in store.sources { store.removeSource(id: s.id) } }

        let day = utc.date(from: DateComponents(year: 2026, month: 4, day: 6))!
        let occ = store.occurrences(on: day, calendar: utc)
        XCTAssertEqual(occ.count, 1)
        XCTAssertEqual(occ[0].summary, "Standup")

        // The second Monday (Apr 13) is also marked.
        let month = utc.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        let marked = store.daysWithEvents(in: month, calendar: utc)
        XCTAssertTrue(marked.contains(6))
        XCTAssertTrue(marked.contains(13))
        XCTAssertFalse(marked.contains(7))
    }
}
