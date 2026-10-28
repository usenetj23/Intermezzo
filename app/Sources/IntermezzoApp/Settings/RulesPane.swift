import SwiftUI
import SwiftData
import AppKit
import Carbon.HIToolbox
import ServiceManagement
import CoreLocation
import UserNotifications
import IOKit.hidsystem
import IntermezzoKit

struct RulesPane: View {
    @State private var rules: [BreakRule] = []
    private let store = BreakRuleStore()

    var body: some View {
        Form {
            Section {
                ForEach($rules) { $rule in
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: $rule.enabled) {
                            Text(localized: rule.kind.label).fontWeight(.medium)
                        }
                        if rule.kind.needsText {
                            TextField(rule.kind == .script
                                    ? "ścieżka skryptu (.applescript)"
                                    : "nazwa aplikacji / tekst",
                                    text: $rule.text)
                                .textFieldStyle(.editable)
                        }
                        HStack {
                            Toggle("isn't (odwrócone)", isOn: $rule.inverted)
                            Spacer()
                            Picker("", selection: $rule.outcome) {
                                ForEach(BreakRuleOutcome.allCases) { outcome in
                                    Text(localized: outcome.label).tag(outcome)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 230)
                            if rule.outcome == .postpone {
                                Stepper("\(rule.postponeMinutes) min",
                                      value: $rule.postponeMinutes, in: 1...60)
                            }
                            if rule.outcome == .suggestBreak {
                                Stepper("trwa ≥ \(rule.sustainSeconds) s",
                                        value: $rule.sustainSeconds, in: 10...900, step: 10)
                                    .help("Warunek musi być prawdziwy tak długo, zanim zaproponuję przerwę")
                                Stepper("co \(rule.cooldownMinutes) min",
                                        value: $rule.cooldownMinutes, in: 5...240, step: 5)
                                    .help("Najczęstsze odstępy między propozycjami z tej reguły")
                            }
                            Button(role: .destructive) {
                                rules.removeAll { $0.id == rule.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 2)
                }
                HStack {
                    Menu("Dodaj regułę…") {
                        ForEach(BreakRuleKind.allCases) { kind in
                            Button(L(kind.label)) {
                                var newRule = BreakRule()
                                newRule.kind = kind
                                rules.append(newRule)
                            }
                        }
                    }
                    Spacer()
                }
            } header: {
                Text("Gdy warunek jest spełniony w momencie nadejścia przerwy — zostanie odroczona lub pominięta")
            }
            Text("Przykład: reguła „Aplikacja z przodu = Keynote” z opcją „Automatycznie pomiń” pomija przerwy podczas prezentacji. „Odrocz” sprawdza warunek ponownie przy każdej próbie wystartowania przerwy, aż przestanie pasować.")
                .settingsNote().settingsAnchor("rules-przyklad-regula-aplikacja-z-przodu-k")
        }
        .formStyle(.grouped)
        .onAppear { rules = store.load() }
        .onChange(of: rules) { _, new in store.save(new) }
    }
}

// MARK: - Minute-accurate time picker (e.g. 6:30 → 14:30 working hours)
