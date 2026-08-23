import SwiftUI

struct ZoneCandidate: Identifiable {
    let id: String
    let label: String
    let region: String
}

struct AddZoneRow: View {
    @EnvironmentObject private var store: TimeZoneStore
    let palette: ThemePalette
    @State private var showPicker = false
    @State private var query = ""

    private static let allCandidates: [ZoneCandidate] = {
        var seen = Set(SettingsView.commonZones.map(\.id))
        var result = SettingsView.commonZones.map { ZoneCandidate(id: $0.id, label: $0.label, region: $0.region) }
        for id in TimeZone.knownTimeZoneIdentifiers where !seen.contains(id) {
            let parts = id.split(separator: "/")
            let label = (parts.last.map(String.init) ?? id).replacingOccurrences(of: "_", with: " ")
            result.append(ZoneCandidate(id: id, label: label,
                                        region: parts.dropLast().last.map(String.init) ?? ""))
            seen.insert(id)
        }
        return result
    }()

    var body: some View {
        Button { showPicker.toggle() } label: {
            Label("Add city", systemImage: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(palette.textSecondary)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPicker, arrowEdge: .top) {
            ZonePickerPopover(candidates: Self.allCandidates,
                              existingIDs: Set(store.zones.map(\.id)),
                              query: $query) { item in
                store.zones.append(ZoneEntry(id: item.id, label: item.label,
                                             region: item.region, color: store.nextZoneColor()))
                showPicker = false
            }
        }
    }
}

struct ZonePickerPopover: View {
    let candidates: [ZoneCandidate]
    let existingIDs: Set<String>
    @Binding var query: String
    let onAdd: (ZoneCandidate) -> Void

    private var filtered: [ZoneCandidate] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return candidates.filter {
            guard !existingIDs.contains($0.id) else { return false }
            return needle.isEmpty || $0.id.lowercased().contains(needle)
                || $0.label.lowercased().contains(needle) || $0.region.lowercased().contains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search cities or time zones", text: $query)
                .textFieldStyle(.roundedBorder).padding(10)
            Divider()
            if filtered.isEmpty {
                ContentUnavailableView("No matching city", systemImage: "globe")
                    .frame(width: 320, height: 260)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { item in
                            Button { onAdd(item) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.label).font(.system(size: 12.5, weight: .medium))
                                        Text(item.id).font(.system(size: 9.5)).foregroundColor(.secondary)
                                    }
                                    Spacer(); Image(systemName: "plus.circle").foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 7).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider().padding(.leading, 12)
                        }
                    }
                }.frame(width: 320, height: 300)
            }
        }.frame(width: 320)
    }
}
