import SwiftUI

// MARK: - Calendar card (阳历 + 农历 + ICS events)

/// A compact month calendar shown in the panel: a header with the viewed day's
/// solar date, weekday, the Chinese lunar date (干支年 / 月 / 日) and any solar
/// term, a month-navigable 7-column mini-grid, event dot-markers on days that
/// have imported ICS events, and — when a day is tapped — the list of that
/// day's events below the grid. Dropping an `.ics` file onto the card imports it.
struct CalendarCardView: View {
    @EnvironmentObject var store: TimeZoneStore
    @EnvironmentObject var eventStore: EventStore
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

    /// The month currently displayed (navigation state).
    @State private var referenceDate: Date = Date()
    /// The day whose details and events are shown (tap to change).
    @State private var viewedDate: Date = Date()

    private var referenceComps: DateComponents {
        calendar.dateComponents([.year, .month], from: referenceDate)
    }

    private var viewedSummary: ChineseLunarCalendar.Summary {
        ChineseLunarCalendar.summary(for: viewedDate, calendar: calendar)
    }

    private var monthTitle: String {
        "\(referenceComps.year ?? 0)年\(referenceComps.month ?? 0)月"
    }

    private var viewedSolarText: String {
        let weekday = calendar.component(.weekday, from: viewedDate)
        let w = Self.weekdayNames[(weekday - 1 + 7) % 7]
        let parts = calendar.dateComponents([.month, .day], from: viewedDate)
        return "\(parts.month ?? 0)月\(parts.day ?? 0)日 周\(w)"
    }

    private var todayComps: DateComponents {
        calendar.dateComponents([.year, .month, .day], from: store.now)
    }

    private var markedDays: Set<Int> {
        eventStore.daysWithEvents(in: referenceDate, calendar: calendar)
    }

    private var viewedEvents: [EventOccurrence] {
        eventStore.occurrences(on: viewedDate, calendar: calendar)
    }

    private struct Cell {
        let day: Int
        let lunarLabel: String
        let isToday: Bool
    }

    /// Leading blanks (before day 1) + one cell per day of the month, padded to
    /// a full week so the grid always aligns to 7 columns.
    private var cells: [Cell?] {
        let year = referenceComps.year ?? 1
        let month = referenceComps.month ?? 1
        guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)   // 1..7

        var result: [Cell?] = []
        for _ in 1..<firstWeekday { result.append(nil) }
        for day in range {
            let date = calendar.date(from: DateComponents(year: year, month: month, day: day))!
            let ld = ChineseLunarCalendar.lunarDate(for: date, calendar: calendar)
            let lunarLabel = ld.day == 1
                ? ChineseLunarCalendar.monthName(ld.month, isLeap: ld.isLeap)
                : ChineseLunarCalendar.dayName(ld.day)
            let isToday = todayComps.year == year && todayComps.month == month && todayComps.day == day
            result.append(Cell(day: day, lunarLabel: lunarLabel, isToday: isToday))
        }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: solar date + lunar date + solar term (viewed day)
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewedSolarText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(palette.textPrimary)
                    Text("\(viewedSummary.ganZhiYear)年 \(viewedSummary.monthText)\(viewedSummary.dayText)")
                        .font(.system(size: 13))
                        .foregroundColor(palette.textSecondary)
                    if let term = viewedSummary.solarTerm {
                        Text(term)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(palette.accent)
                    }
                }
                Spacer(minLength: 0)
                // Month navigation
                HStack(spacing: 4) {
                    Button(action: stepPrevMonth) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                    Text(monthTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(palette.textTertiary)
                    Button(action: stepNextMonth) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
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

            // Events for the viewed day
            if store.showEvents {
                Divider().background(palette.hairline)
                if viewedEvents.isEmpty {
                    Text("暂无安排")
                        .font(.system(size: 11))
                        .foregroundColor(palette.textTertiary)
                        .padding(.vertical, 2)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(viewedEvents) { o in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(palette.accent)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 5)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(o.summary.isEmpty ? "(无标题)" : o.summary)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(palette.textPrimary)
                                    if !o.location.isEmpty {
                                        Text(o.location)
                                            .font(.system(size: 11))
                                            .foregroundColor(palette.textSecondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers -> Bool in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url, url.pathExtension.lowercased() == "ics",
                      let text = try? String(contentsOf: url, encoding: .utf8) else { return }
                let count = eventStore.importICS(text, fileName: url.lastPathComponent)
                if count > 0 {
                    DispatchQueue.main.async {
                        store.onEventsChanged()
                    }
                }
            }
            return true
        }
    }

    private func dayCell(_ cell: Cell) -> some View {
        let isViewed = calendar.component(.year, from: viewedDate) == referenceComps.year
            && calendar.component(.month, from: viewedDate) == referenceComps.month
            && calendar.component(.day, from: viewedDate) == cell.day
        let hasEvent = store.showEvents && markedDays.contains(cell.day)

        return Button(action: { selectDay(cell.day) }) {
            VStack(spacing: 1) {
                ZStack {
                    if cell.isToday {
                        Circle()
                            .fill(palette.accent)
                            .frame(width: 22, height: 22)
                    } else if isViewed {
                        Circle()
                            .stroke(palette.accent, lineWidth: 1)
                            .frame(width: 22, height: 22)
                    }
                    Text("\(cell.day)")
                        .font(.system(size: 12, weight: (cell.isToday || isViewed) ? .semibold : .regular))
                        .foregroundColor(cell.isToday ? palette.window
                                         : (isViewed ? palette.accent : palette.textPrimary))
                }
                .frame(height: 18)
                Text(cell.lunarLabel)
                    .font(.system(size: 9))
                    .foregroundColor(cell.isToday ? palette.window.opacity(0.85) : palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if hasEvent {
                    Circle()
                        .fill(palette.accent)
                        .frame(width: 4, height: 4)
                } else {
                    Color.clear.frame(width: 4, height: 4)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func selectDay(_ day: Int) {
        guard let date = calendar.date(from: DateComponents(year: referenceComps.year,
                                                            month: referenceComps.month,
                                                            day: day)) else { return }
        viewedDate = date
        store.onEventsChanged()
    }

    private func stepPrevMonth() {
        guard let next = calendar.date(byAdding: .month, value: -1, to: referenceDate) else { return }
        referenceDate = next
    }

    private func stepNextMonth() {
        guard let next = calendar.date(byAdding: .month, value: 1, to: referenceDate) else { return }
        referenceDate = next
    }
}
