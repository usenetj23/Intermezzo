import AppKit
import SwiftUI

enum RunningApps {
    /// Names of the apps with a Dock icon, for "add a running app" menus.
    static func regularNames() -> [String] {
        let names = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.localizedName)
        return Array(Set(names)).sorted()
    }
}

/// Keeps the running-app list in a view's state: read once when it appears and again only when an app
/// starts or quits (each read is a LaunchServices call per app, too slow for every redraw).
struct RunningAppsReader: ViewModifier {
    @Binding var names: [String]

    func body(content: Content) -> some View {
        let center = NSWorkspace.shared.notificationCenter
        return content
            .onAppear { names = RunningApps.regularNames() }
            .onReceive(center.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
                names = RunningApps.regularNames()
            }
            .onReceive(center.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
                names = RunningApps.regularNames()
            }
    }
}

extension View {
    func readsRunningApps(into names: Binding<[String]>) -> some View { modifier(RunningAppsReader(names: names)) }
}
