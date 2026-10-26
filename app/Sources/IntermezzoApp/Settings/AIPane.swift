import SwiftUI
import IntermezzoKit

/// The optional AI features: off by default. Here the user chooses where the model runs.
struct AIPane: View {
    @AppStorage(AIKeys.enabled) private var enabled = false
    @AppStorage(AIKeys.provider) private var providerRaw = AIProviderKind.apple.rawValue
    @AppStorage(AIKeys.endpoint) private var endpoint = ""
    @AppStorage(AIKeys.model) private var model = ""
    @AppStorage(AIKeys.noticeShown) private var noticeShown = false
    @ObservedObject private var service = AIService.shared
    @State private var apiKey = ""
    /// The key field was typed in. Only then is the Keychain written: a failed read must never erase a stored key.
    @State private var keyEdited = false
    @State private var models: [String] = []
    @State private var loadingModels = false
    @State private var modelsNote = ""
    @State private var modelsIsError = false
    @State private var showNotice = false
    @State private var testText = ""
    @State private var testIsError = false

    private var provider: AIProviderKind { AIProviderKind(rawValue: providerRaw) ?? .apple }

    var body: some View {
        Form {
            Section {
                Toggle("Włącz funkcje AI", isOn: Binding(
                    get: { enabled },
                    set: { on in
                        if on, !noticeShown { showNotice = true } else { enabled = on }
                        if !on { service.cancel() }
                    }))
                Text("Asystent ustawień, autor skryptów reguł i podsumowanie tygodnia. Funkcje działają tylko wtedy, gdy je klikniesz, a bez włączenia tego przełącznika program niczego nie wysyła.")
                    .settingsNote()
            }
            if enabled {
                providerSection
                Section {
                    Text("Do modelu trafia wyłącznie to, co jest potrzebne do klikniętej funkcji: Twój opis, lista ustawień z ich wartościami albo zbiorcze liczby o przerwach. Nigdy tytuły okien, nazwy sieci, projekty ani ścieżki. Odpowiedź modelu może być błędna, dlatego ustawienia i skrypty zawsze wymagają Twojego zatwierdzenia.")
                        .settingsNote()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { apiKey = KeychainStore.read(account: "openai") ?? "" }
        .onDisappear { commitKey() }
        .alert("Włączyć funkcje AI?", isPresented: $showNotice) {
            Button("Włącz") {
                noticeShown = true
                enabled = true
            }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Po kliknięciu funkcji AI program wyśle do wybranego przez Ciebie modelu Twój opis i potrzebne do niej dane o ustawieniach lub zbiorcze liczby o przerwach. Model systemowy Apple działa na tym Macu. Serwer, który wskażesz, może być na innym komputerze lub w internecie.")
        }
    }

    private var providerSection: some View {
        Section("Model") {
            Picker("Dostawca", selection: $providerRaw) {
                Text("Model systemowy Apple").tag(AIProviderKind.apple.rawValue)
                Text("Serwer zgodny z API OpenAI").tag(AIProviderKind.openai.rawValue)
            }
            switch provider {
            case .apple:
                LabeledContent("Stan") { Text(statusText).foregroundStyle(service.availability() == .ready ? Color.green : Color.secondary) }
                Text("Model wbudowany w macOS (Apple Intelligence). Działa na tym Macu, bez klucza i bez internetu. Wymaga macOS 26 lub nowszego. Jakość odpowiedzi po polsku może być słabsza niż po angielsku.")
                    .settingsNote()
            case .openai:
                TextField("Adres serwera", text: $endpoint, prompt: Text(verbatim: "http://localhost:1234/v1"))
                    .textFieldStyle(.editable)
                TextField("Nazwa modelu", text: $model, prompt: Text(verbatim: "llama3.1:8b"))
                    .textFieldStyle(.editable)
                modelRow
                SecureField("Klucz API (opcjonalny)", text: Binding(get: { apiKey }, set: { apiKey = $0; keyEdited = true }),
                            prompt: Text("wklej klucz, jeśli serwer go wymaga"))
                    .textFieldStyle(.plain)
                    .editableBox()
                    .onSubmit { commitKey() }
                Text(apiKey.isEmpty ? "Bez klucza (zwykle tak jest przy lokalnym serwerze)." : "Klucz jest zapisany w Pęku kluczy.")
                    .settingsNote()
                endpointNote
                HStack {
                    Button("Sprawdź połączenie") { testConnection() }
                        .disabled(service.isBusy)
                    if service.isBusy { Button("Przerwij") { service.cancel() } }
                }
                .controlSize(.small)
                if !testText.isEmpty {
                    Label(testText, systemImage: testIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(testIsError ? Color.orange : Color.green)
                        .font(.caption)
                }
                Text("Lokalny serwer (LM Studio, Ollama i podobne) lub dowolna usługa zgodna z API OpenAI. Klucz jest przechowywany w Pęku kluczy. Zwykły adres http:// jest dozwolony tylko dla serwera w tej sieci.")
                    .settingsNote()
            }
        }
    }

    /// Reads the model list from the server and lets the user pick one.
    @ViewBuilder private var modelRow: some View {
        HStack {
            Button { refreshModels() } label: {
                Label(loadingModels ? "Pobieram…" : "Odśwież listę modeli", systemImage: "arrow.clockwise")
            }
            .disabled(loadingModels || service.isBusy)
            .controlSize(.small)
            if !models.isEmpty {
                Picker("Dostępne modele", selection: $model) {
                    if !models.contains(model) { Text("— wybierz —").tag(model) }
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
        }
        if !modelsNote.isEmpty {
            Label(modelsNote, systemImage: modelsIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(modelsIsError ? Color.orange : Color.green)
                .font(.caption)
        }
    }

    private func refreshModels() {
        commitKey()
        modelsNote = ""
        loadingModels = true
        Task {
            defer { loadingModels = false }
            do {
                let found = try await service.listModels()
                models = found
                if found.isEmpty {
                    modelsNote = String(localized: "Serwer nie podał żadnych modeli.")
                    modelsIsError = true
                } else {
                    if model.trimmingCharacters(in: .whitespaces).isEmpty { model = found[0] }
                    modelsNote = String(localized: "Modele na serwerze: \(found.count)")
                    modelsIsError = false
                }
            } catch let error as AIError {
                modelsNote = error.message
                modelsIsError = true
            } catch {
                modelsNote = error.localizedDescription
                modelsIsError = true
            }
        }
    }

    @ViewBuilder private var endpointNote: some View {
        switch AIEndpoint.parse(endpoint) {
        case .success(let parsed) where parsed.locality == .remote:
            Label("Ten adres jest poza Twoją siecią: wysyłane dane opuszczą ten komputer.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        case .failure(let error) where !endpoint.trimmingCharacters(in: .whitespaces).isEmpty:
            Label(error.message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        default:
            EmptyView()
        }
    }

    private var statusText: String {
        switch service.availability() {
        case .ready: return String(localized: "gotowy")
        case .disabled: return String(localized: "wyłączony")
        case .unavailable(let reason): return reason
        }
    }

    private func commitKey() {
        guard keyEdited else { return }
        keyEdited = false
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { KeychainStore.delete(account: "openai") } else { KeychainStore.save(trimmed, account: "openai") }
    }

    private func testConnection() {
        commitKey()
        testText = ""
        Task {
            do {
                _ = try await service.run(AIRequest(system: "Reply with the single word OK.", user: "ping"))
                testText = String(localized: "Połączenie działa.")
                testIsError = false
            } catch let error as AIError {
                testText = error.message
                testIsError = true
            } catch {
                testText = error.localizedDescription
                testIsError = true
            }
        }
    }
}
