import SwiftUI
import AppKit

struct MenuPanelView: View {
    @EnvironmentObject private var store: TimeZoneStore
    @State private var section: PanelSection = .worldClocks
    @State private var selectedZoneUUID: UUID?
    private var palette: ThemePalette { .current }
    private var selectedZone: ZoneEntry? { store.zones.first { $0.uuid == selectedZoneUUID } }

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(palette: palette)
                .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 16)
            SectionTabs(selection: $section, palette: palette).padding(.horizontal, 22)
            Group {
                switch section {
                case .worldClocks: clockList
                case .calendar:
                    ScrollView(.vertical, showsIndicators: false) {
                        CalendarCardView(palette: palette)
                            .padding(.horizontal, 22)
                            .padding(.top, 14)
                            .padding(.bottom, 22)
                    }
                case .planner:
                    ScrollView(.vertical, showsIndicators: false) {
                        MeetingPlannerView(palette: palette)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 14)
                    }
                }
            }.frame(maxHeight: .infinity)
            CompactFooter(palette: palette)
                .padding(.horizontal, 22).padding(.vertical, 12)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(2)
        }
        .frame(minWidth: 420, idealWidth: 460, maxWidth: 520, minHeight: 560)
        .background(palette.window)
        .ignoresSafeArea(.container, edges: .top)
        // Full-size content extends under the title bar. Reserve exactly the
        // traffic-light height without recreating the former oversized gap.
        .padding(.top, 16)
        .onAppear { selectedZoneUUID = store.currentZoneUUID }
        .onChange(of: section) { _, value in
            store.isCalendarSectionActive = value == .calendar
        }
        .onChange(of: store.currentZoneUUID) { _, value in selectedZoneUUID = value }
    }

    private var clockList: some View {
        VStack(spacing: 10) {
            // Remains scrollable on unusually short displays, but without a
            // visible track for an ordinary five-zone list.
            ScrollView(.vertical, showsIndicators: false) { clockRows }
            if let zone = selectedZone, zone.uuid != store.currentZoneUUID {
                Button { store.switchTo(zone) } label: {
                    Label("Switch to \(zone.label)", systemImage: "arrow.triangle.swap")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(Capsule().fill(palette.accent))
                }.buttonStyle(.plain).disabled(store.isSwitching)
            }
        }.padding(.horizontal, 22).animation(.easeOut(duration: 0.18), value: selectedZoneUUID)
    }

    private var clockRows: some View {
        LazyVStack(spacing: 6) {
            ForEach(store.zones, id: \.uuid) { zone in
                ModernZoneRow(zone: zone, palette: palette,
                              isSelected: selectedZoneUUID == zone.uuid,
                              onSelect: { selectedZoneUUID = zone.uuid })
            }
            AddZoneRow(palette: palette).padding(.top, 2)
        }
        .padding(.vertical, 12)
    }
}

private enum PanelSection: CaseIterable, Identifiable {
    case worldClocks, calendar, planner
    var id: Self { self }
    var title: String { switch self { case .worldClocks: return "World clocks"; case .calendar: return "Calendar"; case .planner: return "Meeting planner" } }
    var icon: String { switch self { case .worldClocks: return "globe.asia.australia.fill"; case .calendar: return "calendar"; case .planner: return "clock.arrow.2.circlepath" } }
}

private struct SectionTabs: View {
    @Binding var selection: PanelSection
    let palette: ThemePalette
    var body: some View {
        HStack(spacing: 4) {
            ForEach(PanelSection.allCases) { item in
                Button { selection = item } label: {
                    Label(item.title, systemImage: item.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(selection == item ? palette.accent : palette.textSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 9).fill(selection == item ? palette.surface : Color.clear)
                            .shadow(color: selection == item ? Color.black.opacity(0.06) : .clear, radius: 5, y: 2))
                }.buttonStyle(.plain)
            }
        }.padding(4).background(RoundedRectangle(cornerRadius: 12).fill(palette.surfaceAlt))
    }
}

private struct ModernZoneRow: View {
    @EnvironmentObject private var store: TimeZoneStore
    let zone: ZoneEntry; let palette: ThemePalette; let isSelected: Bool; let onSelect: () -> Void
    @State private var hovered = false
    private var isCurrent: Bool { zone.uuid == store.currentZoneUUID }
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(isCurrent ? palette.accent : palette.surfaceAlt)
                        .frame(width: 34, height: 34)
                    Image(systemName: isCurrent ? "location.fill" : "clock")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isCurrent ? .white : palette.textSecondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(zone.region.isEmpty ? zone.label : "\(zone.label) · \(zone.region)")
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .medium)).foregroundColor(palette.textPrimary).lineLimit(1)
                    Text(zone.id).font(.system(size: 10.5)).foregroundColor(palette.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 5) {
                        if isCurrent { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundColor(palette.accent) }
                        Text(store.timeString(for: zone)).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                    }.foregroundColor(palette.textPrimary)
                    Text("\(TimeZoneStore.dayLabel(for: store.dayDifference(for: zone))) · UTC\(TimeZoneStore.offsetString(for: zone.id))")
                        .font(.system(size: 9.5, weight: .medium)).foregroundColor(palette.textTertiary)
                }
            }.padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 12).fill(isCurrent ? palette.accent.opacity(0.09) : (isSelected || hovered ? palette.surface : Color.clear)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected && !isCurrent ? palette.hairline : .clear))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }
        .contextMenu {
            if !isCurrent { Button("Switch to \(zone.label)") { store.switchTo(zone) } }
            Button("Remove \(zone.label)", role: .destructive) { store.zones.removeAll { $0.uuid == zone.uuid } }.disabled(isCurrent)
        }
    }
}

private struct CompactFooter: View {
    @EnvironmentObject private var store: TimeZoneStore
    let palette: ThemePalette
    var body: some View {
        VStack(spacing: 9) {
            if let detected = store.detected {
                HStack(spacing: 7) {
                    Image(systemName: "location.fill").foregroundColor(palette.accent)
                    Text(detected.city.isEmpty ? detected.timezone : "\(detected.city) · \(detected.timezone)").lineLimit(1)
                    Spacer(); Button("Use") { store.confirmDetectedZone() }.buttonStyle(.plain).foregroundColor(palette.accent).fontWeight(.semibold)
                }.font(.system(size: 10.5)).padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9).fill(palette.accent.opacity(0.08)))
            }
            HStack(spacing: 18) {
                footerButton(store.isDetecting ? "Detecting…" : "Detect location", icon: "location") { store.detectLocation() }.disabled(store.isDetecting)
                Spacer(); footerButton("Settings", icon: "gearshape") { store.openSettings() }
                footerButton("Quit", icon: "power") { NSApplication.shared.terminate(nil) }
            }.padding(.top, 10).overlay(alignment: .top) { Rectangle().fill(palette.hairline).frame(height: 1) }
            if let error = store.lastError { Text(error).font(.system(size: 9.5)).foregroundColor(.red).lineLimit(2) }
        }
    }
    private func footerButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon).font(.system(size: 10.5, weight: .medium)).foregroundColor(palette.textSecondary) }.buttonStyle(.plain)
    }
}

private struct MeetingPlannerView: View {
    @EnvironmentObject var store: TimeZoneStore
    let palette: ThemePalette
    @State private var hourOffset = 0.0
    private var plannedDate: Date { store.now.addingTimeInterval(hourOffset * 3600) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { VStack(alignment: .leading, spacing: 2) { Text("Find a meeting time").font(.system(size: 14, weight: .semibold)); Text(hourOffset == 0 ? "Now" : relativeLabel).font(.system(size: 10)).foregroundColor(palette.textSecondary) }; Spacer(); Button("Now") { hourOffset = 0 }.buttonStyle(.plain).foregroundColor(palette.accent) }
            Slider(value: $hourOffset, in: -12...36, step: 1).tint(palette.accent)
            ForEach(store.zones, id: \.uuid) { zone in
                HStack { VStack(alignment: .leading, spacing: 2) { Text(zone.label).font(.system(size: 12, weight: .medium)); Text(isWorkingHour(zone.id) ? "Working hours" : "Outside working hours").font(.system(size: 9.5)).foregroundColor(isWorkingHour(zone.id) ? palette.accent : palette.textTertiary) }; Spacer(); Text(time(in: zone.id)).font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit() }.padding(.vertical, 4)
            }
        }.padding(14).background(RoundedRectangle(cornerRadius: 14).fill(palette.surface))
    }
    private var relativeLabel: String { let f = DateFormatter(); f.dateFormat = "EEE, MMM d · HH:mm"; f.timeZone = TimeZone(identifier: store.currentZoneIdentifier); return f.string(from: plannedDate) }
    private func time(in id: String) -> String { let f = DateFormatter(); f.dateFormat = store.use24Hour ? "HH:mm" : "h:mm a"; f.timeZone = TimeZone(identifier: id); return f.string(from: plannedDate) }
    private func isWorkingHour(_ id: String) -> Bool { var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: id) ?? .current; return (9..<18).contains(cal.component(.hour, from: plannedDate)) }
}

struct MenuBarLabel: View {
    @EnvironmentObject var store: TimeZoneStore
    var body: some View { HStack(spacing: 5) { Image(systemName: "clock"); Text(store.menuBarText).monospaced() }.font(.system(size: 12, weight: .medium)) }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces); if s.hasPrefix("#") { s.removeFirst() }
        let expanded = s.count == 3 ? s.map { "\($0)\($0)" }.joined() : s
        guard [6, 8].contains(expanded.count), let value = UInt64(expanded, radix: 16) else { self.init(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1); return }
        let a = expanded.count == 8
        self.init(.sRGB, red: Double((value >> (a ? 24 : 16)) & 255) / 255, green: Double((value >> (a ? 16 : 8)) & 255) / 255, blue: Double((value >> (a ? 8 : 0)) & 255) / 255, opacity: a ? Double(value & 255) / 255 : 1)
    }
}
