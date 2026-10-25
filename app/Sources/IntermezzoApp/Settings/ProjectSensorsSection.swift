import SwiftUI
import IntermezzoKit

/// Focus ▸ "Project sensors": at the start of a session, one small script reads
/// a line of text and — if one of your rules matches — suggests a project.
/// Off by default. Nothing leaves the Mac; the text is never stored or logged.
struct ProjectSensorsSection: View {
    @AppStorage(ProjectSensorKeys.enabled) private var enabled = false
    @AppStorage(ProjectSensorKeys.script) private var scriptPath = ""
    @ObservedObject private var pomodoro = PomodoroController.shared
    @ObservedObject private var permissions = PermissionCenter.shared
    @State private var rules: [ProjectSensorRule] = ProjectSensors.rules()
    @State private var installed: Set<String> = []
    @State private var testOutput: String?
    @State private var testing = false

    var body: some View {
        Section("Project sensors") {
            Toggle("Suggest a project at session start", isOn: $enabled)
            if enabled {
                ForEach(ProjectSensorCatalog.all) { script in sensorRow(script) }
                permissionRow(.automation, needs: "All sensors (System Events; Terminal/iTerm or Finder for two of them).")
                permissionRow(.accessibility, needs: "Front window: document name.")
                rulesEditor
                HStack {
                    Button(testing ? "Running…" : "Test sensor") { test() }
                        .disabled(testing || selectedScript == nil)
                    Spacer()
                }
                if let testOutput {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(testOutput)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                        Text("Raw output of the sensor — untrusted text, shown only here.")
                            .settingsNote()
                    }
                }
            }
            Text("Runs once when a session starts, only if the current task has no project. You always confirm with “Use”. Nothing leaves your Mac and the text is never stored.")
                .settingsNote()
        }
        .onAppear { refresh() }
    }

    private var selectedScript: GalleryScript? {
        ProjectSensorCatalog.all.first { ProjectSensors.path(for: $0).path == scriptPath && installed.contains($0.id) }
    }

    private func refresh() {
        installed = Set(ProjectSensorCatalog.all.filter(ProjectSensors.isInstalled).map(\.id))
        rules = ProjectSensors.rules()
        permissions.refresh()
    }

    private func sensorRow(_ script: GalleryScript) -> some View {
        let isInstalled = installed.contains(script.id)
        let isSelected = scriptPath == ProjectSensors.path(for: script).path && isInstalled
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(localized: script.title)
                Text(localized: script.summary).settingsNote()
            }
            Spacer()
            if isInstalled {
                Button(isSelected ? "Selected" : "Select") { scriptPath = ProjectSensors.path(for: script).path }
                    .disabled(isSelected)
                Button("Uninstall") { ProjectSensors.uninstall(script); refresh() }
            } else {
                Button("Install") {
                    if ProjectSensors.install(script) {
                        scriptPath = ProjectSensors.path(for: script).path
                        refresh()
                    }
                }
            }
        }
    }

    private func permissionRow(_ kind: PermissionKind, needs: LocalizedStringKey) -> some View {
        HStack {
            Image(systemName: permissions.status(kind) == .granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(permissions.status(kind) == .granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(localized: kind.title)
                Text(needs).settingsNote()
            }
        }
    }

    private var rulesEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Rules — first match wins").font(.headline)
            ForEach($rules) { $rule in
                HStack {
                    TextField("contains…", text: $rule.pattern)
                    Image(systemName: "arrow.right")
                    Picker("", selection: $rule.project) {
                        Text("Choose…").tag("")
                        ForEach(pomodoro.projects) { Text($0.name).tag($0.name) }
                        if !rule.project.isEmpty && !pomodoro.projects.contains(where: { $0.name == rule.project }) {
                            Text("\(rule.project) (unavailable)").tag(rule.project)
                        }
                    }
                    .labelsHidden()
                    Button { rules.removeAll { $0.id == rule.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            Button("Add rule") { rules.append(ProjectSensorRule(pattern: "", project: "")) }
        }
        .onChange(of: rules) { _, new in ProjectSensors.save(rules: new) }
    }

    private func test() {
        testing = true
        Task { @MainActor in
            switch await ProjectSensors.runSelected() {
            case .notRun: testOutput = String(localized: "Not run: the selected sensor is missing or invalid, or one is already running.")
            case .failed: testOutput = String(localized: "The sensor failed or took longer than \(Int(ScriptRunner.sensorTimeout)) s and was stopped.")
            case .ran(let raw):
                let shown = ProjectSensors.displayText(raw)
                testOutput = shown.isEmpty ? String(localized: "The sensor ran and printed nothing.") : shown
            }
            testing = false
        }
    }
}
