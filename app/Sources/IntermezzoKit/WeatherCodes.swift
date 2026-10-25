import Foundation

/// Mapowanie kodów WMO (Open-Meteo `weather_code`) na efekt wizualny przerw.
/// Czysta funkcja — testowalna w IntermezzoKit.
public enum WeatherEffect: String, CaseIterable, Codable {
    case clear, cloudy, fog, rain, snow, storm, none

    public static func from(wmoCode code: Int) -> WeatherEffect {
        switch code {
        case 0: return .clear
        case 1, 2, 3: return .cloudy
        case 45, 48: return .fog
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82: return .rain
        case 71, 73, 75, 77, 85, 86: return .snow
        case 95, 96, 99: return .storm
        default: return .none
        }
    }
}
