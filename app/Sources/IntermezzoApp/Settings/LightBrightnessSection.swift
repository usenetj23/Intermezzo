import SwiftUI
import IntermezzoKit

/// Screen brightness by the hour and by the room's light: two equalisers next to the colour chart.
struct LightBrightnessSection: View {
    @AppStorage(BrightnessKeys.enabled) private var enabled = false
    @AppStorage(BrightnessKeys.dayCurve) private var dayCurveText = ""
    @AppStorage(BrightnessKeys.luxCurve) private var luxCurveText = ""
    @AppStorage(BrightnessKeys.automatic) private var automatic = false
    @AppStorage(LightKeys.ambient) private var useAmbient = false
    @AppStorage(BetterDisplayKeys.dim) private var bdDim = false
    @ObservedObject private var light = LightController.shared
    @ObservedObject private var brightness = ScreenBrightnessController.shared

    private var day: BrightnessDayCurve { BrightnessDayCurve.decode(dayCurveText) ?? .standard }
    private var room: LuxBrightnessCurve { LuxBrightnessCurve.decode(luxCurveText) ?? .standard }

    var body: some View {
        Section("Jasność ekranu") {
            Toggle("Dostosowuj jasność ekranu do pory dnia i światła w pokoju", isOn: $enabled).settingsAnchor("light-dostosowuj-jasnosc-ekranu-do-pory-dn")
            Text("Jasność = wartość z wykresu godzin × mnożnik z wykresu światła w pokoju, nie mniej niż 5%. Bez odczytu czujnika (brak czujnika, zamknięta klapa, czujnik wyłączony) liczy się sam wykres godzin. Gdy sam zmienisz jasność, korektor odpuszcza na godzinę; po wyłączeniu, wstrzymaniu Światła albo zamknięciu aplikacji jasność wraca do pierwotnej.")
                .settingsNote().settingsAnchor("light-jasnosc-wartosc-z-wykresu-godzin-mno")
            if enabled { details }
        }
    }

    @ViewBuilder private var details: some View {
        nowRow
        automaticRows
        EqualizerChart(values: day.hourly, range: BrightnessDayCurve.minPercent...BrightnessDayCurve.maxPercent,
                       step: BrightnessDayCurve.step, marker: ScreenBrightness.minuteOfDay(Date()) / 60 - 0.5,
                       axisLabels: [0, 6, 12, 18, 24].map { (Double($0) - 0.5, String(format: "%02d", $0)) },
                       topLabel: "100%", bottomLabel: "5%",
                       curve: { day.percent(atMinuteOfDay: $0 * 1440) },
                       hint: { band, value in String(format: "%02d:00  %d%%", band, Int(value)) },
                       paint: { values, a, va, b, vb in
                           var curve = BrightnessDayCurve(hourly: values)
                           curve.paint(fromBand: a, percent: va, toBand: b, percent: vb)
                           return curve.hourly
                       },
                       commit: { brightness.save(BrightnessDayCurve(hourly: $0)) })
            .frame(height: 120)
            .accessibilityLabel(Text("Wykres jasności ekranu w ciągu doby"))
        Text("Każdy słupek to jedna godzina doby, a wysokość to jasność ekranu (100% to pełna). Przeciągaj jak po wykresie barwy powyżej.")
            .settingsNote().settingsAnchor("light-kazdy-slupek-to-jedna-godzina-doby-a")
        EqualizerChart(values: room.values, range: LuxBrightnessCurve.minPercent...LuxBrightnessCurve.maxPercent,
                       step: LuxBrightnessCurve.step, marker: light.lux.map { LuxBrightnessCurve.position(lux: $0) },
                       axisLabels: LuxBrightnessCurve.luxPoints.enumerated().map { (Double($0.offset), "\(Int($0.element)) lx") },
                       topLabel: "150%", bottomLabel: "20%",
                       curve: nil,
                       hint: { band, value in "\(Int(LuxBrightnessCurve.luxPoints[band])) lx  \(Int(value))%" },
                       paint: { values, a, va, b, vb in
                           var curve = LuxBrightnessCurve(values: values)
                           curve.paint(fromBand: a, percent: va, toBand: b, percent: vb)
                           return curve.values
                       },
                       commit: { brightness.save(LuxBrightnessCurve(values: $0)) })
            .frame(height: 110)
            .accessibilityLabel(Text("Wykres mnożnika jasności według światła w pokoju"))
        Text("Mnożnik dla światła w pokoju: w ciemnym pokoju ekran jest ciemniejszy, w jasnym jaśniejszy (powyżej 100% podnosi przyciemnioną godzinę, ale nigdy ponad pełną jasność). Między słupkami wartość przechodzi płynnie na skali logarytmicznej, a pionowa kreska pokazuje bieżący odczyt czujnika.")
            .settingsNote().settingsAnchor("light-mnoznik-dla-swiatla-w-pokoju-w-ciemn")
        if !useAmbient {
            Button("Włącz czujnik światła w pokoju") { useAmbient = true }.settingsAnchor("light-wlacz-czujnik-swiatla-w-pokoju")
                .controlSize(.small)
        }
        if !brightness.builtInNote.isEmpty {
            Label(brightness.builtInNote, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
        }
        if bdDim {
            Label("Korektor jasności zastępuje teraz przyciemnianie monitorów wieczorem z sekcji BetterDisplay.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
        Text("Wbudowany ekran zmieniam przez prywatny interfejs macOS (może przestać działać po aktualizacji), zewnętrzne monitory przez BetterDisplay. Bez automatu wyłącz „Automatycznie dostosowuj jasność” w Ustawieniach systemowych → Ekrany, bo macOS będzie poprawiał jasność po swojemu. Każdy ekran, także wbudowany, ma własne ustawienia jasności w sekcji Monitory (źródło, mnożnik, limity, nity); monitory „bez zarządzania” i okna-wyjątki zostają przy swojej jasności. Profil „Własne (wg zegara)” nie zmienia barwy według czujnika, ale korektor jasności korzysta z niego, gdy czujnik jest włączony.")
            .settingsNote().settingsAnchor("light-wbudowany-ekran-zmieniam-przez-prywat")
    }

    @ViewBuilder private var automaticRows: some View {
        Toggle("Automat: monitory podążają za wbudowanym ekranem (nity)", isOn: $automatic).settingsAnchor("light-automat-monitory-podazaja-za-wbudowa")
        if automatic, let nits = brightness.builtInNits {
            LabeledContent("Wbudowany ekran teraz") {
                if let max = brightness.builtInMaxNits {
                    Text("\(Int(nits)) nit z \(Int(max.rounded()))").monospacedDigit()
                } else {
                    Text("\(Int(nits)) nit").monospacedDigit()
                }
            }
        }
        Text("W automacie jasność wbudowanego ekranu ustawia macOS (włącz „Automatycznie dostosowuj jasność” w Ustawieniach systemowych → Ekrany), a aplikacja tylko ją odczytuje i przelicza na nity. Monitor dostaje jasność = nity wbudowanego ÷ maksymalne nity monitora, z jego własnym mnożnikiem i limitami (Monitory poniżej); sprawdzane co ok. 30 s. Maksimum monitora pochodzi z EDID, z wpisu ręcznego albo przyjmuję 350 nitów. Przy zamkniętej klapie albo bez odczytu monitory wracają do korektora (wykresy poniżej). Monitor z wyborem „Korektor” zostaje przy wykresach.")
            .settingsNote().settingsAnchor("light-w-automacie-jasnosc-wbudowanego-ekra")
    }

    private var nowRow: some View {
        LabeledContent("Teraz") {
            if let level = brightness.level {
                let hour = Int(day.percent(atMinuteOfDay: ScreenBrightness.minuteOfDay(Date())).rounded())
                let factor = light.lux.map { Int(room.percent(lux: $0).rounded()) }
                HStack(spacing: 6) {
                    Text(verbatim: "\(Int((level * 100).rounded()))%").monospacedDigit()
                    if let factor {
                        Text("godzina \(hour)% × pokój \(factor)%").foregroundStyle(.secondary)
                    } else {
                        Text("godzina \(hour)%, bez czujnika").foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("nie działa (Światło wyłączone lub wstrzymane)").foregroundStyle(.secondary)
            }
        }
    }
}

/// A row of draggable bars, like an equaliser. `marker` and the axis labels are in bands (0 = the first
/// bar's centre); `curve` (x in 0...1 → value) draws a smooth line over the bars.
private struct EqualizerChart: View {
    let values: [Double]
    let range: ClosedRange<Double>
    let step: Double
    let marker: Double?
    let axisLabels: [(Double, String)]
    let topLabel: String
    let bottomLabel: String
    let curve: ((Double) -> Double)?
    let hint: (Int, Double) -> String
    let paint: ([Double], Double, Double, Double, Double) -> [Double]
    let commit: ([Double]) -> Void

    @State private var draft: [Double]?
    @State private var lastPoint: (band: Double, value: Double)?
    @State private var hintText: String?

    private var shown: [Double] { draft ?? values }

    private func y(_ value: Double, _ height: CGFloat) -> CGFloat {
        let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return height - 14 - CGFloat(min(max(t, 0), 1)) * (height - 20)
    }

    private func value(atY position: CGFloat, _ height: CGFloat) -> Double {
        let t = Double((height - 14 - position) / (height - 20))
        let raw = range.lowerBound + min(max(t, 0), 1) * (range.upperBound - range.lowerBound)
        return (raw / step).rounded() * step
    }

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in draw(in: &context, size: size) }
                .overlay(alignment: .topTrailing) {
                    if let hintText {
                        Text(verbatim: hintText).font(.caption).monospacedDigit().padding(4)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                            .padding(4)
                    }
                }
                .contentShape(Rectangle())
                .gesture(drag(in: proxy.size))
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.12)))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let bands = shown
        guard !bands.isEmpty else { return }
        let width = size.width / CGFloat(bands.count)
        let span = range.upperBound - range.lowerBound
        for (index, value) in bands.enumerated() {
            let top = y(value, size.height)
            let rect = CGRect(x: CGFloat(index) * width + 1, y: top, width: width - 2, height: size.height - 14 - top)
            let strength = span > 0 ? (value - range.lowerBound) / span : 1
            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(Color.yellow.opacity(0.2 + 0.6 * strength)))
            context.fill(Path(CGRect(x: rect.minX, y: top - 1.5, width: rect.width, height: 3)), with: .color(.white.opacity(0.9)))
        }
        if let curve {
            var line = Path()
            for stepIndex in 0...144 {
                let fraction = Double(stepIndex) / 144
                let point = CGPoint(x: CGFloat(fraction) * size.width, y: y(curve(fraction), size.height))
                stepIndex == 0 ? line.move(to: point) : line.addLine(to: point)
            }
            context.stroke(line, with: .color(.white.opacity(0.55)), lineWidth: 1)
        }
        if let marker {
            let x = CGFloat(marker + 0.5) * width
            context.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height - 14)) },
                           with: .color(.white), lineWidth: 1)
        }
        for (position, text) in axisLabels {
            let label = Text(verbatim: text).font(.system(size: 9)).foregroundColor(.secondary)
            let x = min(max(CGFloat(position + 0.5) * width, 14), size.width - 14)
            context.draw(label, at: CGPoint(x: x, y: size.height - 6))
        }
        context.draw(Text(verbatim: topLabel).font(.system(size: 9)).foregroundColor(.secondary), at: CGPoint(x: 18, y: 8))
        context.draw(Text(verbatim: bottomLabel).font(.system(size: 9)).foregroundColor(.secondary), at: CGPoint(x: 18, y: size.height - 20))
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let count = Double(values.count)
                guard count > 0, size.width > 0 else { return }
                let band = min(max(Double(gesture.location.x / size.width) * count, 0), count - 0.001)
                let picked = value(atY: gesture.location.y, size.height)
                let from = lastPoint ?? (band, picked)
                draft = paint(draft ?? values, from.band, from.value, band, picked)
                lastPoint = (band, picked)
                hintText = hint(Int(band), picked)
            }
            .onEnded { _ in
                if let draft { commit(draft) }
                draft = nil
                lastPoint = nil
                hintText = nil
            }
    }
}
