import SwiftUI
import SwiftData
import AppKit
import Combine
import IntermezzoKit

@main
struct IntermezzoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        Settings {
            SettingsView()
        }
        .modelContainer(Store.container)
    }
}
