import AVFoundation
import Foundation

/// Audition of a relaxation track from Settings. One preview at a time; it is
/// stopped when a real break starts (see `RelaxationAudioController`).
@MainActor
final class AudioPreview: ObservableObject {
    static let shared = AudioPreview()

    /// Slot that is currently auditioned (e.g. "short", "long"), nil when silent.
    @Published private(set) var playingSlot: String?
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var length: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var ticker: Timer?

    func toggle(slot: String, path: String, volume: Double, loop: Bool) {
        if playingSlot == slot { stop(); return }
        stop()
        guard let resolved = RelaxationAudio.resolve(path),
              let p = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: resolved)) else { return }
        p.volume = Float(min(1.0, max(0.02, volume)))
        p.numberOfLoops = loop ? -1 : 0
        p.prepareToPlay()
        p.play()
        player = p
        length = p.duration
        position = 0
        playingSlot = slot
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        player?.stop()
        player = nil
        playingSlot = nil
        position = 0
    }

    /// Live volume while the slider is dragged.
    func setVolume(_ volume: Double) {
        player?.volume = Float(min(1.0, max(0.02, volume)))
    }

    private func tick() {
        guard let p = player else { stop(); return }
        if !p.isPlaying { stop(); return }       // reached the end of a non-looping track
        position = p.currentTime
    }
}
