import SwiftUI
import SwiftData
import AppKit
import Carbon.HIToolbox
import ServiceManagement
import CoreLocation
import UserNotifications
import IOKit.hidsystem
import IntermezzoKit

struct TimeInput: View {
    @Binding var minutes: Int

    var body: some View {
        HStack(spacing: 3) {
            Picker("", selection: Binding(
                get: { minutes / 60 },
                set: { hours in minutes = hours * 60 + minutes % 60 })) {
                ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            .frame(width: 64)
            Text(":")
            Picker("", selection: Binding(
                get: { minutes % 60 },
                set: { mins in minutes = minutes - minutes % 60 + mins })) {
                ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) {
                    Text(String(format: "%02d", $0)).tag($0)
                }
            }
            .frame(width: 64)
        }
        .pickerStyle(.menu)
        .controlSize(.small)
    }
}

// MARK: - Hotkey recorder row

/// Shows the current shortcut and lets the user record a new one.
/// Press the button, then the desired key combination (Esc cancels).
struct HotkeyRecorderRow: View {
    private let key: String
    private let title: LocalizedStringKey

    @State private var recording = false
    @State private var monitor: Any?

    init(_ key: String, title: LocalizedStringKey) {
        self.key = key
        self.title = title
    }

    private var storage: Binding<String> {
        Binding(
            get: { UserDefaults.standard.string(forKey: key) ?? "" },
            set: { UserDefaults.standard.set($0, forKey: key) })
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(recording ? String(localized: "Naciśnij kombinację…")
                               : (HotkeySpec.parse(storage.wrappedValue)?.display ?? "—"))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(recording ? Color.accentColor : .secondary)
                    .frame(minWidth: 90, alignment: .trailing)
                Button(recording ? "Anuluj" : "Zmień…") {
                    recording ? stop() : start()
                }
                .controlSize(.small)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            let carbon = Self.carbonMask(event.modifierFlags)
            guard carbon != 0 else { return nil }   // require at least one modifier
            storage.wrappedValue = "\(event.keyCode)|\(carbon)"
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func carbonMask(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var c: UInt32 = 0
        if flags.contains(.control) { c |= UInt32(controlKey) }
        if flags.contains(.option) { c |= UInt32(optionKey) }
        if flags.contains(.shift) { c |= UInt32(shiftKey) }
        if flags.contains(.command) { c |= UInt32(cmdKey) }
        return c
    }
}

/// Options most people won't need: idle-detection method, temptation
/// blockers (Hide…), sleep guard, duplicate-copy alert.
/// No analytics: Intermezzo talks to nobody.
/// Wiersz statusu uprawnienia: zielony ptaszek gdy przyznane, czerwony +
/// przycisk "Otwórz…" gdy nie (albo "?" gdy jeszcze nie wiemy).
struct PermissionRow: View {
    let kind: PermissionKind
    let status: PermissionStatus
    let action: () -> Void

    private var icon: (name: String, color: Color) {
        switch status {
        case .granted: return ("checkmark.circle.fill", .green)
        case .denied: return ("xmark.circle.fill", .red)
        case .notDetermined: return ("questionmark.circle", .secondary)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon.name).foregroundStyle(icon.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(localized: kind.title)
                Text(localized: kind.usedFor).settingsNote()
            }
            Spacer()
            switch status {
            case .granted:
                // Location and notifications cannot be reset from here: their switches live in System Settings.
                if kind.tccService == nil { Button("Open Settings…", action: action).controlSize(.small) }
            case .notDetermined: Button("Allow…", action: action).controlSize(.small)
            case .denied: Button("Open Settings…", action: action).controlSize(.small)
            }
        }
    }
}
