import SwiftUI
import AppKit
import IntermezzoKit

/// Projects of the Pomodoro plan: colour, client, hourly rate, currency,
/// billable flag and archive. Names are unique, ignoring case.
struct PomodoroProjectsSection: View {
    @ObservedObject private var pomodoro = PomodoroController.shared

    private var all: [PomodoroProject] {
        pomodoro.ledger.projects.sorted {
            if $0.archived != $1.archived { return !$0.archived }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        Section("Projects") {
            if all.isEmpty {
                Text("Projects appear here when you create one in the plan above (Project → New project…).")
                    .settingsNote().settingsAnchor("focus-projects-appear-here-when-you-create")
            }
            ForEach(all) { project in
                PomodoroProjectRow(project: project)
            }
            Text("Billable projects with an hourly rate add up money per currency from the real time of finished pomodoros. Everything stays on this Mac.")
                .settingsNote().settingsAnchor("focus-billable-projects-with-an-hourly-rat")
        }
    }
}

private struct PomodoroProjectRow: View {
    let project: PomodoroProject
    @ObservedObject private var pomodoro = PomodoroController.shared
    @State private var nameDraft: String
    @State private var rateDraft: String
    @State private var nameRefused = false

    private static let currencies = ["PLN", "EUR", "USD", "GBP", "CHF"]

    init(project: PomodoroProject) {
        self.project = project
        _nameDraft = State(initialValue: project.name)
        _rateDraft = State(initialValue: project.hourlyRate.map { Self.rateText($0) } ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(color.wrappedValue).frame(width: 10, height: 10)
                TextField("Name", text: $nameDraft)
                    .textFieldStyle(.editable)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.red, lineWidth: nameRefused ? 1.5 : 0))
                    .onSubmit(commitName)
                ColorPicker("Colour", selection: color, supportsOpacity: false).labelsHidden()
                Button(project.archived ? "Restore" : "Archive") { edit { $0.archived.toggle() } }
                    .controlSize(.small)
            }
            if nameRefused {
                Text("Name already used").font(.caption).foregroundStyle(.red)
            }
            HStack(spacing: 8) {
                TextField("Client", text: Binding(get: { project.client }, set: { v in edit { $0.client = v } }))
                    .textFieldStyle(.editable)
                TextField("Rate / h", text: $rateDraft)
                    .textFieldStyle(.editable)
                    .frame(width: 80)
                    .onSubmit(commitRate)
                    .onChange(of: rateDraft) { _, _ in commitRate() }
                Picker("Currency", selection: Binding(get: { project.currency }, set: { v in edit { $0.currency = v } })) {
                    ForEach(Self.currencies, id: \.self) { Text($0).tag($0) }
                }.settingsAnchor("focus-currency")
                .labelsHidden().frame(width: 72)
                Toggle("Billable", isOn: Binding(get: { project.billable }, set: { v in edit { $0.billable = v } })).settingsAnchor("focus-billable")
                    .toggleStyle(.checkbox)
            }
        }
        .opacity(project.archived ? 0.55 : 1)
        .padding(.vertical, 2)
    }

    private var color: Binding<Color> {
        Binding(
            get: {
                let c = ColorHex.components(project.colorHex) ?? ColorHex.components(PomodoroProject.defaultColorHex)!
                return Color(.sRGB, red: c.r, green: c.g, blue: c.b)
            },
            set: { new in
                guard let ns = NSColor(new).usingColorSpace(.sRGB) else { return }
                let hex = ColorHex.string(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent))
                edit { $0.colorHex = hex }
            })
    }

    /// Applies a change to the latest stored copy of the project.
    private func edit(_ change: (inout PomodoroProject) -> Void) {
        var p = pomodoro.ledger.projects.first { $0.id == project.id } ?? project
        change(&p)
        pomodoro.upsertProject(p)
    }

    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == project.name { nameRefused = false; nameDraft = trimmed; return }
        if pomodoro.renameProject(id: project.id, to: trimmed) {
            nameRefused = false
        } else {
            nameRefused = true
        }
    }

    private func commitRate() {
        let text = rateDraft.trimmingCharacters(in: .whitespaces)
        let value: Double? = text.isEmpty ? nil : PomodoroProject.parseRate(text)
        if !text.isEmpty && value == nil { return }   // invalid: keep the stored rate
        if value != project.hourlyRate { edit { $0.hourlyRate = value } }
    }

    private static func rateText(_ rate: Double) -> String {
        rate == rate.rounded() ? String(Int(rate)) : String(rate)
    }
}
