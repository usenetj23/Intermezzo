import Foundation

/// How the light in the room (measured in lux by the Mac's ambient light sensor) changes the schedule.
/// Pure functions; reading the sensor is the app's job.
public enum AmbientLight {
    /// Below this the room counts as dark, above `brightLux` as bright.
    /// An evening room lit by a lamp or two is 50-200 lx; daylight indoors is well over 1000.
    static let darkLux = 100.0
    static let brightLux = 1500.0
    /// The most the evening warming is weakened in a bright room.
    static let maxWarmthReduction = 0.4

    /// The median of the recent samples (one odd reading must not move the screen).
    public static func smoothed(_ samples: [Double]) -> Double? {
        let valid = samples.filter { $0 >= 0 && $0.isFinite }.sorted()
        guard !valid.isEmpty else { return nil }
        let mid = valid.count / 2
        return valid.count % 2 == 1 ? valid[mid] : (valid[mid - 1] + valid[mid]) / 2
    }

    /// 0 in a dark room, 1 in a bright one, on a log scale (the eye judges light that way).
    public static func brightness(lux: Double) -> Double {
        let low = log10(darkLux), high = log10(brightLux)
        return min(max((log10(max(lux, 1)) - low) / (high - low), 0), 1)
    }

    /// The colour the screen gets once the room is taken into account.
    /// - Evening warming is weaker in a bright room (the screen is a small part of the light there).
    /// - Lamps of a known colour keep the screen from being much cooler than the room in the evening.
    public static func adjustedKelvin(_ kelvin: Double, lux: Double, settings: LightSettings, roomLampK: Double?) -> Double {
        let s = settings.sanitized
        let warming = max(s.dayK - kelvin, 0)
        var result = s.dayK - warming * (1 - maxWarmthReduction * brightness(lux: lux))
        if let lamp = roomLampK, lamp > 0, lux >= darkLux, warming > 500 {
            result = min(result, max(lamp + 500, LightSettings.minKelvin))
        }
        return min(max(result, LightSettings.minKelvin), s.dayK)
    }

    /// How much of the evening dimming applies: all of it in a dark room, none in a bright one.
    public static func dimScale(lux: Double) -> Double {
        1 - brightness(lux: lux)
    }

    /// Applies `dimScale` to a brightness factor (1 = no dimming).
    public static func scaledDimFactor(_ factor: Double, lux: Double?) -> Double {
        guard let lux else { return factor }
        return 1 - (1 - factor) * dimScale(lux: lux)
    }
}

/// Ready-made exclusion lists: apps where colours must stay true.
public enum LightExclusionPresets {
    public struct Preset: Sendable {
        public let id: String
        public let apps: [String]
    }

    public static let all: [Preset] = [
        Preset(id: "creative", apps: ["Final Cut Pro", "DaVinci Resolve", "Adobe Premiere Pro", "Adobe Photoshop",
                                      "Adobe Lightroom", "Adobe After Effects", "Adobe Illustrator", "Pixelmator Pro",
                                      "Affinity Photo", "Affinity Designer", "Capture One", "Blender", "Compressor"]),
        Preset(id: "video", apps: ["IINA", "VLC", "QuickTime Player", "Infuse", "Plex", "TV"]),
        Preset(id: "games", apps: ["Steam", "Epic Games Launcher", "Battle.net", "GOG Galaxy", "Heroic", "CrossOver",
                                   "Whisky", "Minecraft"]),
    ]

    /// `current` (comma text) with the preset's apps added once each.
    public static func adding(_ preset: Preset, to current: String) -> String {
        var list = KeepAwakeApps.list(fromCommaText: current)
        for app in preset.apps where !list.contains(where: { KeepAwakeApps.normalized($0) == KeepAwakeApps.normalized(app) }) {
            list.append(app)
        }
        return list.joined(separator: ", ")
    }
}
