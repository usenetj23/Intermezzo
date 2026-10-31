import IntermezzoKit
import SwiftUI
import CoreGraphics
import CoreLocation
import Quartz
import Accelerate
#if canImport(ObjectiveC)
#endif

// MARK: - "Glass" i "Frost": żywy obraz ekranu pod przerwą + efekty pogodowe.
//
// Podbudowa = aktualnie wyświetlany obraz, mocno rozmyty — jak szybka woda na oknie; "Frost" = mrożone szkło;
// plus nasza własna warstwa pogodowa z Open-Meteo (bez kluczy, cache 15 min).
// Bez analityki: jedno żądanie HTTP na 15 minut, tylko kody pogodowe.

enum GlassKeys {
    /// "blur" (domyślny systemowy NSVisualEffectView) | "glass" | "frost"
    static let effect = "screenGlassEffect"
    static let weatherFX = "weatherFXEnabled"
    static let lat = "weatherLat"
    static let lon = "weatherLon"
}

struct WeatherSnapshot {
    var effect: WeatherEffect
    var temperatureC: Double
    var windKmh: Double
    var windDirDeg: Double
    var fetchedAt: Date
    /// Today's max UV index (Open-Meteo daily), when available.
    var uvIndex: Double?
    /// Cloud cover in percent (Open-Meteo current), when available.
    var cloudCover: Double?

    /// Czy snapshot wciąż ważny (cache Open-Meteo: 15 minut).
    var isFresh: Bool { Date().timeIntervalSince(fetchedAt) < 15 * 60 }
}

// MARK: - Pobieranie pogody (Open-Meteo, zero kluczy)

@MainActor
final class WeatherController {
    static let shared = WeatherController()
    private(set) var snapshot: WeatherSnapshot?
    private var fetching = false
    private var locationRequested = false
    private var lastAttempt = Date.distantPast
    /// What happened the last time, for the diagnostics ("ok …", "no location", "fetch failed …").
    private(set) var lastStatus = "not requested yet"
    private let locationFetcher = LocationOneShot()

    /// intermezzo://debug/weather?effect=rain&wind=15 — wymusza warunki do podglądu.
    func debugForce(effect: WeatherEffect, windKmh: Double) {
        snapshot = WeatherSnapshot(effect: effect, temperatureC: 10, windKmh: windKmh,
                                   windDirDeg: 270, fetchedAt: Date())
        Trace.log("weather: DEBUG forced \(effect.rawValue) wind \(Int(windKmh))")
    }

    /// Odśwież dane, jeśli włączone i cache nieświeży.
    /// `ignoreSetting`: the light schedule asks for cloud cover even when the glass weather is off.
    func refreshIfNeeded(force: Bool = false, ignoreSetting: Bool = false) {
        guard ignoreSetting || UserDefaults.standard.integer(forKey: GlassKeys.weatherFX) != 0 else { return }
        if !force, let s = snapshot, s.isFresh { return }
        guard !fetching else { return }
        // Nieudane próby (brak sieci) nie mogą się powtarzać co sekundę.
        if !force, Date().timeIntervalSince(lastAttempt) < 60 { return }
        lastAttempt = Date()
        Trace.log("weather: refresh requested")
        lastStatus = "requested"

        // Potrzebna lokalizacja: najpierw cache, potem CoreLocation (raz).
        let d = UserDefaults.standard
        func coord(_ key: String) -> Double? {
            if let v = d.object(forKey: key) as? Double { return v }
            if let s = d.string(forKey: key), let v = Double(s) { return v }
            return nil
        }
        guard let lat = coord(GlassKeys.lat), let lon = coord(GlassKeys.lon) else {
            Trace.log("weather: no cached location, requesting CoreLocation")
            lastStatus = "no location yet (Location permission needed or no fix)"
            if !locationRequested {
                locationRequested = true
                locationFetcher.onLocation = { [weak self] lat, lon in
                    Task { @MainActor in
                        d.set(lat, forKey: GlassKeys.lat)
                        d.set(lon, forKey: GlassKeys.lon)
                        self?.refreshIfNeeded(force: true)
                    }
                }
                locationFetcher.requestOnce()
            }
            return
        }
        fetching = true
        Task { [weak self] in
            defer { self?.fetching = false }
            do {
                guard let url = URL(string:
                    "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=weather_code,temperature_2m,wind_speed_10m,wind_direction_10m,cloud_cover&daily=uv_index_max&forecast_days=1&timezone=auto") else { return }
                var req = URLRequest(url: url, timeoutInterval: 8)
                req.setValue("Intermezzo/1.9", forHTTPHeaderField: "User-Agent")
                let (data, _) = try await URLSession.shared.data(for: req)
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let current = json["current"] as? [String: Any],
                      let code = current["weather_code"] as? Int else {
                    Trace.log("weather: bad payload")
                    self?.lastStatus = "bad answer from the weather service"
                    return
                }
                let temp = (current["temperature_2m"] as? Double) ?? 0
                let wind = (current["wind_speed_10m"] as? Double) ?? 0
                let windDir = (current["wind_direction_10m"] as? Double) ?? 0
                let uv = ((json["daily"] as? [String: Any])?["uv_index_max"] as? [Double])?.first
                self?.snapshot = WeatherSnapshot(effect: .from(wmoCode: code),
                                                 temperatureC: temp,
                                                 windKmh: wind, windDirDeg: windDir,
                                                 fetchedAt: Date(), uvIndex: uv,
                                                 cloudCover: current["cloud_cover"] as? Double)
                self?.lastStatus = "ok, \(WeatherEffect.from(wmoCode: code).rawValue)"
                Trace.log("weather: code=\(code) effect=\(WeatherEffect.from(wmoCode: code).rawValue) \(temp)°C wiatr \(Int(wind)) km/h")
            } catch {
                Trace.log("weather: fetch failed \(error.localizedDescription)")
                self?.lastStatus = "fetch failed (\((error as NSError).code))"
            }
        }
    }
}

// MARK: - Jednorazowy pobieracz lokalizacji (wkładka dla widoku)

final class LocationOneShot: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onLocation: ((Double, Double) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestOnce() {
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        onLocation?(loc.coordinate.latitude, loc.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Bez lokalizacji — pogody po prostu nie ma; zero crashy.
    }
}

// MARK: - Captura ekranu (Glass) i obraz tła

/// Zatrzymuje klatkę obecnego ekranu (z pominięciem wskazanego okna)
/// i rozmywa ją. Bez uprawnień Nagrywanie ekranu Capture wraca pusta —
/// wtedy zostajemy przy systemowym blur.
private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

enum ScreenGlass {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    /// Klatka danego ekranu -> NSImage rozmyty (radius px).
    /// Render w pełni na CPU (Accelerate/vImage): CIFilter odpala te same
    /// co Canvas/ImageRenderer crashe telemetry Metal na macOS 27 beta
    /// (-[__NSCFNumber length] przy commicie command buffera).
    /// Downsample 4x -> box blur x3 (przybliżenie Gaussa) -> upscale.
    static func blurredShot(of screen: NSScreen, radius: CGFloat, frost: Bool) -> NSImage? {
        guard let id = screen.displayID, let shot = CGDisplayCreateImage(id) else { return nil }
        let w = shot.width, h = shot.height
        guard w > 16, h > 16 else { return nil }
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let sw = max(64, w / 4), sh = max(64, h / 4)
        guard let small = CGContext(data: nil, width: sw, height: sh, bitsPerComponent: 8,
                                    bytesPerRow: 0, space: cs,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let px = small.data else { return nil }
        small.interpolationQuality = .medium
        small.draw(shot, in: CGRect(x: 0, y: 0, width: CGFloat(sw), height: CGFloat(sh)))

        let rowBytes = small.bytesPerRow
        var src = vImage_Buffer(data: px, height: vImagePixelCount(sh),
                                 width: vImagePixelCount(sw), rowBytes: rowBytes)
        let tmpBytes = rowBytes * sh * 3
        guard let tmp1 = malloc(tmpBytes), let tmp2 = malloc(tmpBytes) else { return nil }
        defer { free(tmp1); free(tmp2) }
        var a = vImage_Buffer(data: tmp1, height: vImagePixelCount(sh),
                              width: vImagePixelCount(sw), rowBytes: rowBytes)
        var b = vImage_Buffer(data: tmp2, height: vImagePixelCount(sh),
                              width: vImagePixelCount(sw), rowBytes: rowBytes)
        let r = max(1, UInt32(radius / 4))
        let flags = vImage_Flags(kvImageEdgeExtend)
        var ok = vImageBoxConvolve_ARGB8888(&src, &a, nil, 0, 0, r, r, nil, flags) == 0
        if ok { ok = vImageBoxConvolve_ARGB8888(&a, &b, nil, 0, 0, r, r, nil, flags) == 0 }
        if ok { ok = vImageBoxConvolve_ARGB8888(&b, &src, nil, 0, 0, r, r, nil, flags) == 0 }
        guard ok, let blurred = small.makeImage() else { return nil }

        // Upscale do pełnej rozdzielczości (interpolacja = miękkość) + szron.
        guard let full = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                   bytesPerRow: 0, space: cs,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        full.interpolationQuality = .high
        full.draw(blurred, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        if frost {
            full.setFillColor(CGColor(gray: 1, alpha: 0.16))
            full.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        }
        guard let out = full.makeImage() else { return nil }
        return NSImage(cgImage: out, size: screen.frame.size)
    }
}

// MARK: - Widoki efektów pogodowych (na żywo).
// UWAGA: celowo BEZ Canvas — rysowanie przez RenderBox (Canvas) triggeruje
// crash telemetry Metal (RPS) na macOS 27 beta: -[__NSCFNumber length] przy
// commicie command buffera na oknach screenSaver-level. Shape/Circle idą
// inną ścieżką renderującą i nie odpalają tego buga.

struct WeatherFXView: View {
    let effect: WeatherEffect
    var windKmh: Double = 0

    var body: some View {
        ZStack {
            switch effect {
            case .clear:  ClearSkyFX()
            case .cloudy: CloudFX(windKmh: windKmh)
            case .fog:    FogFX()
            case .rain:   RainFX(intensity: 1.0, storm: false, windKmh: windKmh)
            case .snow:   SnowFX(windKmh: windKmh)
            case .storm:  RainFX(intensity: 1.4, storm: true, windKmh: windKmh)
            case .none:   EmptyView()
            }
            SeasonFX(effect: effect, windKmh: windKmh)
        }
    }
}

/// Pora roku jako osobna warstwa, niezależna od chmur: jesienią spadają liście, wiosną płatki
/// kwiatów — także w słoneczny dzień. Znikają tylko tam, gdzie fizycznie by nie pasowały
/// (deszcz, burza, śnieg). Półkula z szerokości geograficznej; wyłączane w Wygląd → Pory roku.
struct SeasonFX: View {
    let effect: WeatherEffect
    var windKmh: Double

    enum Season { case autumn, spring }

    static func current(date: Date = Date(), latitude: Double? = nil) -> Season? {
        var month = Calendar.current.component(.month, from: date)
        if let lat = latitude, lat < 0 { month = (month + 5) % 12 + 1 }        // southern hemisphere
        switch month {
        case 9...11: return .autumn
        case 4...5: return .spring
        default: return nil
        }
    }

    var body: some View {
        let d = UserDefaults.standard
        let lat = d.object(forKey: GlassKeys.lat) as? Double
        if d.string(forKey: "seasonFX") != "off",
           ![.rain, .storm, .snow, .none].contains(effect),
           let season = Self.current(latitude: lat) {
            ParticleFXRepresentable(kind: season == .autumn ? .leaves : .petals,
                                    windKmh: max(season == .autumn ? 5 : 3, windKmh),
                                    reportsSunOcclusion: effect == .clear)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

/// Słońce: ciepła poświata + obracające się promienie + odbłysk soczewki.
struct ClearSkyFX: View {
    var body: some View {
        SkyMetalRepresentable(mode: .sun)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

struct SunSkyRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> SunSkyNSView { SunSkyNSView() }
    func updateNSView(_ v: SunSkyNSView, context: Context) {}
}

/// Chmury: duże rozmyte plamy dryfujące w poziomie + przyciemnienie.
/// Chmury: przed-renderowane sprite'y cumulusów dryfujące z prędkością
/// zależną od wiatru (paralaksa). Każdy chmura to bitmapa z ~20 puffów
/// (radialne gradienty z clipem), rysowana JEDNYM blitem na klatkę —
/// zero gradientów per klatka, zero płaskich elips. Timer 6 fps, bitmapa
/// generowana raz na widok.
struct CloudFX: View {
    var windKmh: Double = 0
    var body: some View {
        SkyMetalRepresentable(mode: .clouds, windKmh: windKmh)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

struct CloudsNSViewRepresentable: NSViewRepresentable {
    var windKmh: Double = 0
    func makeNSView(context: Context) -> CloudsNSView {
        let v = CloudsNSView()
        v.windKmh = windKmh
        return v
    }
    func updateNSView(_ v: CloudsNSView, context: Context) {
        if v.windKmh != windKmh { v.windKmh = windKmh }
    }
}

/// AppKit: kłęby chmur jako przed-renderowane bitmapy. Każda chmura to osobna
/// CALayer z liniową animacją `position.x` — dryf liczy render server, więc
/// proces nie robi NIC w klatce (wcześniej: przerysowanie całej warstwy
/// w skali Retina 6×/s, ~40% czasu głównego wątku podczas przerwy).
final class CloudsNSView: NSView {
    private var built = false
    private var builtWidth: CGFloat = 0
    var windKmh: Double = 0 {
        didSet { if windKmh != oldValue { rebuild() } }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// Effect layers are decoration: they must never take mouse events from the
    /// break controls beneath/above them (SwiftUI's allowsHitTesting does not
    /// make an embedded NSView transparent to AppKit hit-testing).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        if !built || abs(bounds.width - builtWidth) > 1 { rebuild() }
    }

    private func rebuild() {
        guard bounds.width > 200, let root = layer else { return }
        built = true
        builtWidth = bounds.width
        root.sublayers?.forEach { $0.removeFromSuperlayer() }

        var seed: UInt64 = 0x243F6A8885A308D3
        func rnd() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 11) & 0xFFFFFF) / CGFloat(1 << 24)
        }
        // cztery warstwy: różne wysokości / rozmiary / gęstości
        let specs: [(w: CGFloat, h: CGFloat, y: CGFloat, puffs: Int, alpha: CGFloat)] = [
            (bounds.width * 0.62, 210, bounds.height * 0.04, 26, 0.16),
            (bounds.width * 0.44, 150, bounds.height * 0.16, 18, 0.13),
            (bounds.width * 0.34, 110, bounds.height * 0.27, 12, 0.10),
            (bounds.width * 0.24, 80, bounds.height * 0.36, 8, 0.08),
        ]
        for (i, spec) in specs.enumerated() {
            let img = Self.sprite(width: spec.w, height: spec.h,
                                   puffs: spec.puffs, alpha: spec.alpha, rnd: rnd)
            let phase = Double(rnd())
            let cloud = CALayer()
            cloud.contents = img
            cloud.contentsScale = 1
            cloud.bounds = CGRect(x: 0, y: 0, width: spec.w, height: spec.h)
            cloud.position = CGPoint(x: -spec.w / 2,
                                     y: bounds.height - spec.y - spec.h / 2)
            // Wiatr steruje prędkością dryfu (px/s); parallaksa: dalsze wolniejsze.
            let speed = (3.0 + windKmh * 0.22) * (1.0 + Double(i % 4) * 0.35)
            let distance = Double(bounds.width + spec.w)
            let drift = CABasicAnimation(keyPath: "position.x")
            drift.fromValue = 0.0
            drift.toValue = distance
            drift.duration = distance / speed
            drift.repeatCount = .infinity
            drift.timeOffset = phase * drift.duration
            drift.isAdditive = true
            drift.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 20, preferred: 15)
            cloud.add(drift, forKey: "drift")
            root.addSublayer(cloud)
        }
    }

    private static func sprite(width w: CGFloat, height h: CGFloat, puffs: Int,
                               alpha: CGFloat, rnd: () -> CGFloat) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        // Kłąb: puff skupiony wokół osi poziomej, na dole płaski, na górze kopulasty.
        for _ in 0..<puffs {
            let u = rnd()
            let px = w * (0.12 + 0.76 * u)
            let bulge = sin(u * .pi)            // brzegi cieńsze
            let py = h * (0.30 + 0.22 * rnd() + 0.10 * bulge)
            let pr = h * (0.18 + 0.30 * rnd())
            let a = alpha * (0.5 + 0.5 * bulge)
            let inner = CGColor(gray: 1.0, alpha: a)
            let outer = CGColor(gray: 1.0, alpha: 0.0)
            guard let grad = CGGradient(colorsSpace: cs,
                                        colors: [inner, outer] as CFArray,
                                        locations: [0, 1]) else { continue }
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: px - pr, y: py - pr, width: pr * 2, height: pr * 2))
            ctx.clip()
            ctx.drawRadialGradient(grad,
                                   startCenter: CGPoint(x: px, y: py), startRadius: 0,
                                   endCenter: CGPoint(x: px, y: py), endRadius: pr,
                                   options: [])
            ctx.restoreGState()
        }
        return ctx.makeImage()!
    }
}

/// Mgła: biała mgła + mocne spłycenie kontrastu.
/// Mgła: dwie przed-renderowane tekstury „kurzu mgły" dryfujące z różną
/// prędkością (paralaksa) + delikatna bielą zasłona. Jedna bitmapa = jeden
/// blit; timer 5 fps.
struct FogFX: View {
    var body: some View {
        SkyMetalRepresentable(mode: .fog)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

struct FogNSViewRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> FogNSView { FogNSView() }
    func updateNSView(_ v: FogNSView, context: Context) {}
}

/// Mgła na warstwach Core Animation: dwie tekstury (paralaksa) w połowie
/// rozdzielczości — i tak są miękkie — rozciągane na pełny ekran i dryfowane
/// animacją `position.x` (render server). Wcześniej: przerysowanie całego widoku
/// w skali Retina 5×/s + 2 bitmapy w pełnej rozdzielczości (~130 MB IOSurface),
/// a tekstura o wysokości 0,9 ekranu zostawiała twardą krawędź u góry.
final class FogNSView: NSView {
    private var builtSize = CGSize.zero
    private let speeds: [Double] = [2.5, 6.0]

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// Effect layers are decoration: they must never take mouse events from the
    /// break controls beneath/above them (SwiftUI's allowsHitTesting does not
    /// make an embedded NSView transparent to AppKit hit-testing).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        if bounds.width > 200, bounds.size != builtSize { build() }
    }

    private func build() {
        guard let root = layer else { return }
        builtSize = bounds.size
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        let w = bounds.width, h = bounds.height

        // Jasna zasłona — mocno subtelna, żeby ciemne UI nie siadało.
        let veil = CALayer()
        veil.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        veil.frame = bounds
        root.addSublayer(veil)

        var seed: UInt64 = 0x1234ABCD5678EF90
        func rnd() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 11) & 0xFFFFFF) / CGFloat(1 << 24)
        }
        let texW = w * 1.6
        for layerIndex in 0..<2 {
            guard let image = Self.makeTexture(width: Int(texW / 2), height: Int(h / 2),
                                               layer: layerIndex, rnd: rnd) else { continue }
            let distance = Double(texW)
            let phase = layerIndex == 0 ? 0.0 : 0.3
            // Dwie kopie obok siebie: dryf o `texW` zawija się bez luki.
            for copy in 0..<2 {
                let tile = CALayer()
                tile.contents = image
                tile.contentsGravity = .resize
                tile.anchorPoint = .zero
                tile.bounds = CGRect(x: 0, y: 0, width: texW, height: h)
                tile.position = CGPoint(x: -w * 0.3 - CGFloat(copy) * texW, y: 0)
                let drift = CABasicAnimation(keyPath: "position.x")
                drift.fromValue = 0.0
                drift.toValue = distance
                drift.duration = distance / speeds[layerIndex]
                drift.repeatCount = .infinity
                drift.isAdditive = true
                drift.timeOffset = phase * drift.duration
                drift.preferredFrameRateRange = CAFrameRateRange(minimum: 4, maximum: 12, preferred: 8)
                tile.add(drift, forKey: "drift")
                root.addSublayer(tile)
            }
        }
    }

    private static func makeTexture(width w: Int, height h: Int, layer: Int,
                                    rnd: () -> CGFloat) -> CGImage? {
        guard w > 8, h > 8 else { return nil }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let fw = CGFloat(w), fh = CGFloat(h)
        let puffs = layer == 0 ? 60 : 34
        let base = layer == 0 ? 0.045 : 0.06
        for _ in 0..<puffs {
            let px = rnd() * fw
            let py = fh * (0.1 + rnd() * 0.8)
            let pr = fh * (0.10 + rnd() * 0.26)
            guard let grad = CGGradient(colorsSpace: cs,
                                        colors: [CGColor(gray: 1.0, alpha: base),
                                                 CGColor(gray: 1.0, alpha: 0.0)] as CFArray,
                                        locations: [0, 1]) else { continue }
            // Three copies (±width) so the puffs wrap and the tile has no seam.
            for dx in [-fw, 0, fw] {
                ctx.saveGState()
                ctx.addEllipse(in: CGRect(x: px + dx - pr, y: py - pr, width: pr * 2, height: pr * 2))
                ctx.clip()
                ctx.drawRadialGradient(grad,
                                       startCenter: CGPoint(x: px + dx, y: py), startRadius: 0,
                                       endCenter: CGPoint(x: px + dx, y: py), endRadius: pr,
                                       options: [])
                ctx.restoreGState()
            }
        }
        return ctx.makeImage()
    }
}

/// Symulacja kroplówki na zaparowanej szybie — patrzmy NA szkło od wewnątrz.
/// Krople rosną z kondensacji, duża rusza w dół, zmywa trasę (szkło pod nią
/// robi się przezroczyste), po minięciu krawędzi ślad powoli zaparowuje z powrotem.
final class GlassDroplet {
    var x: Double
    var y: Double
    var r: Double            // promień kropli (px)
    var vy: Double = 0       // prędkość zsuwania
    var sliding = false
    var threshold: Double    // powyżej tego promienia kropla rusza
    var trailPoints: [CGPoint] = []
    var pathCooldown = 0.0
    init(x: Double, y: Double, r: Double, threshold: Double) {
        self.x = x; self.y = y; self.r = r; self.threshold = threshold
    }
}

/// Ślad po kropli — zaparowana szyba, którą kropla zmyła. life: 1 = świeży,
/// 0 = kondensacja wypełniła trasę z powrotem.
final class WipedTrail {
    var points: [CGPoint]
    var width: Double
    var life: Double
    init(points: [CGPoint], width: Double) {
        self.points = points; self.width = width; self.life = 1.0
    }
}

final class RainOnGlassSim {
    var drops: [GlassDroplet] = []
    var wiped: [WipedTrail] = []
    var lastT: TimeInterval?

    private func rnd(_ a: Double, _ b: Double) -> Double { Double.random(in: a...b) }

    func step(now: TimeInterval, size: CGSize, intensity: Double, windPx: Double) {
        let dt = min(0.1, max(0.001, lastT.map { now - $0 } ?? 1.0 / 24.0))
        lastT = now
        let w = Double(size.width), h = Double(size.height)
        guard w > 10, h > 10 else { return }

        // 1) Osadzanie: rzadko, ale DUŻE krople (soczewki, nie plamki).
        let spawnRate = 6.0 * intensity
        if Double.random(in: 0...1) < spawnRate * dt {
            for _ in 0..<Int(1 + rnd(0, 2)) where drops.count < 160 {
                let big = Double.random(in: 0...1) < 0.10      // rzadka duża soczewka
                let r = big ? rnd(9.0, 15.0) : rnd(2.0, 7.5)
                drops.append(GlassDroplet(x: rnd(0, w), y: rnd(0, h * 0.8), r: r,
                                          threshold: big ? rnd(12.0, 18.0) : rnd(5.5, 9.5)))
            }
        }

        // 2) Kondensacja: krople rosną.
        for d in drops where !d.sliding {
            d.r += dt * rnd(0.35, 1.20) * intensity
        }

        // 3) Powyżej progu — prosty spływ w dół (plus dryf od wiatru).
        var survivors: [GlassDroplet] = []
        for d in drops {
            if !d.sliding, d.r >= d.threshold { d.sliding = true }
            if d.sliding {
                let excess = max(0, d.r - d.threshold)
                let target = 12.0 + excess * 20.0
                d.vy = min(d.vy + (target - d.vy) * dt * 1.2, 220)
                if Double.random(in: 0...1) < 0.008 { d.vy *= 0.2 }     // zaczepiła
                d.y += d.vy * dt
                // Prawdziwa kropla spływa PROSTO w dół. Żadnego sinusoidalnego
                // wężykowania (robiło "snakey"). Tylko sporadyczny mikropodskok,
                // gdy trafi na nierówność szkła, oraz dryf od wiatru.
                if Double.random(in: 0...1) < 0.012 { d.x += rnd(-1.2, 1.2) }
                d.x += windPx * dt * (0.25 + d.vy / 200)
                // zapis trasy (do zmycia pary) — co ~40 ms
                d.pathCooldown -= dt
                if d.pathCooldown <= 0 {
                    d.trailPoints.append(CGPoint(x: d.x, y: d.y))
                    if d.trailPoints.count > 90 { d.trailPoints.removeFirst() }
                    d.pathCooldown = 0.04
                }
                // wchłanianie spotkanych mniejszych kropli
                for o in drops where o !== d && !o.sliding {
                    let dx = o.x - d.x, dy = o.y - d.y
                    if dx * dx + dy * dy < pow(d.r + o.r, 2) {
                        d.r = sqrt(d.r * d.r + o.r * o.r)
                        o.r = -1
                        d.vy = max(d.vy, 16)
                    }
                }
                if d.y - d.r > h || d.r < 0.8 {
                    // zjechała — trasa zostaje i powoli zaparowuje z powrotem
                    if d.trailPoints.count > 2, wiped.count < 45 {
                        wiped.append(WipedTrail(points: d.trailPoints,
                                               width: max(1.5, d.r * 1.6)))
                    }
                    d.r = -1
                }
            }
            if d.r > 0 { survivors.append(d) }
        }
        drops = survivors.filter { $0.r > 0 }

        // 4) Ślady: kondensacja powraca (life → 0), potem usuwamy.
        for i in wiped.indices { wiped[i].life -= dt * 0.10 }
        wiped.removeAll { $0.life <= 0 }
    }
}

// MARK: - Deszcz na szybie (podejście raindropfx, CoreGraphics w NSView)
//
// Scena rysowana w bitmapie: tekstura kondensacji (placki mgły + tysiące
// mikro-kropelek) → trasy spływających kropel wytrawiane blendem .clear
// (siła = life, więc para powoli wraca) → kropla jako soczewka: gradient
// refrakcji z offsetem, ciemny rim, specular highlight. Zero Canvas i
// ImageRenderer — oba crashują RPS/Metal na macOS 27 beta; NSView draw(_:)
// to standardowa ścieżka AppKit.

/// Cache tekstury kondensacji + generowanie bitmy pary z wytrawionymi trasami.
@MainActor
final class FogTextureCache {
    private var specks: CGImage?
    private var specksSize = CGSize.zero
    private var fogCtx: CGContext?
    private var fogCtxSize = CGSize.zero

    /// Zaparowanie rysowane BEZPOŚREDNIO w kontekście docelowym:
    ///cached bitmapa specks + trasy wytrawiane .destinationOut + residual
    ///bieli. Dawniej budowaliśmy offscreen-bitmapę co klatkę (6K RGBA,
    ///85 MB @20 fps) — na macOS 27 beta odpalało to crash telemetry Metal
    ///(-[__NSCFNumber length]) przy commicie command buffera. Teraz jeden
    ///blit cache'owanej tekstury + cienkie smugi na wierzchu.
    func fogDirect(into cg: CGContext, sim: RainOnGlassSim, size: CGSize, fog: Double) {
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        guard w > 20, h > 20 else { return }
        // Bramki testowe (intermezzo://debug/flag) — diagnostyka crasha macOS 27 beta.
        let noTrails = UserDefaults.standard.integer(forKey: "fxNoTrails") != 0
        if UserDefaults.standard.integer(forKey: "fxNoFog") != 0 { return }
        if specksSize != size || specks == nil {
            specks = Self.makeSpecks(w: w, h: h)
            specksSize = size
        }
        guard let sp = specks else { return }
        cg.saveGState()
        if UserDefaults.standard.integer(forKey: "fxNoImg") == 0 {
            cg.setAlpha(CGFloat(min(1.0, max(0.0, fog / 0.26))))
            cg.draw(sp, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
            cg.setAlpha(1)
        }
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        func stroke(_ points: [CGPoint], _ width: CGFloat, _ strength: CGFloat) {
            guard points.count > 1, width > 0.5, abs(strength) > 0.02 else { return }
            if strength > 0 {
                cg.setBlendMode(.destinationOut)
                cg.setStrokeColor(CGColor(gray: 0, alpha: min(1.0, strength)))
            } else {
                // residual wody w kanale: gęsta para wraca na dno wytrawionej smugi
                cg.setBlendMode(.normal)
                cg.setStrokeColor(CGColor(gray: 1, alpha: min(1.0, -strength)))
            }
            cg.setLineWidth(width)
            cg.move(to: CGPoint(x: points[0].x, y: CGFloat(h) - points[0].y))
            for pt in points.dropFirst() {
                cg.addLine(to: CGPoint(x: pt.x, y: CGFloat(h) - pt.y))
            }
            cg.strokePath()
        }
        func softChannel(_ points: [CGPoint], _ width: CGFloat, _ strength: CGFloat) {
            guard strength > 0.02 else { return }
            stroke(points, width * 1.4, strength * 0.35)
            stroke(points, width * 1.0, strength * 0.65)
            stroke(points, width * 0.6, strength * 1.0)
        }
        if !noTrails {
            for d in sim.drops where d.sliding {
                softChannel(d.trailPoints, CGFloat(d.r) * 1.5, 1.0)
            }
            for tr in sim.wiped {
                softChannel(tr.points, CGFloat(tr.width), CGFloat(tr.life))
            }
        }
        cg.restoreGState()
    }

    private static func makeSpecks(w: Int, h: Int) -> CGImage? {
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // 1) Ciągły mleczny film — para to nie kropeczki, to zasłona
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.24))
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        // 2) Miękkie gradientowe płacki (nierównomierne skroplenie)
        for _ in 0..<26 {
            let r = CGFloat.random(in: 40...140)
            let x = CGFloat.random(in: 0...CGFloat(w))
            let y = CGFloat.random(in: 0...CGFloat(h))
            let a = CGFloat.random(in: 0.04...0.09)
            if let g = CGGradient(colorsSpace: cs,
                                  colors: [CGColor(gray: 1, alpha: a),
                                         CGColor(gray: 1, alpha: 0)] as CFArray,
                                  locations: [0, 1]) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0,
                                       endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
            }
        }
        // 3) Mikro-kropelki — gęsto, to one dają ziarno kondensacji
        let n = max(3000, w * h / 2200)
        for _ in 0..<n {
            let r = CGFloat.random(in: 0.4...2.2)
            let x = CGFloat.random(in: 0...CGFloat(w))
            let y = CGFloat.random(in: 0...CGFloat(h))
            ctx.setFillColor(CGColor(gray: 1, alpha: CGFloat.random(in: 0.06...0.22)))
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        return ctx.makeImage()
    }
}

// MARK: - Rain rendering (AppKit, dirty-rect incremental)
//
// macOS 27 beta (Tahoe-next, AGXMetalG17X) crashuje SIGABRT
// (-[__NSCFNumber length] w telemetry Metal) gdy pełnoekranowa zawartość
// jest przerysowywana w ~12 fps na oknie level=.screenSaver — dowiedzione
// empirycznie (repro: gradient fullscreen -> crash < 60 s; dirty-rect ->
// stabilność). Dlatego deszcz NIE używa TimelineView/pełnych invalidacji:
// NSView napędza własny timer 10 fps i unieważnia TYLKO obszary, w których
// coś się zmieniło (nowe segmenty tras + kadry kropli). Para w wytrawionych
// trasach „zastyga" — tak działa w rzeczywistości (mokre rowki).

/// Pełna scena deszczu na szybie. Współdzielona przez live i snapshot.
@MainActor
func drawRainScene(cg: CGContext, size: CGSize, sim: RainOnGlassSim,
                  cache: FogTextureCache, fog: Double, drawBackground: Bool) {
    if drawBackground, let cs = CGColorSpace(name: CGColorSpace.sRGB),
       let bg = CGGradient(colorsSpace: cs,
                           colors: [CGColor(red: 0.42, green: 0.46, blue: 0.52, alpha: 1),
                                    CGColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 1)] as CFArray,
                           locations: [0, 1]) {
        cg.drawLinearGradient(bg, start: CGPoint(x: 0, y: size.height),
                              end: CGPoint(x: 0, y: 0), options: [])
        // ciepłe „latarnie" za szybą — dają kroplom co łamać
        for (gx, gy, gr, ga) in [(0.18, 0.22, 0.16, 0.14), (0.78, 0.14, 0.12, 0.11),
                                   (0.55, 0.30, 0.09, 0.08)] {
            let cx = CGFloat(gx) * size.width, cy = CGFloat(gy) * size.height
            let rr = CGFloat(gr) * max(size.width, size.height)
            if let lamp = CGGradient(colorsSpace: cs,
                                     colors: [CGColor(red: 1.0, green: 0.82, blue: 0.55, alpha: CGFloat(ga)),
                                            CGColor(red: 1.0, green: 0.82, blue: 0.55, alpha: 0)] as CFArray,
                                     locations: [0, 1]) {
                cg.drawRadialGradient(lamp, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                                      endCenter: CGPoint(x: cx, y: cy), endRadius: rr, options: [])
            }
        }
    }
    cache.fogDirect(into: cg, sim: sim, size: size, fog: fog)
    drawLensDrops(cg: cg, size: size, sim: sim)
    // błyskawica burzy (ryta w tej samej warstwie, ~2 pełne invalidacje
    // na błysk zamiast pełnego odświeżania co klatkę)
    // (błysk burzy maluje widok, nie symulacja)
}

/// Pojedyncza kropla: refrakcja (gradient z offsetem), ciemna obwódka, rim,
/// specular highlight. r < 2.4 rysowana jako proste jasne ziarno.
private func drawLensDrops(cg: CGContext, size: CGSize, sim: RainOnGlassSim) {
    guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return }
    for d in sim.drops {
        let r = CGFloat(d.r)
        guard r >= 0.8 else { continue }
        let c = CGPoint(x: CGFloat(d.x), y: size.height - CGFloat(d.y))
        let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        if r > 2.4 {
            cg.saveGState()
            // spływające krople: kształt łzy (ciało + zwężany ogon w górę)
            let body = CGMutablePath()
            if d.sliding {
                let tailH = r * 1.6
                body.move(to: CGPoint(x: c.x, y: c.y + r))
                body.addQuadCurve(to: CGPoint(x: c.x, y: c.y - tailH),
                                  control: CGPoint(x: c.x + r * 0.52, y: c.y - tailH * 0.35))
                body.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r),
                                  control: CGPoint(x: c.x - r * 0.52, y: c.y - tailH * 0.35))
            } else {
                body.addEllipse(in: rect)
            }
            cg.addPath(body)
            cg.clip()
            // interior: refrakcja skupia światło
            if let fill = CGGradient(colorsSpace: cs,
                                     colors: [CGColor(gray: 1, alpha: 0.22),
                                            CGColor(gray: 1, alpha: 0.03)] as CFArray,
                                     locations: [0, 1]) {
                cg.drawRadialGradient(fill,
                                      startCenter: CGPoint(x: c.x - r * 0.30, y: c.y + r * 0.24),
                                      startRadius: 0, endCenter: c, endRadius: r, options: [])
            }
            // fresnel: ciemna obwódka soczewki
            if let rim = CGGradient(colorsSpace: cs,
                                    colors: [CGColor(gray: 0, alpha: 0),
                                           CGColor(gray: 0.01, alpha: 0.26)] as CFArray,
                                    locations: [0.72, 1]) {
                cg.drawRadialGradient(rim, startCenter: c, startRadius: 0,
                                      endCenter: c, endRadius: r, options: [])
            }
            // specular: miękka iskra + drobna wtórna
            if let spec = CGGradient(colorsSpace: cs,
                                     colors: [CGColor(gray: 1, alpha: 0.62),
                                            CGColor(gray: 1, alpha: 0)] as CFArray,
                                     locations: [0, 1]) {
                let hx = c.x - r * 0.30, hy = c.y + r * 0.26
                cg.drawRadialGradient(spec, startCenter: CGPoint(x: hx, y: hy), startRadius: 0,
                                      endCenter: CGPoint(x: hx, y: hy), endRadius: r * 0.34,
                                      options: [])
            }
            if let spec2 = CGGradient(colorsSpace: cs,
                                      colors: [CGColor(gray: 1, alpha: 0.28),
                                             CGColor(gray: 1, alpha: 0)] as CFArray,
                                      locations: [0, 1]) {
                let qx = c.x + r * 0.34, qy = c.y - r * 0.22
                cg.drawRadialGradient(spec2, startCenter: CGPoint(x: qx, y: qy), startRadius: 0,
                                      endCenter: CGPoint(x: qx, y: qy), endRadius: r * 0.2,
                                      options: [])
            }
            cg.restoreGState()
        } else {
            cg.setFillColor(CGColor(gray: 1, alpha: 0.12))
            cg.fillEllipse(in: rect)
        }
    }
}

/// Widok deszczu z WŁASNYM timerem imałoobszarową invalidacją (patrz komentarz góry).
@MainActor
/// Deszcz na szybie (raindropfx): ZAPAROWANA szyba, duże soczewkowe krople
/// zsuwają się w dół WYTRAWIAJAC trasę. Bez TimelineView — patrz wyżej.
struct RainFX: View {
    let intensity: Double
    let storm: Bool
    var windKmh: Double = 0

    var body: some View {
        Group {
            if UserDefaults.standard.string(forKey: "rainEngine") == "ca" {
                RainGlassCARepresentable(intensity: intensity, storm: storm, windKmh: windKmh)
            } else {
                RainMetalRepresentable(intensity: intensity, storm: storm, windKmh: windKmh)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Śnieg: wirujące płatki; dryf poziomy couplingowany z wiatrem Open-Meteo.
struct SnowFX: View {
    var windKmh: Double = 0
    var body: some View {
        SnowCARepresentable(windKmh: windKmh)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

// MARK: - Debug: headless snapshot efektów (CoreGraphics na CPU — zero Metal)
// intermezzo://debug/snapshot?kind=rain|storm|leaf|snow&fog=0.26&wind=20&out=/path.png
// ImageRenderer crashuje na macOS 27 (ta sama ścieżka RPS/Metal co Canvas), więc
// scenę rysujemy z DANYCH symulacji przez CoreGraphics. Tylko do weryfikacji.

@MainActor
func renderWeatherSnapshot(kind: String, outPath: String,
                           size: CGSize = CGSize(width: 1600, height: 900),
                           fogOverride: Double? = nil, windOverride: Double? = nil) -> Bool {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let cg = CGContext(data: nil,
                              width: Int(size.width), height: Int(size.height),
                              bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }

    // Tło za szybą (deszcz rysuje swoje w drawRainScene)
    if kind != "rain" && kind != "storm" {
        cg.setFillColor(CGColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1))
        cg.fill(CGRect(origin: .zero, size: size))
    }

    let wind = windOverride ?? 20
    switch kind {
    case "rain", "storm":
        let sim = RainOnGlassSim()
        var t = Date.timeIntervalSinceReferenceDate
        let intensity = kind == "storm" ? 1.4 : 1.0
        for _ in 0..<700 {          // ~29 s symulacji — trasy muszą zdążyć powstać
            t += 1.0 / 24.0
            sim.step(now: t, size: size, intensity: intensity, windPx: wind * 0.6)
        }
        let cache = FogTextureCache()
        drawRainScene(cg: cg, size: size, sim: sim, cache: cache,
                      fog: fogOverride ?? 0.26, drawBackground: true)
    case "leaf":
        drawLeavesCG(cg: cg, size: size, wind: wind, t: Date.timeIntervalSinceReferenceDate)
    case "snow":
        drawSnowCG(cg: cg, size: size, wind: wind, t: Date.timeIntervalSinceReferenceDate)
    default:
        break
    }

    guard let img = cg.makeImage() else { return false }
    let rep = NSBitmapImageRep(cgImage: img)
    guard let png = rep.representation(using: .png, properties: [:]) else { return false }
    do { try png.write(to: URL(fileURLWithPath: outPath)); return true } catch { return false }
}

private func drawLeavesCG(cg: CGContext, size: CGSize, wind: Double, t: TimeInterval) {
    let palette: [(CGFloat, CGFloat, CGFloat)] = [
        (0.76, 0.44, 0.16), (0.62, 0.32, 0.10), (0.85, 0.58, 0.13),
        (0.55, 0.22, 0.10), (0.70, 0.48, 0.20)]
    let count = min(36, Int(6 + wind * 0.8))
    let fall = 22.0 + wind * 1.1
    for i in 0..<count {
        let seed = Double(i) * 71.3
        let speed = 0.55 + (sin(seed) * 0.5 + 0.5) * 0.9
        let x = ((sin(seed * 1.7) * 0.5 + 0.5) * size.width
                + t * wind * 1.6 * speed
                + sin(t * 1.25 + seed) * (8 + wind * 0.9))
            .truncatingRemainder(dividingBy: size.width + 60) - 30
        let y = (t * fall * speed + seed * 57.0)
            .truncatingRemainder(dividingBy: size.height + 60) - 30
        let lw = 9.0 + (sin(seed * 2.1) * 0.5 + 0.5) * 31.0
        let lh = lw * 0.72
        let col = palette[i % palette.count]
        cg.saveGState()
        cg.translateBy(x: CGFloat(x) + lw / 2, y: CGFloat(size.height - y) - lh / 2)
        cg.rotate(by: CGFloat((t * (35 + wind * 3.5) + seed * 57) * .pi / 180))
        cg.setFillColor(CGColor(red: col.0, green: col.1, blue: col.2, alpha: 0.85))
        let leaf = CGMutablePath()
        leaf.move(to: CGPoint(x: 0, y: lh / 2))
        leaf.addQuadCurve(to: CGPoint(x: 0, y: -lh / 2), control: CGPoint(x: lw * 0.54, y: 0))
        leaf.addQuadCurve(to: CGPoint(x: 0, y: lh / 2), control: CGPoint(x: -lw * 0.54, y: 0))
        cg.addPath(leaf)
        cg.fillPath()
        cg.restoreGState()
    }
}

private func drawSnowCG(cg: CGContext, size: CGSize, wind: Double, t: TimeInterval) {
    for i in 0..<70 {
        let seed = Double(i) * 53.7
        let x = ((sin(seed) * 0.5 + 0.5) * size.width
                + sin(t * 0.8 + seed) * 18
                + t * wind * 1.2)
            .truncatingRemainder(dividingBy: size.width)
        let y = (t * (28.0 + (sin(seed * 2.3) * 0.5 + 0.5) * 24.0) + seed * 97.0)
            .truncatingRemainder(dividingBy: size.height + 20) - 10
        let r = CGFloat(1.5 + (sin(seed * 1.1) * 0.5 + 0.5) * 2.0)
        cg.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
        cg.fillEllipse(in: CGRect(x: CGFloat(x) - r, y: CGFloat(size.height - y) - r,
                                   width: r * 2, height: r * 2))
    }
}

/// Jesienne liście na szybie/przed szybem: im mocniejszy wiatr, tym więcej liści,
/// szybszy opad, mocniejsze kołysanie i podmuchi (składowa sin z amplitudą od wiatru).
struct LeafFX: View {
    var windKmh: Double = 0
    var body: some View {
        ParticleFXRepresentable(kind: .leaves, windKmh: max(0, windKmh))
            .allowsHitTesting(false)
    }
}

// MARK: - Liście (warstwy z animacją, bez rysowania w klatce)

struct ParticleFXRepresentable: NSViewRepresentable {
    let kind: ParticleNSView.Kind
    var windKmh: Double
    var reportsSunOcclusion = false
    func makeNSView(context: Context) -> ParticleNSView {
        let v = ParticleNSView(kind: kind)
        v.reportsSunOcclusion = reportsSunOcclusion
        v.windKmh = windKmh
        return v
    }
    func updateNSView(_ v: ParticleNSView, context: Context) {
        if v.windKmh != windKmh { v.windKmh = windKmh }
    }
}

final class ParticleNSView: NSView {
    enum Kind { case leaves, petals }

    private let kind: Kind
    private var configuredSize = CGSize.zero
    /// When true the view measures how much of the sun the falling leaves cover (drives flare flicker).
    var reportsSunOcclusion = false
    private var occlusionLink: CADisplayLink?
    var windKmh: Double = 0 {
        didSet { if windKmh != oldValue { configure(force: true) } }
    }

    private static let leafPalette: [(CGFloat, CGFloat, CGFloat)] = [
        (0.76, 0.44, 0.16), (0.62, 0.32, 0.10), (0.85, 0.58, 0.13),
        (0.55, 0.22, 0.10), (0.70, 0.48, 0.20)]
    private static let leafImages: [CGImage] = leafPalette.compactMap { makeLeaf($0) }
    private static let petalImages: [CGImage] = [(1.0, 0.86, 0.90), (1.0, 0.93, 0.95), (0.98, 0.78, 0.86)].compactMap { makePetal($0) }

    /// Soft petal: rounded body with a small notch at the tip and a lighter centre.
    private static func makePetal(_ c: (CGFloat, CGFloat, CGFloat)) -> CGImage? {
        let w = 64, h = 52
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 32, y: 2))
        p.addCurve(to: CGPoint(x: 60, y: 30), control1: CGPoint(x: 54, y: 2), control2: CGPoint(x: 64, y: 20))
        p.addCurve(to: CGPoint(x: 36, y: 50), control1: CGPoint(x: 56, y: 44), control2: CGPoint(x: 46, y: 52))
        p.addQuadCurve(to: CGPoint(x: 28, y: 50), control: CGPoint(x: 32, y: 44))
        p.addCurve(to: CGPoint(x: 4, y: 30), control1: CGPoint(x: 18, y: 52), control2: CGPoint(x: 8, y: 44))
        p.addCurve(to: CGPoint(x: 32, y: 2), control1: CGPoint(x: 0, y: 20), control2: CGPoint(x: 10, y: 2))
        ctx.addPath(p)
        ctx.clip()
        if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [CGColor(red: min(1, c.0 + 0.05), green: min(1, c.1 + 0.08), blue: min(1, c.2 + 0.06), alpha: 1),
                                       CGColor(red: c.0, green: c.1 * 0.88, blue: c.2 * 0.92, alpha: 1)] as CFArray,
                              locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 30), startRadius: 0,
                                   endCenter: CGPoint(x: 32, y: 30), endRadius: 34, options: [])
        }
        return ctx.makeImage()
    }

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        occlusionLink?.invalidate(); occlusionLink = nil
        guard window != nil, reportsSunOcclusion else { return }
        let l = displayLink(target: self, selector: #selector(measureOcclusion(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 24, preferred: 20)
        l.add(to: .main, forMode: .common)
        occlusionLink = l
    }

    /// Fraction of the sun's disc hidden by leaves right now (read from the animated presentation layers).
    @objc private func measureOcclusion(_ link: CADisplayLink) {
        guard window?.isVisible == true, let root = layer, bounds.width > 100 else { return }
        let sun = SunLightState.sunUV
        let sx = CGFloat(sun.x) * bounds.width, sy = (1 - CGFloat(sun.y)) * bounds.height     // layers are y-up
        var covered: CGFloat = 0
        for sub in root.sublayers ?? [] {
            let pl = sub.presentation() ?? sub
            let reach = max(pl.bounds.width, pl.bounds.height) * 0.55 + 14
            let d = hypot(pl.position.x - sx, pl.position.y - sy)
            if d < reach { covered += (1 - d / reach) * 0.9 }
        }
        SunLightState.occlusion = Float(min(1, covered))
    }

    override func layout() {
        super.layout()
        configure()
    }

    private func configure(force: Bool = false) {
        guard bounds.width > 100, bounds.height > 100, let root = layer else { return }
        guard force || bounds.size != configuredSize else { return }
        configuredSize = bounds.size
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        let wind = max(0, windKmh)
        var rng = SystemRandomNumberGenerator()
        if kind == .petals {
            for _ in 0..<min(46, Int(14 + wind * 1.1)) {
                let size = CGFloat.random(in: 6...15)
                root.addSublayer(FallingSprites.layer(.init(
                    image: Self.petalImages.randomElement()!,
                    size: CGSize(width: size, height: size * 0.8),
                    speed: CGFloat((16 + wind * 0.9) * Double.random(in: 0.6...1.4)),
                    drift: CGFloat(wind * 1.3) * CGFloat.random(in: 0.5...1.3),
                    alpha: Float.random(in: 0.7...0.92),
                    spin: CGFloat.random(in: 40...150) * (Bool.random() ? 1 : -1),
                    sway: CGFloat(18 + wind)), in: bounds, rng: &rng))
            }
            return
        }
        let count = min(40, Int(7 + wind * 0.9))
        for _ in 0..<count {
            let size = CGFloat.random(in: 13...48)
            let speed = CGFloat((22 + wind * 1.1) * Double.random(in: 0.55...1.45))
            let spec = FallingSprites.Spec(
                image: Self.leafImages.randomElement()!,
                size: CGSize(width: size, height: size * 0.72),
                speed: speed, drift: CGFloat(wind * 1.6) * CGFloat.random(in: 0.6...1.4),
                alpha: Float.random(in: 0.75...0.9),
                spin: CGFloat((35 + wind * 3.5)) * (Bool.random() ? 1 : -1) * CGFloat.random(in: 0.5...1.2),
                sway: CGFloat(8 + wind * 0.9))
            root.addSublayer(FallingSprites.layer(spec, in: bounds, rng: &rng))
        }
    }

    private static func makeLeaf(_ c: (CGFloat, CGFloat, CGFloat)) -> CGImage? {
        let w = 80, h = 58
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let fw = CGFloat(w), fh = CGFloat(h)
        let leaf = CGMutablePath()
        leaf.move(to: CGPoint(x: fw / 2, y: fh))
        leaf.addQuadCurve(to: CGPoint(x: fw / 2, y: 0), control: CGPoint(x: fw * 1.08, y: fh / 2))
        leaf.addQuadCurve(to: CGPoint(x: fw / 2, y: fh), control: CGPoint(x: -fw * 0.08, y: fh / 2))
        // soft warm glow behind the leaf — sunlight passing through it (backlit look)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 7, color: CGColor(red: 1.0, green: 0.72, blue: 0.30, alpha: 0.55))
        ctx.setFillColor(CGColor(red: c.0, green: c.1, blue: c.2, alpha: 1))
        ctx.addPath(leaf); ctx.fillPath()
        ctx.restoreGState()
        // translucent body: brighter toward the tip, deeper toward the stem
        ctx.saveGState()
        ctx.addPath(leaf); ctx.clip()
        if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [CGColor(red: min(1, c.0 * 1.25 + 0.10), green: min(1, c.1 * 1.25 + 0.08), blue: min(1, c.2 * 1.2 + 0.03), alpha: 1),
                                       CGColor(red: c.0 * 0.7, green: c.1 * 0.7, blue: c.2 * 0.7, alpha: 1)] as CFArray,
                              locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: fw / 2, y: fh), end: CGPoint(x: fw / 2, y: 0), options: [])
        }
        ctx.restoreGState()
        // central vein
        ctx.setStrokeColor(CGColor(red: c.0 * 0.6, green: c.1 * 0.6, blue: c.2 * 0.6, alpha: 0.8))
        ctx.setLineWidth(1.6)
        ctx.move(to: CGPoint(x: fw / 2, y: 2)); ctx.addLine(to: CGPoint(x: fw / 2, y: fh - 2))
        ctx.strokePath()
        return ctx.makeImage()
    }
}
