import SwiftUI
import AppKit
import IntermezzoKit

/// "Relaxation Audio": one track (or generated noise) per break type, with
/// audition, track length versus break length, and looping for short tracks.
struct RelaxationAudioSection: View {
    @AppStorage(RelaxationAudioKeys.enabled) private var enabled = false
    @AppStorage(RelaxationAudioKeys.volume) private var volume = 0.25
    @AppStorage(Keys.shortBreakSeconds) private var shortBreakSeconds = 300
    @AppStorage(Keys.longBreakSeconds) private var longBreakSeconds = 900

    var body: some View {
        Section("Relaxation Audio") {
            Toggle("Play relaxing audio during breaks", isOn: $enabled)
            if enabled {
                AudioSlotEditor(kind: .short, title: "Short break", breakSeconds: shortBreakSeconds, volume: volume)
                AudioSlotEditor(kind: .long, title: "Long break", breakSeconds: longBreakSeconds, volume: volume)
                HStack(spacing: 10) {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(.secondary)
                    Slider(value: $volume, in: 0.05...1.0)
                        .onChange(of: volume) { _, v in AudioPreview.shared.setVolume(v) }
                    Text("\(Int(volume * 100))%")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
                Text("Playback volume during breaks (independent of the system volume)")
                    .settingsNote()
            }
        }
        .onDisappear { AudioPreview.shared.stop() }
    }
}

private struct AudioSlotEditor: View {
    let kind: BreakKind
    let title: LocalizedStringKey
    let breakSeconds: Int
    let volume: Double

    @State private var path: String
    @AppStorage private var loop: Bool
    @ObservedObject private var preview = AudioPreview.shared

    init(kind: BreakKind, title: LocalizedStringKey, breakSeconds: Int, volume: Double) {
        self.kind = kind
        self.title = title
        self.breakSeconds = breakSeconds
        self.volume = volume
        _path = State(initialValue: RelaxationAudioKeys.storedPath(for: kind))
        _loop = AppStorage(wrappedValue: true, RelaxationAudioKeys.loop(for: kind))
    }

    private var slot: String { kind == .long ? "long" : "short" }
    private var isNoise: Bool { path.isEmpty }
    private var isPlaying: Bool { preview.playingSlot == slot }
    private var trackSeconds: TimeInterval? { isNoise ? nil : RelaxationAudio.duration(ofPath: path) }
    private var fit: AudioFit {
        AudioFit.evaluate(trackSeconds: trackSeconds, breakSeconds: TimeInterval(breakSeconds), loop: loop)
    }

    private var bundledChoices: [BundledTrack] { RelaxationAudio.tracks }
    private var isCustom: Bool {
        !isNoise && !bundledChoices.contains { $0.url.path == RelaxationAudio.resolve(path) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Text("· \(AudioFit.clock(TimeInterval(breakSeconds)))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Picker("Track", selection: pathBinding) {
                    Text("Brown noise (generated live)").tag("")
                    ForEach(bundledChoices) { t in
                        Text("\(t.label) — \(durationText(t.url.path))").tag(t.url.path)
                    }
                    if isCustom {
                        Text("\((path as NSString).lastPathComponent) — \(durationText(path))").tag(path)
                    }
                }
                .labelsHidden()
                Button("Choose…", action: chooseFile).controlSize(.small)
                Button {
                    preview.toggle(slot: slot, path: path, volume: volume, loop: loop)
                } label: {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                }
                .controlSize(.small)
                .disabled(isNoise)
                .help(isPlaying ? "Stop" : "Listen")
            }
            if isPlaying {
                ProgressView(value: min(preview.position, preview.length), total: max(preview.length, 0.1)) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(AudioFit.clock(preview.position)) / \(AudioFit.clock(preview.length))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if !isNoise {
                Toggle("Loop when shorter than the break", isOn: $loop)
                    .onChange(of: loop) { _, _ in if isPlaying { restartPreview() } }
            }
            fitLabel
        }
        .padding(.vertical, 2)
    }

    private var pathBinding: Binding<String> {
        Binding(get: { path }, set: { setPath($0) })
    }

    private func setPath(_ new: String) {
        if isPlaying { preview.stop() }
        path = new
        UserDefaults.standard.set(new, forKey: RelaxationAudioKeys.path(for: kind))
    }

    private func restartPreview() {
        preview.stop()
        preview.toggle(slot: slot, path: path, volume: volume, loop: loop)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { setPath(url.path) }
    }

    private func durationText(_ p: String) -> String {
        RelaxationAudio.duration(ofPath: p).map(AudioFit.clock) ?? "?"
    }

    @ViewBuilder
    private var fitLabel: some View {
        if isNoise {
            Label("Generated noise fills the whole break", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.caption)
        } else {
            let length = trackSeconds.map(AudioFit.clock) ?? "?"
            switch fit {
            case .coversBreak(let excess):
                Label(excess < 1
                      ? "Track \(length) fits the break exactly"
                      : "Track \(length) fills the break; the last \(AudioFit.clock(excess)) won't be heard (fades out)",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.caption)
            case .loops(let times):
                Label("Track \(length) repeats about ×\(times) to fill the break",
                      systemImage: "repeat.circle.fill")
                    .foregroundStyle(.green).font(.caption)
            case .endsEarly(let silent):
                Label("Track \(length) ends \(AudioFit.clock(silent)) before the break does — turn on looping",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.caption)
            case .unknown:
                Label("Could not read the track length", systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary).font(.caption)
            }
        }
    }
}
