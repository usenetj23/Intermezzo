import SwiftUI
import WebKit

/// "YouTube" break theme: paste any YouTube URL, and during
/// a break the video plays behind the break text on the main screen.

enum YouTubeThemeKeys {
    static let enabled = "youTubeThemeEnabled"
    static let url = "youTubeUrl"
    static let volume = "youTubeVolume"
    static let startRandom = "youTubeStartRandom"
    static let startOffset = "youTubeStartOffset"
}

/// Extracts (videoId, playlistId) from any common YouTube URL form.
func youTubeIds(from raw: String) -> (video: String?, playlist: String?) {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, let comps = URLComponents(string: text) else { return (nil, nil) }

    var video: String?
    var playlist: String?
    for item in comps.queryItems ?? [] {
        if item.name == "v", let v = item.value, !v.isEmpty { video = v }
        if item.name == "list", let v = item.value, !v.isEmpty { playlist = v }
    }
    let host = (comps.host ?? "").replacingOccurrences(of: "www.", with: "")
    let parts = comps.path.split(separator: "/").map(String.init)
    if host == "youtu.be", let first = parts.first, !first.isEmpty {
        video = first
    }
    if host.contains("youtube.com"), video == nil, let first = parts.first {
        if first == "embed", parts.count > 1 { video = parts[1] }
        if first == "shorts", parts.count > 1 { video = parts[1] }
    }
    return (video, playlist)
}

/// The embed URL to load for the theme (nil when nothing usable).
func youTubeEmbedURL(raw: String, random: Bool, offset: Int) -> String? {
    let (video, playlist) = youTubeIds(from: raw)
    var query = ["autoplay": "1", "playsinline": "1", "controls": "1",
                "rel": "0", "modestbranding": "1"]
    if random {
        query["start"] = String(Int.random(in: 0...3600))
    } else if offset > 0 {
        query["start"] = String(offset)
    }
    let queryString = query.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
    if let video {
        return "https://www.youtube.com/embed/\(video)?\(queryString)"
    }
    if let playlist {
        return "https://www.youtube.com/embed/videoseries?list=\(playlist)&\(queryString)"
    }
    return nil
}

// MARK: - SwiftUI wrapper

struct YouTubePlayView: NSViewRepresentable {
    let embedURL: String
    let volumePercent: Int

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Allow autoplay without a user gesture (the break overlay is not a
        // browsing context — the whole point is hands-free playback).
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        if let url = URL(string: embedURL) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Apply the configured volume once the player exists (retry a few times:
        // the <video> element appears only after YouTube finishes bootstrapping).
        let vol = Double(max(0, min(100, volumePercent))) / 100.0
        for delay in [1.0, 2.5, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                webView.evaluateJavaScript(
                    "document.querySelectorAll('video').forEach(v => { v.muted = \(vol <= 0); v.volume = \(vol); });",
                    completionHandler: nil)
            }
        }
    }
}
