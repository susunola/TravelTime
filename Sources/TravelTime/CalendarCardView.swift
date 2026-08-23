import SwiftUI

// MARK: - Calendar card (阳历 + 农历)

/// A compact month calendar shown in the panel: a header with the full solar
/// date, weekday, the Chinese lunar date (干支年 / 月 / 日) and any solar term,
/// followed by a 7-column mini-grid of the current month. Each cell shows the
/// Gregorian day number with its lunar day (or lunar month on a new-moon day)
/// beneath, and today is highlighted with the accent color.
struct CalendarCardView: View {
    @EnvironmentObject var store: TimeZoneStore
    let palette: ThemePalette

    private static let weekdayNames = ["日", "一", "二", "三", "四", "五", "六"]

    /// Gregorian calendar anchored to the displayed zone so the calendar
    /// reflects the same date the rest of the panel shows (not the host OS
    /// zone, which may differ by a day around midnight).
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: store.currentZoneIdentifier) ?? .current
        c.firstWeekday = 1   // Sunday-first
        return c
    }

    private var summary: ChineseLunarCalendar.Summary {
        ChineseLunarCalendar.summary(for: store.now, calendar: calendar)
    }

    private var monthTitle: String {
        let parts = calendar.dateComponents([.year, .month], from: store.now)
        return "\(parts.year ?? 0)年\(parts.month ?? 0)月"
    }

    private var solarDateText: String {
        let weekday = calendar.component(.weekday, from: store.now)
        let w = Self.weekdayNames[(weekday - 1 + 7) % 7]
        let parts = calendar.dateComponents([.month, .day], from: store.now)
        return "\(parts.month ?? 0)月\(parts.day ?? 0)日 周\(w)"
    }

    private struct Cell {
        let day: Int
        let lunarLabel: String
        let isToday: Bool
    }

    /// Leading blanks (before day 1) + one cell per day of the month, padded to
    /// a full week so the grid always aligns to 7 columns.
    private var cells: [Cell?] {
        let comps = calendar.dateComponents([.year, .month], from: store.now)
        let year = comps.year ?? 1
        let month = comps.month ?? 1
        guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)   // 1..7
        let today = calendar.dateComponents([.year, .month, .day], from: store.now)

        var result: [Cell?] = []
        for _ in 1..<firstWeekday { result.append(nil) }
        for day in range {
            let date = calendar.date(from: DateComponents(year: year, month: month, day: day))!
            let ld = ChineseLunarCalendar.lunarDate(for: date, calendar: calendar)
            // On a new-moon day (lunar day 1) show the lunar month name —
            // mirrors how paper calendars mark 正月 / 闰六月 etc.
            let lunarLabel = ld.day == 1
                ? ChineseLunarCalendar.monthName(ld.month, isLeap: ld.isLeap)
                : ChineseLunarCalendar.dayName(ld.day)
            let isToday = today.year == year && today.month == month && today.day == day
            result.append(Cell(day: day, lunarLabel: lunarLabel, isToday: isToday))
        }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: solar date + lunar date + solar term
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(solarDateText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(palette.textPrimary)
                    Text("\(summary.ganZhiYear)年 \(summary.monthText)\(summary.dayText)")
                        .font(.system(size: 13))
                        .foregroundColor(palette.textSecondary)
                    if let term = summary.solarTerm {
                        Text(term)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(palette.accent)
                    }
                }
                Spacer(minLength: 0)
                Text(monthTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(palette.textTertiary)
            }

            // Weekday header
            HStack(spacing: 0) {
                ForEach(Self.weekdayNames, id: \.self) { w in
                    Text(w)
                        .font(.system(size: 10))
                        .foregroundColor(palette.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Month grid
            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.0) { _, cell in
                    if let cell {
                        dayCell(cell)
                    } else {
                        Color.clear.frame(height: 30)
                    }
                }
            }
        }
        .padding(12)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func dayCell(_ cell: Cell) -> some View {
        VStack(spacing: 1) {
            Text("\(cell.day)")
                .font(.system(size: 12, weight: cell.isToday ? .semibold : .regular))
                .foregroundColor(cell.isToday ? palette.window : palette.textPrimary)
            Text(cell.lunarLabel)
                .font(.system(size: 9))
                .foregroundColor(cell.isToday ? palette.window.opacity(0.85) : palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, minHeight: 30)
        .padding(.vertical, 2)
        .background(cell.isToday ? palette.accent : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
