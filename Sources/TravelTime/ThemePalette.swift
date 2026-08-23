import SwiftUI

// MARK: - Theme palette

/// TravelTime's single visual token set.
struct ThemePalette {
    let window: Color          // panel background
    let surface: Color         // row / card surface
    let surfaceAlt: Color      // alternate row surface (midnight: dimmed row)
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let accent: Color
    let hairline: Color
    let rowRadius: CGFloat
    let headerTimeSize: CGFloat
    let quoteIsSerif: Bool
    let quoteHasMarks: Bool
    let useCards: Bool         // rows as cards (glass) vs flat rows
    let useAccentBars: Bool    // 4px accent bar on rows (minimal / midnight)
    let detectIsSolid: Bool    // solid accent detect button (glass)
    let panelRadius: CGFloat

    static let current = ThemePalette(window: Color(hex: "#F7F8F4"),
                                surface: Color(hex: "#FFFFFF"),
                                surfaceAlt: Color(hex: "#EAEFEA"),
                                textPrimary: Color(hex: "#171A18"),
                                textSecondary: Color(hex: "#687069"),
                                textTertiary: Color(hex: "#9AA09A"),
                                accent: Color(hex: "#27806A"),
                                hairline: Color(hex: "#DDE2DD"),
                                rowRadius: 12,
                                headerTimeSize: 40,
                                quoteIsSerif: true,
                                quoteHasMarks: false,
                                useCards: false,
                                useAccentBars: false,
                                detectIsSolid: false,
                                panelRadius: 16)
}
