import XCTest
@testable import TravelTime

/// Verifies the 中国农历 conversion (generated and byte-checked against the
/// 6tail astronomical oracle) on a few hand-picked, high-signal dates:
///   - a normal lunar day that also carries a solar term (处暑),
///   - a Chinese New Year (正月初一) boundary,
///   - a leap-month new moon (闰六月初一),
///   - three solar terms spread across the year.
final class ChineseLunarCalendarTests: XCTestCase {

    /// UTC-anchored Gregorian calendar so the year/month/day components are
    /// date-stable regardless of the test machine's timezone.
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// Builds a Date at noon UTC for the given Gregorian y/m/d.
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    // MARK: - Full summaries

    func testSummary_ChuShu() {
        // 2026-08-23 — 丙午年 七月十一, and the day is the 处暑 solar term.
        let s = ChineseLunarCalendar.summary(for: date(2026, 8, 23), calendar: cal)
        XCTAssertEqual(s.ganZhiYear, "丙午")
        XCTAssertEqual(s.monthText, "七月")
        XCTAssertEqual(s.dayText, "十一")
        XCTAssertEqual(s.solarTerm, "处暑")
        XCTAssertEqual("\(s.ganZhiYear)年 \(s.monthText)\(s.dayText)", "丙午年 七月十一")
    }

    func testSummary_ChineseNewYear2026() {
        // 2026-02-17 — 丙午年 正月初一 (the lunar new year).
        let s = ChineseLunarCalendar.summary(for: date(2026, 2, 17), calendar: cal)
        XCTAssertEqual(s.ganZhiYear, "丙午")
        XCTAssertEqual(s.monthText, "正月")
        XCTAssertEqual(s.dayText, "初一")
        XCTAssertNil(s.solarTerm)
    }

    func testSummary_LeapSixthMonth2025() {
        // 2025-07-25 — 乙巳年 闰六月初一 (leap-month new moon).
        let d = ChineseLunarCalendar.lunarDate(for: date(2025, 7, 25), calendar: cal)
        XCTAssertTrue(d.isLeap)
        XCTAssertEqual(d.month, 6)
        XCTAssertEqual(d.day, 1)
        let s = ChineseLunarCalendar.summary(for: date(2025, 7, 25), calendar: cal)
        XCTAssertEqual(s.ganZhiYear, "乙巳")
        XCTAssertEqual(s.monthText, "闰六月")
        XCTAssertEqual(s.dayText, "初一")
    }

    // MARK: - Solar terms

    func testSolarTerms2026() {
        XCTAssertEqual(ChineseLunarCalendar.solarTermName(for: date(2026, 2, 4), calendar: cal), "立春")
        XCTAssertEqual(ChineseLunarCalendar.solarTermName(for: date(2026, 8, 7), calendar: cal), "立秋")
        XCTAssertEqual(ChineseLunarCalendar.solarTermName(for: date(2026, 12, 22), calendar: cal), "冬至")
        // A non-term day returns nil.
        XCTAssertNil(ChineseLunarCalendar.solarTermName(for: date(2026, 8, 8), calendar: cal))
    }

    // MARK: - Naming helpers

    func testMonthAndDayNames() {
        XCTAssertEqual(ChineseLunarCalendar.monthName(1, isLeap: false), "正月")
        XCTAssertEqual(ChineseLunarCalendar.monthName(6, isLeap: true), "闰六月")
        XCTAssertEqual(ChineseLunarCalendar.monthName(12, isLeap: false), "腊月")
        XCTAssertEqual(ChineseLunarCalendar.dayName(1), "初一")
        XCTAssertEqual(ChineseLunarCalendar.dayName(15), "十五")
        XCTAssertEqual(ChineseLunarCalendar.dayName(30), "三十")
    }

    func testGanZhiAndAnimal() {
        // 2026 → 丙午年, 马 (午). 2025 → 乙巳年, 蛇 (巳).
        XCTAssertEqual(ChineseLunarCalendar.ganZhiYear(2026), "丙午")
        XCTAssertEqual(ChineseLunarCalendar.animal(2026), "马")
        XCTAssertEqual(ChineseLunarCalendar.ganZhiYear(2025), "乙巳")
        XCTAssertEqual(ChineseLunarCalendar.animal(2025), "蛇")
    }
}
