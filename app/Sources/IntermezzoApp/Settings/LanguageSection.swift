import SwiftUI
import IntermezzoKit

/// Interface language. The labels are fixed bilingual text so the picker stays readable in either language.
struct LanguageSection: View {
    @State private var choice = LanguageSwitch.current
    @State private var changed = false

    var body: some View {
        Section("Język / Language") {
            Picker("Język / Language", selection: $choice) {
                Text("Systemowy / System").tag(AppLanguage.system)
                Text("English").tag(AppLanguage.english)
                Text("Polski").tag(AppLanguage.polish)
            }
            .onChange(of: choice) { _, new in
                LanguageSwitch.apply(new)
                changed = true
            }
            if changed {
                HStack {
                    Text("Zmiana działa po ponownym uruchomieniu. / Applies after a restart.")
                        .settingsNote()
                    Spacer()
                    Button("Uruchom ponownie / Restart") { LanguageSwitch.relaunch() }
                }
            }
        }
    }
}
