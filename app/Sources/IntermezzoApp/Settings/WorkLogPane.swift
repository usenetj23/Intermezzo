import AppKit
import IntermezzoKit
import SwiftUI

/// Work-time register: presence in the work zone per day, office and remote, with overtime
/// against the working hours and hand corrections.
struct WorkLogPane: View {
    @AppStorage(WorkLogKeys.enabled) private var enabled = 0
    @AppStorage(WorkLogKeys.wifiNames) private var wifiNames = ""
    @AppStorage(WorkLogKeys.vpnNames) private var vpnNames = ""
    @AppStorage(WorkLogKeys.scanInRange) private var scanInRange = 0
    @AppStorage(WorkLogKeys.networkMarks) private var marksData = Data()
    @AppStorage(Keys.workStartMinutes) private var workStart = 8 * 60
    @AppStorage(Keys.workEndMinutes) private var workEnd = 18 * 60
    @ObservedObject private var log = WorkLogController.shared
    @ObservedObject private var detector = WorkDetector.shared
    @Environment(\.surfaceTheme) private var theme
    /// First day of the month on screen.
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())!.start
    @State private var editing: EditedDay?
    /// Day opened from the calendar or the table (its log, with a way into the editor).
    @State private var viewing: EditedDay?
    @State private var tableExpanded = false
    @State private var newDay = Date()
    @State private var pickingNewDay = false

    struct EditedDay: Identifiable {
        let day: Date
        var id: Date { day }
    }

    private var monthEnd: Date { Calendar.current.date(byAdding: .month, value: 1, to: month)! }
    private var days: [WorkDaySummary] {
        _ = log.revision
        return log.days(from: month, to: monthEnd)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Prowadź rejestr czasu pracy", isOn: Binding(get: { enabled != 0 }, set: { enabled = $0 ? 1 : 0 }))
                Text("Czas pracy to obecność w strefie pracy: od pierwszej do ostatniej aktywności przy komputerze. Sieć firmowa = biuro, VPN do pracy poza siecią firmową = praca zdalna. Odejścia do 30 min (narada, hala) nie przerywają pracy. Wszystko poza godzinami pracy (\(Self.clock(workStart))–\(Self.clock(workEnd)), ustawienia w Ogólne) to nadgodziny, rozliczane w pełnych kwadransach.")
                    .settingsNote()
            }
            if enabled != 0 {
                zoneSection
                todaySection
                monthSection
            }
        }
        .formStyle(.grouped)
        .scrollsToSettingsAnchor()
        .onChange(of: wifiNames) { _, _ in log.settingsChanged() }
        .onChange(of: vpnNames) { _, _ in log.settingsChanged() }
        .onChange(of: scanInRange) { _, _ in log.settingsChanged() }
        .onChange(of: marksData) { _, _ in log.settingsChanged() }
        .sheet(item: $editing) { WorkDayEditor(day: $0.day).themedSheet() }
        .sheet(item: $viewing) { WorkDayLog(day: $0.day).themedSheet() }
    }

    // MARK: Sections

    private var zoneSection: some View {
        Section("Strefa pracy") {
            TextField("Sieci Wi-Fi w pracy (po przecinku)", text: $wifiNames, prompt: Text("np. Firma, Firma-5G"))
            if !log.zone.currentSSID.isEmpty,
               !WorkZoneProbe.list(wifiNames).contains(log.zone.currentSSID.lowercased()) {
                Button("Dodaj bieżącą sieć: \(log.zone.currentSSID)") {
                    wifiNames = (WorkZoneProbe.list(wifiNames) + [log.zone.currentSSID]).joined(separator: ", ")
                }
                .controlSize(.small)
            }
            Toggle("Licz także sieć w zasięgu, bez połączenia (skan co 5 min)",
                   isOn: Binding(get: { scanInRange != 0 }, set: { scanInRange = $0 ? 1 : 0 }))
            if (scanInRange != 0 || !wifiNames.isEmpty) && !detector.locationAuthorized {
                HStack {
                    Text("macOS podaje nazwy sieci Wi-Fi tylko aplikacjom z dostępem do lokalizacji.")
                        .font(.caption).foregroundStyle(.orange)
                    Button("Zezwól") { WorkDetector.shared.requestLocationAuthorization() }
                        .controlSize(.small)
                }
            }
            TextField("VPN do pracy zdalnej (po przecinku, fragment nazwy)", text: $vpnNames, prompt: Text("np. Biuro"))
            if !log.zone.connectedVPNs.isEmpty {
                Text("Połączone VPN: \(log.zone.connectedVPNs.joined(separator: ", "))")
                    .settingsNote()
            }
            wiredRows
            LabeledContent("Teraz") {
                Label(log.zone.inZone ? log.zone.reason : String(localized: "poza strefą pracy"),
                      systemImage: Self.symbol(log.zone.place))
                    .foregroundStyle(log.zone.inZone ? .green : .secondary)
            }
        }
    }

    private var marks: [WorkNetworkMark] { WorkNetworkMark.decode(marksData) }

    /// Wired part of the work zone, in the same section as Wi-Fi and VPN so "Teraz" covers all of it.
    @ViewBuilder
    private var wiredRows: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sieć przewodowa (LAN, stacja dokująca)")
                .id("lan")
            Text("Sieć LAN jest rozpoznawana po tym, co podaje jej serwer DHCP (router, domena, DNS), niezależnie od karty. Kartę lub stację zapamiętaj tylko, jeśli nie używasz jej poza pracą.")
                .settingsNote()
        }
        if log.zone.wiredLinks.isEmpty {
            Text("Brak aktywnego połączenia przewodowego.").foregroundStyle(.secondary)
        }
        ForEach(log.zone.wiredLinks, id: \.device) { link in
            VStack(alignment: .leading, spacing: 6) {
                Label("\(link.name) (\(link.device))", systemImage: "cable.connector")
                    .font(.callout.weight(.medium))
                Text(Self.describe(link.lease))
                    .settingsNote()
                if !link.lease.isStrong {
                    Text("Stały adres bez DHCP: rozpoznanie tylko po routerze i masce, wiele sieci może wyglądać tak samo.")
                        .font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    markButton(.lan, value: link.lease.fingerprint,
                               label: link.lease.domain.isEmpty ? "LAN \(link.lease.router)" : link.lease.domain,
                               title: "To jest sieć w pracy")
                    markButton(.adapter, value: link.mac, label: link.name,
                               title: "Ta karta / stacja jest tylko w pracy")
                }
                .controlSize(.small)
            }
            .padding(.vertical, 2)
        }
        ForEach(marks, id: \.self) { mark in
            HStack {
                Image(systemName: mark.kind == .lan ? "network" : "dock.rectangle")
                Text(mark.label)
                Text(mark.kind == .lan ? "sieć LAN" : "karta / stacja")
                    .settingsNote()
                Spacer()
                Button(role: .destructive) {
                    marksData = WorkNetworkMark.encode(marks.filter { $0 != mark })
                } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Zapomnij")
            }
        }
    }

    @ViewBuilder
    private func markButton(_ kind: WorkNetworkMark.Kind, value: String, label: String, title: String) -> some View {
        if marks.contains(where: { $0.kind == kind && $0.value == value }) {
            Label("zapamiętane", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
        } else {
            Button(LocalizedStringKey(title)) {
                marksData = WorkNetworkMark.encode(marks + [WorkNetworkMark(kind: kind, value: value, label: label)])
            }
        }
    }

    private static func describe(_ lease: WiredNetwork.Lease) -> String {
        let router = lease.router.isEmpty ? "?" : lease.router
        var parts = [String(localized: "router \(router)")]
        if !lease.domain.isEmpty { parts.append(String(localized: "domena \(lease.domain)")) }
        if !lease.dns.isEmpty { parts.append("DNS \(lease.dns.joined(separator: ", "))") }
        return parts.joined(separator: " · ")
    }

    private var todaySection: some View {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let today = log.days(from: start, to: cal.date(byAdding: .day, value: 1, to: start)!).first
        return Section("Dziś") {
            if let today {
                LabeledContent("Od – do", value: "\(Self.time(today.first)) – \(Self.time(today.last))")
                LabeledContent("Praca", value: Self.split(today.office, today.remote))
                LabeledContent("Nadgodziny", value: Self.split(today.officeOvertime, today.remoteOvertime))
                LabeledContent("Aktywnie przy komputerze", value: WorkLog.hm(today.active))
            } else {
                Text("Dziś nie zarejestrowano jeszcze pracy w strefie.")
                    .foregroundStyle(.secondary)
            }
            Button("Popraw dzisiejszy dzień…") { editing = EditedDay(day: start) }
                .controlSize(.small)
        }
    }

    private var monthSection: some View {
        let list = days
        return Section {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Text(month, format: .dateTime.month(.wide).year())
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(monthEnd > Date())
            }
            .buttonStyle(.borderless)
            HStack(spacing: 18) {
                total("Praca", list.reduce(0) { $0 + $1.worked })
                total("w tym zdalnie", list.reduce(0) { $0 + $1.remote })
                total("Nadgodziny do rozliczenia", list.reduce(0) { $0 + $1.billableOvertime }, accent: true)
                total("w tym zdalne", list.reduce(0) { $0 + $1.billableRemoteOvertime }, accent: true)
                total("Dni", nil, count: list.count)
            }
            WorkCalendar(month: month, days: list, schedule: WorkLogController.schedule()) {
                viewing = EditedDay(day: $0)
            }
            if !list.isEmpty {
                DisclosureGroup("Tabela dni", isExpanded: $tableExpanded) { table(list) }
            }
            Text("Kliknij dzień w kalendarzu, aby zobaczyć jego log i go poprawić. Nadgodziny = praca poza godzinami pracy, w dni wolne cała praca; rozliczane w dół do pełnych 15 min, za każdy dzień osobno dla biura i pracy zdalnej. ✎ = korekta ręczna.")
                .settingsNote()
            HStack {
                Button("Dodaj dzień ręcznie…") { newDay = Date(); pickingNewDay = true }
                    .popover(isPresented: $pickingNewDay) {
                        VStack(alignment: .leading, spacing: 10) {
                            DatePicker("Dzień", selection: $newDay, in: ...Date(), displayedComponents: .date)
                                .datePickerStyle(.graphical)
                            Button("Dalej") {
                                pickingNewDay = false
                                editing = EditedDay(day: Calendar.current.startOfDay(for: newDay))
                            }
                            .keyboardShortcut(.defaultAction)
                        }
                        .padding(14)
                    }
                Spacer()
                Button("Eksportuj miesiąc do CSV…") { exportCSV(list) }
                    .disabled(list.isEmpty)
            }
        } header: {
            Text("Rejestr")
        }
    }

    private func table(_ list: [WorkDaySummary]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                ForEach(["Dzień", "Od – do", "Biuro", "Zdalnie", "Nadg. biuro", "Nadg. zdalne", "Aktywnie", ""], id: \.self) {
                    Text(LocalizedStringKey($0)).settingsNote()
                }
            }
            ForEach(list.reversed(), id: \.day) { d in
                GridRow {
                    Text(d.day, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .foregroundStyle(d.isWorkday ? .primary : .secondary)
                    Text("\(Self.time(d.first)) – \(Self.time(d.last))")
                    Text(d.office >= 60 ? WorkLog.hm(d.office) : "–")
                    Text(d.remote >= 60 ? WorkLog.hm(d.remote) : "–")
                    overtimeCell(raw: d.officeOvertime, billable: d.billableOfficeOvertime)
                    overtimeCell(raw: d.remoteOvertime, billable: d.billableRemoteOvertime)
                    Text(WorkLog.hm(d.active)).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        if d.hasCorrections { Image(systemName: "pencil").foregroundStyle(.orange) }
                        if !d.notes.isEmpty {
                            Image(systemName: "note.text").foregroundStyle(.secondary).help(d.notes.joined(separator: "\n"))
                        }
                    }
                }
                .font(.callout)
                .monospacedDigit()
                .contentShape(Rectangle())
                .onTapGesture { viewing = EditedDay(day: d.day) }
            }
        }
    }

    /// Billable overtime, with the exact minutes on hover.
    private func overtimeCell(raw: TimeInterval, billable: TimeInterval) -> some View {
        Text(billable > 0 ? WorkLog.hm(billable) : (raw >= 60 ? "(\(WorkLog.hm(raw)))" : "–"))
            .foregroundStyle(billable > 0 ? Color.orange : .secondary)
            .fontWeight(billable > 0 ? .semibold : .regular)
            .help(raw >= 60 ? String(localized: "Dokładnie \(WorkLog.hm(raw)), do rozliczenia \(WorkLog.hm(billable))") : "")
    }

    // MARK: Helpers

    private func total(_ title: String, _ seconds: TimeInterval?, count: Int = 0, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(title)).settingsNote()
            Text(seconds.map(WorkLog.hm) ?? "\(count)")
                .font(.title3.weight(.semibold)).monospacedDigit()
                .foregroundStyle(accent ? theme.accent : .primary)
        }
    }

    private func shiftMonth(_ by: Int) {
        month = Calendar.current.date(byAdding: .month, value: by, to: month)!
    }

    private func exportCSV(_ list: [WorkDaySummary]) {
        let panel = NSSavePanel()
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        panel.nameFieldStringValue = "rejestr-pracy-\(f.string(from: month)).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try WorkLog.csv(list, calendar: .current).write(to: url, atomically: true, encoding: .utf8)
            Trace.log("work log exported to \(url.path)")
        } catch {
            Trace.log("work log export failed: \(error.localizedDescription)")
        }
    }

    private static func symbol(_ place: WorkPlace?) -> String {
        switch place {
        case .office: "building.2.fill"
        case .remote: "house.fill"
        case nil: "circle"
        }
    }

    /// "8:00" or "6:00 + 2:00 zdalnie".
    private static func split(_ office: TimeInterval, _ remote: TimeInterval) -> String {
        guard remote >= 60 else { return WorkLog.hm(office) }
        guard office >= 60 else { return String(localized: "\(WorkLog.hm(remote)) zdalnie") }
        return String(localized: "\(WorkLog.hm(office)) + \(WorkLog.hm(remote)) zdalnie")
    }

    private static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private static func clock(_ minutes: Int) -> String {
        "\(minutes / 60):" + String(format: "%02d", minutes % 60)
    }
}
