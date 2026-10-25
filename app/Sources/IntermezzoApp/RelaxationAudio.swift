import AVFoundation
import Foundation
import IntermezzoKit

/// UserDefaults keys for relaxation audio (nonisolated so Views/@AppStorage can use them).
enum RelaxationAudioKeys {
    static let enabled = "relaxAudioEnabled"
    /// Legacy single track (before short/long slots); still the fallback for a slot that was never set.
    static let path = "relaxAudioPath"
    static let volume = "relaxVolume"

    static func path(for kind: BreakKind) -> String {
        kind == .long ? "relaxAudioPath.long" : "relaxAudioPath.short"
    }

    static func loop(for kind: BreakKind) -> String {
        kind == .long ? "relaxLoop.long" : "relaxLoop.short"
    }

    /// Track for a slot: `nil` = never chosen (→ legacy track), `""` = brown noise.
    static func storedPath(for kind: BreakKind, defaults d: UserDefaults = .standard) -> String {
        d.string(forKey: path(for: kind)) ?? d.string(forKey: path) ?? ""
    }

    /// Loop shorter tracks over the whole break (default on, as before slots existed).
    static func loops(for kind: BreakKind, defaults d: UserDefaults = .standard) -> Bool {
        d.object(forKey: loop(for: kind)) == nil ? true : d.bool(forKey: loop(for: kind))
    }
}

/// Ścieżki dołączone do paczki: skan katalogu Resources/tracks
/// (pliki .wav/.mp3/.m4a wrzucone tam w buildzie). Id = nazwa pliku bez rozszerzenia.
struct BundledTrack: Identifiable {
    let id: String
    let label: String
    let url: URL
}

enum RelaxationAudio {
    /// Czyść etykietę: usuń sufiks "-NNNNNN" (ID rynku), myślniki → spacje.
    private static func friendlyLabel(_ file: String) -> String {
        var s = (file as NSString).deletingPathExtension
        s = s.replacingOccurrences(of: "-\\d{4,}$", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "_", with: " ")
        s = s.replacingOccurrences(of: "-", with: " ")
        // kapitalizacja pierwszej litery
        if let first = s.first { s = String(first).uppercased() + s.dropFirst() }
        return s
    }

    /// Pełna lista ścieżek zainstalowanych w paczce (sortowanie alfabetyczne).
    static func scanTracks() -> [BundledTrack] {
        let fm = FileManager.default
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("tracks"),
              let files = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        let okExts: Set<String> = ["wav", "mp3", "m4a"]
        return files
            .filter { okExts.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
            .map { name in
                BundledTrack(id: name,
                            label: friendlyLabel(name),
                            url: dir.appendingPathComponent(name))
            }
    }

    static var tracks: [BundledTrack] { scanTracks() }

    static func bundleURL(for id: String) -> URL? {
        guard !id.isEmpty else { return nil }
        let dir = Bundle.main.resourceURL?.appendingPathComponent("tracks")
        let url = dir?.appendingPathComponent(id)
        return (url != nil && FileManager.default.fileExists(atPath: url!.path)) ? url : nil
    }

    /// Znajdź ID ścieżki po zapisanej ścieżce (do inicjalizacji UI).
    static func trackID(forPath path: String) -> String {
        guard !path.isEmpty else { return "" }
        let name = (path as NSString).lastPathComponent
        return scanTracks().first(where: { $0.id == name })?.id ?? ""
    }

    /// A picked bundled track is stored as an absolute path INTO the bundle it was
    /// chosen from; once the app is moved or rebuilt elsewhere that path is stale
    /// and playback silently fell back to synthesized noise. Prefer the same file
    /// name inside the running bundle.
    static func resolve(_ path: String) -> String? {
        guard !path.isEmpty else { return nil }
        let fm = FileManager.default
        if path.contains("/Contents/Resources/tracks/"),
           let dir = Bundle.main.resourceURL?.appendingPathComponent("tracks") {
            let local = dir.appendingPathComponent((path as NSString).lastPathComponent).path
            if fm.fileExists(atPath: local) { return local }
        }
        return fm.fileExists(atPath: path) ? path : nil
    }

    private static var durationCache: [String: TimeInterval] = [:]

    /// Length of an audio file in seconds (header read, cached), nil when unreadable.
    static func duration(ofPath path: String) -> TimeInterval? {
        guard let resolved = resolve(path) else { return nil }
        if let hit = durationCache[resolved] { return hit }
        guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: resolved)) else { return nil }
        let rate = file.processingFormat.sampleRate
        guard rate > 0 else { return nil }
        let seconds = Double(file.length) / rate
        durationCache[resolved] = seconds
        return seconds
    }
}

/// Plays relaxing audio while a break is running, stops the moment the break
/// ends. Two sources: a user-picked audio file (looped) or, when none is
/// configured, a softly filtered brown-noise generator synthesized live with
/// AVAudioEngine — no bundled assets, no network.
@MainActor
final class RelaxationAudioController {
    private var player: AVAudioPlayer?
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var stopGen = 0

    func startDuringBreak(kind: BreakKind) {
        let d = UserDefaults.standard
        guard d.integer(forKey: RelaxationAudioKeys.enabled) != 0 else { return }
        stop()
        AudioPreview.shared.stop()
        let volume = Float(min(1.0, max(0.02, d.double(forKey: RelaxationAudioKeys.volume))))
        if let path = RelaxationAudio.resolve(RelaxationAudioKeys.storedPath(for: kind)),
           let p = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) {
            p.numberOfLoops = RelaxationAudioKeys.loops(for: kind) ? -1 : 0
            p.volume = volume
            p.prepareToPlay()
            p.play()
            player = p
            Trace.log("relaxation: playing \(kind) file \(path) loop=\(RelaxationAudioKeys.loops(for: kind))")
        } else {
            startBrownNoise(volume: volume)
        }
    }

    /// Zatrzymaj dźwięk. fadeSeconds > 0 → płynny fade-out (muzyka gaśnie
    /// razem z końcem przerwy), dopiero potem fizyczne stop. Nowe odtwarzanie
    /// anuluje oczekujący stop (licznik generacji).
    func stop(fadeSeconds: TimeInterval = 0) {
        stopGen += 1
        let gen = stopGen
        if fadeSeconds > 0 {
            Trace.log("relaxation: fade-out \(String(format: "%.1f", fadeSeconds))s")
            if let p = player {
                p.setVolume(0, fadeDuration: fadeSeconds)
                DispatchQueue.main.asyncAfter(deadline: .now() + fadeSeconds + 0.15) { [weak self] in
                    guard let self, self.stopGen == gen else { return }
                    p.stop()
                    if self.player === p { self.player = nil }
                }
            }
            if engine != nil {
                // Brown noise: krokowe ściszenie (mieszalnik nie robi rampy).
                var remaining = fadeSeconds
                func stepFade() {
                    guard stopGen == gen, let eng = engine else { return }
                    remaining -= 0.25
                    if remaining <= 0 {
                        eng.mainMixerNode.outputVolume = 0
                        eng.stop()
                        if let node = sourceNode { eng.detach(node) }
                        sourceNode = nil
                        engine = nil
                    } else {
                        eng.mainMixerNode.outputVolume *= 0.78
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { stepFade() }
                    }
                }
                stepFade()
            }
            return
        }
        player?.stop()
        player = nil
        engine?.stop()
        if let node = sourceNode { engine?.detach(node) }
        sourceNode = nil
        engine = nil
    }

    // MARK: - Brown noise generator

    private func startBrownNoise(volume: Float) {
        let eng = AVAudioEngine()
        var lastOut = 0.0
        let node = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let white = Double.random(in: -1.0...1.0)
                // Leaky integration → brown noise (soft, rain-like hiss).
                let brown = (lastOut + 0.02 * white) / 1.02
                lastOut = brown
                let sample = Float(brown * 3.2)   // bring up to audible range
                for buffer in ablPointer {
                    let buf = UnsafeMutableBufferPointer<Float>(buffer)
                    buf[frame] = sample
                }
            }
            return noErr
        }
        sourceNode = node
        eng.attach(node)
        let format = eng.outputNode.inputFormat(forBus: 0)
        eng.connect(node, to: eng.mainMixerNode, format: format)
        eng.mainMixerNode.outputVolume = volume
        eng.prepare()
        do { try eng.start(); Trace.log("relaxation: brown noise started") } catch {
            Trace.log("relaxation: engine failed \(error.localizedDescription)")
            eng.detach(node)
            sourceNode = nil
            return
        }
        engine = eng
    }
}
