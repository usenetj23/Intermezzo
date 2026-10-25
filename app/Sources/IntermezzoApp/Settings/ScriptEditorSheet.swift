import SwiftUI
import AppKit
import IntermezzoKit

/// What the editor opens: an existing script file, or a new one (no file yet).
struct ScriptEditorTarget: Identifiable {
    let id = UUID()
    /// nil = a new script; the file is created on save.
    let url: URL?
    /// Set for gallery scripts: the shipped source, offered as "restore".
    let gallery: GalleryScript?

    static func new() -> ScriptEditorTarget { ScriptEditorTarget(url: nil, gallery: nil) }
}

/// Edits a rule script: its settings ("nastawy") as form fields, and the AppleScript itself.
struct ScriptEditorSheet: View {
    let target: ScriptEditorTarget
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var source = ""
    @State private var settings: [ScriptSetting] = []
    @State private var templateID = ScriptGallery.templates[0].id
    @State private var resultText = ""
    @State private var resultIsError = false
    @State private var testing = false
    /// Bumped when the source is replaced as a whole, so the list fields reload their text.
    @State private var revision = 0

    private var isNew: Bool { target.url == nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            VSplitView {
                Form {
                    Section {
                        if isNew || target.gallery == nil {
                            TextField("Nazwa", text: $name)
                        } else if let gallery = target.gallery {
                            LabeledContent("Nazwa", value: L(gallery.title))
                        }
                        if isNew {
                            Picker("Szablon", selection: $templateID) {
                                ForEach(ScriptGallery.templates) { Text(localized: $0.title).tag($0.id) }
                            }
                            .onChange(of: templateID) { _, _ in loadTemplate() }
                        }
                    }
                    settingsSection
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 150, idealHeight: 260)
                codePane
                    .frame(minHeight: 200, maxHeight: .infinity)
            }
            Divider()
            buttons
                .padding(12)
        }
        .frame(minWidth: 620, idealWidth: 760, minHeight: 560, idealHeight: 700)
        .themedSheet()
        .onAppear(perform: load)
    }

    /// The code fills whatever height the sheet has; the divider above it can be dragged.
    private var codePane: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kod AppleScript").font(.headline)
            CodeEditor(text: Binding(get: { source }, set: { sourceEdited($0) }))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.12)))
            Text("Skrypt odpowiada na pytanie „czy warunek jest teraz spełniony?”: zwraca true albo false. Gdy zwróci true, reguła robi to, co ustawisz na stronie Reguły.")
                .settingsNote()
            if !resultText.isEmpty {
                Label(resultText, systemImage: resultIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(resultIsError ? .orange : .green)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var settingsSection: some View {
        Section("Nastawy") {
            if settings.isEmpty {
                Text(target.gallery.map { ScriptSettings.parse($0.source).isEmpty } == false
                     ? "Zainstalowana wersja jest starsza i nie ma nastaw. Kliknij „Przywróć wersję z galerii”."
                     : "Ten skrypt nie ma nastaw. Dodaj na początku kodu linię „property nazwa : wartość”, a pojawi się tutaj jako pole.")
                    .settingsNote()
            }
            ForEach(Array(settings.enumerated()), id: \.offset) { index, setting in
                settingRow(index: index, setting: setting)
            }
        }
    }

    @ViewBuilder
    private func settingRow(index: Int, setting: ScriptSetting) -> some View {
        let label = settingLabel(setting)
        switch setting.value {
        case .list(let items):
            ListSettingField(label: label, items: items) { update(index, .list($0)) }
                .id("\(revision)-\(setting.name)")
        case .number(let n):
            Stepper(value: Binding(get: { n }, set: { update(index, .number($0)) }), in: -100_000...100_000) {
                LabeledContent(label, value: String(n))
            }
        case .flag(let on):
            Toggle(label, isOn: Binding(get: { on }, set: { update(index, .flag($0)) }))
        case .text(let text):
            TextField(label, text: Binding(get: { text }, set: { update(index, .text($0)) }))
        }
    }

    private var buttons: some View {
        HStack {
            Button("Sprawdź") { _ = compile() }
            Button(testing ? "Trwa test…" : "Testuj teraz") { test() }
                .disabled(testing)
            if let gallery = target.gallery {
                Button("Przywróć wersję z galerii") { replaceSource(gallery.source) }
            }
            Spacer()
            Button("Anuluj", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(isNew ? "Utwórz" : "Zapisz") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(isNew && trimmedName.isEmpty)
        }
    }

    // MARK: - State

    private func settingLabel(_ s: ScriptSetting) -> String {
        if let label = ScriptGallery.settingLabels[s.name] { return L(label) }
        return s.comment ?? s.name
    }

    private func load() {
        if let url = target.url {
            replaceSource((try? String(contentsOf: url, encoding: .utf8)) ?? target.gallery?.source ?? "")
            name = ScriptSettings.ruleName(in: source) ?? url.deletingPathExtension().lastPathComponent
        } else {
            name = String(localized: "Mój skrypt")
            loadTemplate()
        }
    }

    private func loadTemplate() {
        guard let template = ScriptGallery.templates.first(where: { $0.id == templateID }) else { return }
        replaceSource(ScriptGallery.source(for: template, name: trimmedName))
    }

    private func replaceSource(_ text: String) {
        source = text
        settings = ScriptSettings.parse(text)
        revision += 1
        resultText = ""
    }

    private func sourceEdited(_ text: String) {
        source = text
        settings = ScriptSettings.parse(text)
        revision += 1
    }

    private func update(_ index: Int, _ value: ScriptSettingValue) {
        guard settings.indices.contains(index) else { return }
        settings[index].value = value
        source = ScriptSettings.apply(settings, to: source)
    }

    /// The source to save: the name goes into the header line of the user's own scripts.
    private var finalSource: String {
        guard target.gallery == nil, !trimmedName.isEmpty else { return source }
        return ScriptSettings.withRuleName(trimmedName, in: source)
    }

    // MARK: - Actions

    private func compile() -> Bool {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: finalSource) else {
            show(String(localized: "Nie udało się odczytać skryptu."), error: true)
            return false
        }
        if script.compileAndReturnError(&error) {
            show(String(localized: "Skrypt jest poprawny."), error: false)
            return true
        }
        let message = error?[NSAppleScript.errorMessage] as? String ?? ""
        show(String(localized: "Błąd w skrypcie: \(message)"), error: true)
        return false
    }

    private func test() {
        guard compile() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("intermezzo-test-\(UUID().uuidString).applescript")
        guard (try? finalSource.write(to: url, atomically: true, encoding: .utf8)) != nil else {
            show(String(localized: "Nie udało się zapisać pliku testowego."), error: true)
            return
        }
        testing = true
        Task {
            let result = await ScriptRunner.run(path: url.path, timeout: ScriptRunner.ruleTimeout)
            try? FileManager.default.removeItem(at: url)
            testing = false
            if result.status == ScriptRunner.failedStatus || result.status != 0 {
                show(String(localized: "Skrypt nie zadziałał (błąd uruchomienia, brak uprawnień albo przekroczony czas)."), error: true)
            } else if ScriptRuleResult.isHit(exitStatus: result.status, output: result.stdout) {
                show(String(localized: "Warunek jest teraz spełniony: reguła by zadziałała."), error: false)
            } else {
                show(String(localized: "Warunek nie jest teraz spełniony: reguła nic nie zrobi."), error: false)
            }
        }
    }

    private func save() {
        guard compile() else { return }
        let url = target.url ?? ScriptGallery.newScriptURL(named: trimmedName)
        guard ScriptGallery.write(finalSource, to: url) else {
            show(String(localized: "Zapis nie powiódł się."), error: true)
            return
        }
        if isNew { ScriptGallery.addRule(path: url.path, outcome: .postpone) }
        onSaved()
        dismiss()
    }

    private func show(_ text: String, error: Bool) {
        resultText = text
        resultIsError = error
    }
}

/// A list setting typed as comma-separated text; keeps its own text while typing.
private struct ListSettingField: View {
    let label: String
    let onChange: ([String]) -> Void
    @State private var text: String

    init(label: String, items: [String], onChange: @escaping ([String]) -> Void) {
        self.label = label
        self.onChange = onChange
        _text = State(initialValue: ScriptSettings.commaText(items))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
            TextField(label, text: $text)
                .textFieldStyle(.editable)
                .labelsHidden()
                .onChange(of: text) { _, new in onChange(ScriptSettings.list(fromCommaText: new)) }
            Text("Oddzielaj przecinkami.").settingsNote()
        }
    }
}
