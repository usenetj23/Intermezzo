import Foundation

/// Short, weather-aware suggestion shown on a break screen.
public enum WeatherAdvice {
    public static func tip(effect: WeatherEffect, uvIndex: Double?, temperatureC: Double) -> String? {
        switch effect {
        case .clear:
            if temperatureC <= -5 {
                return "Słonecznie, ale mroźno — postój chwilę przy oknie i popatrz w dal."
            }
            if let uv = uvIndex, uv >= 3 {
                return kitL("Słonecznie (UV %lld) — wyjdź na 5 minut na zewnątrz i popatrz w dal.", Int(uv.rounded()))
            }
            return "Ładna pogoda — podejdź do okna i popatrz na horyzont przez 20 sekund."
        case .rain, .storm:
            return "Za oknem deszcz — rozciągnij kark i ramiona w pomieszczeniu."
        case .snow:
            return "Pada śnieg — wstań i weź kilka głębokich oddechów przy oknie."
        case .fog:
            return "Mgła za oknem — daj oczom odpocząć, zamknij je na 20 sekund."
        case .cloudy, .none:
            return nil
        }
    }
}
