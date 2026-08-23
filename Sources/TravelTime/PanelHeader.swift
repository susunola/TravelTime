import SwiftUI
import AppKit

// MARK: - Header: avatar · quote · time

struct HeaderView: View {
    @EnvironmentObject var store: TimeZoneStore
    let palette: ThemePalette

    /// The highlighted zone: prefer the uuid-tracked current row, fall back to
    /// a lookup by IANA id (covers the case where the current row was deleted
    /// and the pointer was sanitized to nil).
    private var current: ZoneEntry? {
        if let u = store.currentZoneUUID,
           let z = store.zones.first(where: { $0.uuid == u }) { return z }
        return store.zones.first { $0.id == store.currentZoneIdentifier }
    }

    private var accent: Color { palette.accent }

    private var dateText: String {
        // The date must be formatted in the DISPLAYED zone, not the host one —
        // otherwise the header can show 01:30 on a Monday with "Sunday"
        // beneath it for an hour either side of midnight.
        TimeZoneStore.cachedFormatter(
            format: "EEEE, MMM d",
            timeZone: TimeZone(identifier: store.currentZoneIdentifier)
        ).string(from: store.now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 14) {
                Text(store.timeString(for: store.currentZoneIdentifier))
                    .font(.system(size: 39, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .tracking(-1.2)
                    .foregroundColor(palette.textPrimary)
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 5) {
                        Circle().fill(palette.accent).frame(width: 7, height: 7)
                        Text(current?.label ?? "Current")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(palette.accent)
                    }
                    Text("UTC\(TimeZoneStore.offsetString(for: store.currentZoneIdentifier))")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(palette.textSecondary)
                }
            }
            HStack {
                Text(dateText)
                Spacer()
                let lunar = ChineseLunarCalendar.summary(for: store.now, calendar: displayedCalendar)
                Text("\(lunar.monthText)\(lunar.dayText)\(lunar.solarTerm.map { " · \($0)" } ?? "")")
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundColor(palette.textSecondary)

            HStack(spacing: 11) {
                AvatarView(palette: palette)
                QuoteView(palette: palette)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(palette.surface))
        }
    }

    private var displayedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: store.currentZoneIdentifier) ?? .current
        return calendar
    }

    // Editorial: avatar + label on top, big serif time, quote below
    private var editorialBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AvatarView(palette: palette)
                VStack(alignment: .leading, spacing: 2) {
                    Text(current?.label ?? "Current")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(palette.textPrimary)
                    Text(dateText)
                        .font(.system(size: 12))
                        .foregroundColor(palette.textSecondary)
                }
            }
            .padding(.bottom, 6)

            Text(store.timeString(for: store.currentZoneIdentifier))
                .font(.system(size: palette.headerTimeSize, weight: .medium, design: .serif))
                .monospacedDigit()
                .foregroundColor(palette.textPrimary)
            Text("UTC\(TimeZoneStore.offsetString(for: store.currentZoneIdentifier)) · \(current?.label ?? "Local")")
                .font(.system(size: 13))
                .foregroundColor(palette.textSecondary)
                .padding(.bottom, 6)

            QuoteView(palette: palette)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeStack: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accent)
                Text(current?.label ?? "Current")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(palette.textPrimary)
                if store.isDST(in: store.currentZoneIdentifier) {
                    Text("DST")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                }
            }
            Text(store.timeString(for: store.currentZoneIdentifier))
                .font(.system(size: palette.headerTimeSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(palette.textPrimary)
            Text("\(dateText)  ·  UTC\(TimeZoneStore.offsetString(for: store.currentZoneIdentifier))")
                .font(.system(size: 11))
                .foregroundColor(palette.textSecondary)
        }
    }
}

// MARK: - Quote of the hour

struct QuoteView: View {
    @EnvironmentObject var store: TimeZoneStore
    let palette: ThemePalette

    private static let quotes: [String] = [
        "Time is the most fair — everyone gets twenty-four hours a day.",
        "An inch of time is an inch of gold, but gold cannot buy time.",
        "Time flows like a river — it never stops, day or night.",
        "Life passes like a white colt glimpsed through a crack.",
        "Time is like water in a sponge — squeeze and there is always more.",
        "Live each day as if it were your last.",
        "No prime years come twice, no morning repeats itself.",
        "Don't wait idly, lamenting the grey in your youth.",
        "Nothing is as fast and as slow, as long and as short, as common and as precious as time.",
        "You never step into the same river twice — new water always flows past you.",
        "Time has no present, eternity has no future or past.",
        "Yesterday cannot be recalled; today holds its own worries."
    ]

    private var quote: String {
        // Rotate by the hour of the DISPLAYED zone, not the host system zone —
        // "morning" quotes should match what the panel is actually showing.
        let hour = TimeZoneStore.hourOfDay(in: store.currentZoneIdentifier, at: store.now)
        return Self.quotes[hour % Self.quotes.count]
    }

    var body: some View {
        let text = palette.quoteHasMarks ? "「\(quote)」" : quote
        Text(text)
            .font(.system(size: palette.quoteHasMarks ? 13 : 11.5,
                          weight: .regular,
                          design: palette.quoteIsSerif ? .serif : .default))
            .italic()
            .foregroundColor(palette.textSecondary)
            .multilineTextAlignment(palette.quoteHasMarks ? .center : .leading)
            .lineLimit(4)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.opacity)
            .id(quote)
    }
}

// MARK: - Avatar

struct AvatarView: View {
    @EnvironmentObject var store: TimeZoneStore
    let palette: ThemePalette

    private var isDay: Bool { store.isDaytime(in: store.currentZoneIdentifier) }

    /// Cached in the store — never re-decoded from disk on every redraw.
    private var nsImage: NSImage? { store.avatarImage }

    var body: some View {
        Button {
            store.chooseAvatar()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 54, height: 54)
                if let img = nsImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1.5))
                } else {
                    Image(systemName: isDay ? "sun.max.fill" : "moon.stars.fill")
                        .font(.system(size: 20))
                        .foregroundColor(isDay ? Color.orange : Color.indigo)
                }
                // Bottom corners: day/night indicator (left) + camera hint (right).
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: isDay ? "sun.max.fill" : "moon.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Circle().fill(isDay ? Color.orange : Color.indigo))
                        Spacer()
                        Image(systemName: "camera.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(3)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                    }
                }
                .frame(width: 54, height: 54)
            }
        }
        .buttonStyle(.plain)
        .help("Click to choose a photo")
    }
}
