import SwiftUI
import IntermezzoKit

/// The window of the location picker: the map, where the pin is, when the Sun rises and sets there.
struct LocationMapSheet: View {
    let onUse: (GeoPoint) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewport: MapViewport
    @State private var pin: GeoPoint?
    @State private var mapSize = CGSize(width: 720, height: 360)

    /// `center` is where the map opens; `pin` is the place chosen so far, if any.
    init(center: GeoPoint, pin: GeoPoint?, onUse: @escaping (GeoPoint) -> Void) {
        self.onUse = onUse
        _viewport = State(initialValue: MapViewport(center: pin ?? center, zoom: pin == nil ? 3 : 6))
        _pin = State(initialValue: pin)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wybierz miejsce na mapie").font(.headline)
            Text("Kliknij mapę, żeby postawić pinezkę, i przeciągnij ją, żeby ją przesunąć. Przeciągnięcie mapy przesuwa mapę, a kółko myszy, szczypanie i przyciski + i − ją przybliżają. Cień pokazuje, gdzie teraz jest dzień, zmierzch i noc.")
                .settingsNote()
            LocationMapView(viewport: $viewport, pin: $pin, size: $mapSize)
                .frame(minWidth: 640, minHeight: 340)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            if !PreparedMap.shared.isAvailable {
                Label("Mapa jest niedostępna, ale współrzędne możesz wpisać ręcznie.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
            info
            Text("Dane mapy: Natural Earth (domena publiczna); nazwy miast: GeoNames, licencja CC BY 4.0.").settingsNote()
            HStack {
                Spacer()
                Button("Anuluj", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Użyj tego miejsca") {
                    if let pin { onUse(pin) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pin == nil)
            }
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 540)
    }

    @ViewBuilder private var info: some View {
        if let pin {
            LabeledContent("Współrzędne") {
                Text(LightLocation.format(pin)).monospacedDigit()
            }
            Text(sunTimes(at: pin)).settingsNote()
        } else {
            Text("Nie wybrano jeszcze miejsca.").settingsNote()
        }
        Text("Skala mapy: ok. \(scale) km na punkt ekranu").settingsNote()
    }

    private var scale: String {
        let km = viewport.kilometresPerPixel(in: mapSize)
        return km >= 10 ? String(format: "%.0f", km) : String(format: "%.1f", km)
    }

    /// Sunrise and sunset in the Mac's time zone; polar day and night have neither.
    private func sunTimes(at point: GeoPoint) -> String {
        let now = Date()
        guard let first = LightSchedule.nextSunEvent(after: now, latitude: point.latitude, longitude: point.longitude),
              let second = LightSchedule.nextSunEvent(after: first.date.addingTimeInterval(60),
                                                      latitude: point.latitude, longitude: point.longitude)
        else { return String(localized: "Brak wschodu lub zachodu Słońca w tym miejscu (dzień lub noc polarna).") }
        let rise = [first, second].first { $0.kind == .sunrise }?.date
        let set = [first, second].first { $0.kind == .sunset }?.date
        let format = { (date: Date?) in date?.formatted(date: .omitted, time: .shortened) ?? "" }
        return String(localized: "Wschód \(format(rise)), zachód \(format(set)) (czas Maca).")
    }
}
