import Foundation
import Combine

// MARK: - Event data model

/// A single imported calendar source (one .ics file).
struct ImportedEvent: Identifiable, Codable {
    let id: UUID
    let fileName: String
    var events: [CalendarEvent]

    init(id: UUID = UUID(), fileName: String, events: [CalendarEvent]) {
        self.id = id
        self.fileName = fileName
        self.events = events
    }
}

/// A VEVENT parsed from an ICS file. May carry a recurrence rule.
struct CalendarEvent: Identifiable, Codable, Hashable {
    var id: String { uid }
    let uid: String
    var summary: String
    var location: String
    var notes: String
    var isAllDay: Bool
    var start: Date
    var end: Date
    var rrule: RecurrenceRule?
}

/// A concrete occurrence after RRULE expansion — what the UI actually shows.
struct EventOccurrence: Identifiable {
    let id = UUID()
    let start: Date
    let end: Date
    let summary: String
    let location: String
    let sourceName: String
    let isAllDay: Bool
}

// MARK: - Recurrence rule

/// RFC 5545 RRULE, the subset this app understands.
struct RecurrenceRule: Codable, Hashable {
    enum Frequency: String, Codable {
        case daily = "DAILY"
        case weekly = "WEEKLY"
        case monthly = "MONTHLY"
        case yearly = "YEARLY"
    }

    /// A weekday with an optional signed ordinal (e.g. +1MO, -1SA).
    struct WeekdayOrdinal: Codable, Hashable {
        var weekday: Int   // 1=Sunday .. 7=Saturday (matches Calendar.weekday)
        var ordinal: Int?  // nil = plain weekday, +1 first, -1 last
    }

    var frequency: Frequency
    var interval: Int = 1
    var count: Int?
    var until: Date?
    var byDay: [WeekdayOrdinal]?
    var byMonth: [Int]?
}

// MARK: - ICS importer

/// Parses RFC 5545 ICS text into `CalendarEvent` values.
enum ICSImporter {
    /// Maps RFC 5545 BYDAY two-letter codes to Calendar.weekday (1..7).
    private static let bydayMap: [String: Int] = [
        "SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7
    ]

    /// Parse a full ICS document string into calendar events.
    static func parse(_ text: String) -> [CalendarEvent] {
        let lines = unfoldLines(text)
        var stack: [String] = []
        var current: [String: (params: [String: String], value: String)] = [:]
        var events: [CalendarEvent] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("BEGIN:") {
                let name = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                stack.append(name)
                if name == "VEVENT" { current = [:] }
            } else if trimmed.hasPrefix("END:") {
                let name = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                if name == "VEVENT", let ev = buildEvent(current) {
                    events.append(ev)
                }
                if !stack.isEmpty { stack.removeLast() }
            } else if stack.last == "VEVENT", let prop = parseProperty(trimmed) {
                current[prop.key] = (prop.params, prop.value)
            }
        }
        return events
    }

    // MARK: line unfolding

    /// RFC 5545 line folding: a continuation line that begins with a space or
    /// tab is appended to the preceding logical line (the CRLF + WSP removed).
    private static func unfoldLines(_ text: String) -> [String] {
        let raw = text.replacingOccurrences(of: "\r\n", with: "\n")
                        .replacingOccurrences(of: "\r", with: "\n")
        let parts = raw.components(separatedBy: "\n")
        var out: [String] = []
        for part in parts {
            if part.hasPrefix(" ") || part.hasPrefix("\t") {
                if let last = out.indices.last {
                    out[last] = out[last] + String(part.dropFirst())
                }
            } else {
                out.append(part)
            }
        }
        return out
    }

    // MARK: property parsing

    /// Splits `NAME;PARAM=V;PARAM=V:VALUE` into key / params / value.
    private static func parseProperty(_ line: String) -> (key: String, params: [String: String], value: String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let left = String(line[..<colon])
        let value = String(line[line.index(after: colon)...])

        let leftParts = left.components(separatedBy: ";")
        let key = leftParts[0].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var params: [String: String] = [:]
        for p in leftParts.dropFirst() {
            let kv = p.components(separatedBy: "=")
            if kv.count == 2 {
                params[kv[0].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()] =
                    kv[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return (key, params, value)
    }

    // MARK: event assembly

    private static func buildEvent(_ props: [String: (params: [String: String], value: String)]) -> CalendarEvent? {
        guard let uid = props["UID"]?.value, !uid.isEmpty else { return nil }

        let dtstart = props["DTSTART"]
        let dtend = props["DTEND"]
        let isAllDay = dtstart?.params["VALUE"] == "DATE"

        guard let start = parseDate(dtstart?.value ?? "", tzid: dtstart?.params["TZID"], allDay: isAllDay) else {
            return nil
        }
        let end: Date
        if let rawEnd = dtend?.value, let parsed = parseDate(rawEnd, tzid: dtend?.params["TZID"], allDay: isAllDay) {
            end = parsed
        } else {
            // DTEND omitted: timed defaults to +1h, all-day to +1 day.
            end = isAllDay
                ? start.addingTimeInterval(86400)
                : start.addingTimeInterval(3600)
        }

        let rrule = props["RRULE"].flatMap { parseRRule($0.value) }

        return CalendarEvent(
            uid: uid,
            summary: unescape(props["SUMMARY"]?.value ?? ""),
            location: unescape(props["LOCATION"]?.value ?? ""),
            notes: unescape(props["DESCRIPTION"]?.value ?? ""),
            isAllDay: isAllDay,
            start: start,
            end: end,
            rrule: rrule
        )
    }

    // MARK: date parsing

    /// Parse an ICS date/datetime value into an absolute Date.
    /// - all-day (`VALUE=DATE`) → midnight UTC of that date.
    /// - trailing `Z` → UTC.
    /// - `TZID` param → interpreted in that timezone.
    /// - otherwise (floating) → interpreted in the system timezone.
    private static func parseDate(_ value: String, tzid: String?, allDay: Bool) -> Date? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return nil }

        if allDay {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyyMMdd"
            fmt.timeZone = TimeZone(identifier: "UTC")
            return fmt.date(from: v)
        }

        let tz: TimeZone
        var val = v
        if let tzid = tzid, let t = TimeZone(identifier: tzid) {
            tz = t
        } else if v.hasSuffix("Z") {
            tz = TimeZone(identifier: "UTC")!
            val = String(v.dropLast())   // strip the trailing 'Z'
        } else {
            tz = TimeZone.current
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd'T'HHmmss"
        fmt.timeZone = tz
        return fmt.date(from: val)
    }

    // MARK: RRULE parsing

    private static func parseRRule(_ value: String) -> RecurrenceRule? {
        var rule = RecurrenceRule(frequency: .daily)
        let parts = value.components(separatedBy: ";")
        for part in parts {
            let kv = part.components(separatedBy: "=")
            guard kv.count == 2 else { continue }
            let key = kv[0].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let val = kv[1].trimmingCharacters(in: .whitespacesAndNewlines)
            switch key {
            case "FREQ":
                if let f = RecurrenceRule.Frequency(rawValue: val) { rule.frequency = f }
            case "INTERVAL":
                rule.interval = Int(val) ?? 1
            case "COUNT":
                rule.count = Int(val)
            case "UNTIL":
                // UNTIL is always UTC (ends with Z in practice).
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
                fmt.timeZone = TimeZone(identifier: "UTC")
                rule.until = fmt.date(from: val) ?? parseDate(val, tzid: nil, allDay: false)
            case "BYDAY":
                rule.byDay = val.components(separatedBy: ",").compactMap { parseWeekdayOrdinal($0) }
            case "BYMONTH":
                rule.byMonth = val.components(separatedBy: ",").compactMap { Int($0) }
            default:
                break
            }
        }
        return rule
    }

    /// Parse a BYDAY token such as `MO`, `+1MO`, `-1SA`.
    private static func parseWeekdayOrdinal(_ token: String) -> RecurrenceRule.WeekdayOrdinal? {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2 else { return nil }
        let code = String(t.suffix(2)).uppercased()
        guard let weekday = bydayMap[code] else { return nil }
        let prefix = String(t.dropLast(2))
        var ordinal: Int?
        if !prefix.isEmpty {
            ordinal = Int(prefix)
        }
        return RecurrenceRule.WeekdayOrdinal(weekday: weekday, ordinal: ordinal)
    }

    // MARK: text unescaping

    /// Unescape ICS text: \\, → ,   \\; → ;   \\n / \n → newline   \\\\ → \
    private static func unescape(_ value: String) -> String {
        var result = value
        result = result.replacingOccurrences(of: "\\n", with: "\n")
        result = result.replacingOccurrences(of: "\\N", with: "\n")
        result = result.replacingOccurrences(of: "\\,", with: ",")
        result = result.replacingOccurrences(of: "\\;", with: ";")
        result = result.replacingOccurrences(of: "\\\\", with: "\\")
        return result
    }
}

// MARK: - RRULE expansion

/// Expands a `CalendarEvent`'s recurrence into concrete occurrence start dates
/// within a query window. All date arithmetic uses the supplied `calendar`
/// (a Gregorian anchored to the displayed timezone) so weekdays and months
/// line up with what the user sees.
enum RRULEExpander {
    /// Returns occurrence start Dates for `event` that fall in `[from, to)`.
    static func occurrenceStarts(event: CalendarEvent, from: Date, to: Date, calendar: Calendar) -> [Date] {
        guard let rule = event.rrule else {
            return (event.start >= from && event.start < to) ? [event.start] : []
        }

        var results: [Date] = []
        var produced = 0
        let limit = 5000

        switch rule.frequency {
        case .daily:
            var cursor = event.start
            var n = 0
            while n < limit {
                n += 1
                if let until = rule.until, cursor > until { break }
                if cursor >= from && cursor < to {
                    results.append(cursor)
                    produced += 1
                    if let c = rule.count, produced >= c { break }
                }
                guard let next = calendar.date(byAdding: .day, value: rule.interval, to: cursor) else { break }
                cursor = next
            }

        case .weekly:
            let byDays = (rule.byDay ?? [RecurrenceRule.WeekdayOrdinal(weekday: calendar.component(.weekday, from: event.start), ordinal: nil)])
                .sorted { $0.weekday < $1.weekday }
            var weekAnchor = startOfWeek(event.start, calendar: calendar)
            var n = 0
            while n < limit {
                n += 1
                for bd in byDays {
                    let raw = dateOfWeekday(bd.weekday, inWeekContaining: weekAnchor, calendar: calendar)
                    let d = withTimeOfDay(event.start, on: raw, calendar: calendar)
                    if d < event.start { continue }
                    if let until = rule.until, d > until { continue }
                    if d >= from && d < to {
                        results.append(d)
                        produced += 1
                        if let c = rule.count, produced >= c { return results }
                    }
                }
                if let c = rule.count, produced >= c { break }
                guard let nextAnchor = calendar.date(byAdding: .weekOfYear, value: rule.interval, to: weekAnchor) else { break }
                weekAnchor = nextAnchor
                if weekAnchor > to { break }
            }

        case .monthly:
            guard var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: event.start)) else { break }
            var n = 0
            while n < limit {
                n += 1
                let comps = calendar.dateComponents([.year, .month], from: cursor)
                if let raw = monthlyOccurrence(year: comps.year ?? 1, month: comps.month ?? 1, rule: rule, event: event, calendar: calendar) {
                    let occ = withTimeOfDay(event.start, on: raw, calendar: calendar)
                    if let until = rule.until, occ > until { break }
                    if occ >= from && occ < to {
                        results.append(occ)
                        produced += 1
                        if let c = rule.count, produced >= c { break }
                    }
                }
                guard let next = calendar.date(byAdding: .month, value: rule.interval, to: cursor) else { break }
                cursor = next
            }

        case .yearly:
            guard var cursor = calendar.date(from: calendar.dateComponents([.year], from: event.start)) else { break }
            var n = 0
            while n < limit {
                n += 1
                let year = calendar.component(.year, from: cursor)
                let months = rule.byMonth ?? [calendar.component(.month, from: event.start)]
                for m in months {
                    if let raw = yearlyOccurrence(year: year, month: m, rule: rule, event: event, calendar: calendar) {
                        let occ = withTimeOfDay(event.start, on: raw, calendar: calendar)
                        if let until = rule.until, occ > until { continue }
                        if occ >= from && occ < to {
                            results.append(occ)
                            produced += 1
                            if let c = rule.count, produced >= c { return results }
                        }
                    }
                }
                guard let next = calendar.date(byAdding: .year, value: rule.interval, to: cursor) else { break }
                cursor = next
            }
        }

        return results
    }

    /// Returns `day` (a midnight date) with `reference`'s time-of-day preserved,
    /// so a timed event recurs at the same hour/minute it was first defined.
    private static func withTimeOfDay(_ reference: Date, on day: Date, calendar: Calendar) -> Date {
        var comps = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: reference)
        comps.year = calendar.component(.year, from: day)
        comps.month = calendar.component(.month, from: day)
        comps.day = calendar.component(.day, from: day)
        return calendar.date(from: comps) ?? day
    }

    // MARK: helpers

    /// The start of the week (Sunday, since calendar.firstWeekday = 1) that
    /// contains `date`.
    private static func startOfWeek(_ date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: comps) ?? date
    }

    /// The date of `weekday` (1..7) within the week containing `anchor`.
    private static func dateOfWeekday(_ weekday: Int, inWeekContaining anchor: Date, calendar: Calendar) -> Date {
        let start = startOfWeek(anchor, calendar: calendar)
        let wd = calendar.component(.weekday, from: start)
        let diff = weekday - wd
        return calendar.date(byAdding: .day, value: diff, to: start) ?? start
    }

    /// The `ordinal`-th `weekday` of a given month (1=first, -1=last).
    private static func nthWeekday(weekday: Int, ordinal: Int, year: Int, month: Int, calendar: Calendar) -> Date? {
        var comps = DateComponents(year: year, month: month, day: 1)
        guard let first = calendar.date(from: comps) else { return nil }
        let firstWD = calendar.component(.weekday, from: first)
        let firstOcc = ((weekday - firstWD) % 7 + 7) % 7 + 1
        let dayNum: Int
        if ordinal > 0 {
            dayNum = firstOcc + (ordinal - 1) * 7
        } else {
            guard let range = calendar.range(of: .day, in: .month, for: first) else { return nil }
            let daysInMonth = range.count
            let k = (daysInMonth - firstOcc) / 7
            let lastOcc = firstOcc + 7 * k
            dayNum = lastOcc + 7 * (ordinal + 1)
        }
        guard dayNum >= 1,
              let range = calendar.range(of: .day, in: .month, for: first),
              dayNum <= range.count else { return nil }
        comps.day = dayNum
        return calendar.date(from: comps)
    }

    private static func monthlyOccurrence(year: Int, month: Int, rule: RecurrenceRule, event: CalendarEvent, calendar: Calendar) -> Date? {
        if let byDay = rule.byDay {
            // Use the first BYDAY rule (most ICS use a single one).
            let bd = byDay[0]
            return nthWeekday(weekday: bd.weekday, ordinal: bd.ordinal ?? 1, year: year, month: month, calendar: calendar)
        }
        let startDay = calendar.component(.day, from: event.start)
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        guard let range = calendar.range(of: .day, in: .month, for: first) else { return nil }
        let day = range.contains(startDay) ? startDay : min(startDay, range.count)
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func yearlyOccurrence(year: Int, month: Int, rule: RecurrenceRule, event: CalendarEvent, calendar: Calendar) -> Date? {
        if let byDay = rule.byDay, let bd = byDay.first {
            return nthWeekday(weekday: bd.weekday, ordinal: bd.ordinal ?? 1, year: year, month: month, calendar: calendar)
        }
        let startDay = calendar.component(.day, from: event.start)
        return calendar.date(from: DateComponents(year: year, month: month, day: startDay))
    }
}

// MARK: - Event store

/// Owns the imported ICS sources, persists them to disk, and answers queries
/// about which days have events and what happens on a given day.
final class EventStore: ObservableObject {
    static let shared = EventStore()

    @Published private(set) var sources: [ImportedEvent] = []

    /// When false, the store does not read or write the on-disk cache. Used by
    /// unit tests so they never mutate Application Support.
    private let persistent: Bool

    init(persistent: Bool = true) {
        self.persistent = persistent
        if persistent { load() }
    }

    // MARK: persistence

    private static func eventsFileURL() -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dir = support.appendingPathComponent("TravelTime", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("events.json")
    }

    private func load() {
        guard let url = Self.eventsFileURL(),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ImportedEvent].self, from: data) else { return }
        sources = decoded
    }

    private func save() {
        guard persistent else { return }
        guard let url = Self.eventsFileURL() else { return }
        do {
            let data = try JSONEncoder().encode(sources)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("EventStore save failed: \(error.localizedDescription)")
        }
    }

    // MARK: mutations

    /// Parse ICS text and append it as a new source.
    @discardableResult
    func importICS(_ text: String, fileName: String) -> Int {
        let events = ICSImporter.parse(text)
        guard !events.isEmpty else { return 0 }
        let source = ImportedEvent(fileName: fileName, events: events)
        sources.append(source)
        save()
        return events.count
    }

    func removeSource(id: UUID) {
        sources.removeAll { $0.id == id }
        save()
    }

    // MARK: queries

    /// All occurrences that start within `[from, to)`.
    func occurrences(from: Date, to: Date, calendar: Calendar) -> [EventOccurrence] {
        var result: [EventOccurrence] = []
        for source in sources {
            for ev in source.events {
                let starts = RRULEExpander.occurrenceStarts(event: ev, from: from, to: to, calendar: calendar)
                let durationDays = max(1, Int(round(ev.end.timeIntervalSince(ev.start) / 86400)))
                for s in starts {
                    for d in 0..<durationDays {
                        guard let occStart = calendar.date(byAdding: .day, value: d, to: s),
                              let occEnd = calendar.date(byAdding: .day, value: d, to: ev.end) else { continue }
                        if occStart >= from && occStart < to {
                            result.append(EventOccurrence(
                                start: occStart, end: occEnd,
                                summary: ev.summary, location: ev.location,
                                sourceName: source.fileName, isAllDay: ev.isAllDay
                            ))
                        }
                    }
                }
            }
        }
        result.sort { $0.start < $1.start }
        return result
    }

    /// Occurrences that fall on a specific day.
    func occurrences(on day: Date, calendar: Calendar) -> [EventOccurrence] {
        let startOfDay = calendar.startOfDay(for: day)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }
        return occurrences(from: startOfDay, to: nextDay, calendar: calendar)
    }

    /// The set of day-of-month numbers in `month` that have at least one event.
    func daysWithEvents(in month: Date, calendar: Calendar) -> Set<Int> {
        let comps = calendar.dateComponents([.year, .month], from: month)
        guard let first = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: first),
              let lastDay = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: range.count)),
              let monthEnd = calendar.date(byAdding: .day, value: 1, to: lastDay) else { return [] }
        let occ = occurrences(from: first, to: monthEnd, calendar: calendar)
        var days: Set<Int> = []
        for o in occ {
            days.insert(calendar.component(.day, from: o.start))
        }
        return days
    }
}
