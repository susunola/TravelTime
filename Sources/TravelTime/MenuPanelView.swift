import SwiftUI

// MARK: - Main panel

struct MenuPanelView: View {
    @EnvironmentObject var store: TimeZoneStore

    private var palette: ThemePalette { ThemePalette.palette(for: store.theme) }

    var body: some View {
        VStack(spacing: 0) {
            // Calendar card on top; the time/avatar header moves to the bottom.
            if store.showCalendar {
                CalendarCardView(palette: palette)
                    .padding(.horizontal, 12)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
            }

            DividerView(palette: palette)
                .padding(.horizontal, 12)

            ZoneListView(palette: palette)
                .frame(maxHeight: .infinity)

            DividerView(palette: palette)
                .padding(.horizontal, 12)

            HeaderView(palette: palette)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

            DividerView(palette: palette)
                .padding(.horizontal, 12)

            FooterView(palette: palette)
                .padding(12)
        }
        .frame(minWidth: 320, minHeight: 420, maxHeight: .infinity)
        .background(palette.window)
    }
}

// MARK: - Legacy menu bar label (kept for potential status item reuse)

struct MenuBarLabel: View {
    @EnvironmentObject var store: TimeZoneStore

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .medium))
            Text(store.menuBarText)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }
}

// MARK: - Color helper

extension Color {
    /// Parses "#RRGGBB", "RRGGBB", 3-digit shorthand and 8-digit "#RRGGBBAA".
    /// Invalid input falls back to a neutral gray instead of silently black.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let expanded: String
        switch s.count {
        case 3: expanded = s.map { "\($0)\($0)" }.joined()
        case 6, 8: expanded = s
        default:
            self.init(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1)
            return
        }
        var value: UInt64 = 0
        guard Scanner(string: expanded).scanHexInt64(&value) else {
            self.init(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1)
            return
        }
        if s.count == 8 {
            // #RRGGBBAA — alpha lives in the low byte.
            let r = Double((value >> 24) & 0xFF) / 255.0
            let g = Double((value >> 16) & 0xFF) / 255.0
            let b = Double((value >> 8) & 0xFF) / 255.0
            let a = Double(value & 0xFF) / 255.0
            self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
        } else {
            let r = Double((value >> 16) & 0xFF) / 255.0
            let g = Double((value >> 8) & 0xFF) / 255.0
            let b = Double(value & 0xFF) / 255.0
            self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
        }
    }
}
