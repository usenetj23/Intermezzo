import SwiftUI
import AppKit
import IntermezzoKit

/// The map read once from the app's Resources, with the bounding box of every path so that paths outside the
/// window are skipped while drawing.
struct PreparedMap {
    struct Path {
        let points: [GeoPoint]
        let minLat: Double, maxLat: Double, minLon: Double, maxLon: Double

        init(_ points: [GeoPoint]) {
            self.points = points
            minLat = points.map(\.latitude).min() ?? 0
            maxLat = points.map(\.latitude).max() ?? 0
            minLon = points.map(\.longitude).min() ?? 0
            maxLon = points.map(\.longitude).max() ?? 0
        }
    }

    let land: [Path]
    let borders: [Path]
    let cities: [WorldMap.City]
    let isAvailable: Bool

    static let shared = load()

    private static func load() -> PreparedMap {
        guard let url = Bundle.main.url(forResource: "worldmap", withExtension: "bin"),
              let data = try? Data(contentsOf: url), let map = WorldMap.decode(data) else {
            return PreparedMap(land: [], borders: [], cities: [], isAvailable: false)
        }
        return PreparedMap(land: map.land.map(Path.init), borders: map.borders.map(Path.init),
                           cities: map.cities.sorted { $0.population > $1.population }, isAvailable: true)
    }
}

private struct MapPalette {
    let ocean: Color, land: Color, border: Color, text: Color, night: Color, outside: Color
    /// Strength of the night colour for each `DayNight` level.
    let shade: [Double]

    static func of(_ scheme: ColorScheme) -> MapPalette {
        scheme == .dark
            ? MapPalette(ocean: Color(red: 0.11, green: 0.16, blue: 0.27), land: Color(red: 0.23, green: 0.26, blue: 0.34),
                         border: Color(red: 0.42, green: 0.46, blue: 0.56), text: Color(red: 0.91, green: 0.93, blue: 0.97),
                         night: Color(red: 0.02, green: 0.03, blue: 0.10), outside: .black, shade: [0, 0.18, 0.32, 0.46, 0.6])
            : MapPalette(ocean: Color(red: 0.81, green: 0.88, blue: 0.97), land: Color(red: 0.96, green: 0.97, blue: 0.98),
                         border: Color(red: 0.50, green: 0.55, blue: 0.66), text: Color(red: 0.11, green: 0.15, blue: 0.25),
                         night: Color(red: 0.12, green: 0.16, blue: 0.40), outside: .gray, shade: [0, 0.16, 0.30, 0.44, 0.58])
    }
}

/// Hands mouse-wheel and trackpad scrolling over the map to the view, which has no scroll event of its own.
private final class ScrollBridge {
    var hover: CGPoint?
    var handle: ((CGFloat, CGFloat, Bool, CGPoint) -> Void)?
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let hover = self.hover, let handle = self.handle else { return event }
            handle(event.scrollingDeltaX, event.scrollingDeltaY, event.hasPreciseScrollingDeltas, hover)
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit { stop() }
}

/// The shading is rebuilt only when the view, its size or the minute changes.
private final class ShadeCache {
    var key = ""
    var image: CGImage?
}

private struct DragStart {
    let viewport: MapViewport
    let movesPin: Bool
}

/// The last click on the map and the pin before it: a double click zooms, so its clicks must not move the pin.
private struct ClickMemory {
    let time: Date
    let pinBefore: GeoPoint?
}

/// A zoomable world map with the day and night shading, the larger cities' names and the pin.
struct LocationMapView: View {
    @Binding var viewport: MapViewport
    @Binding var pin: GeoPoint?
    @Binding var size: CGSize

    @Environment(\.colorScheme) private var scheme
    @State private var dragStart: DragStart?
    @State private var pinchStart: MapViewport?
    @State private var lastClick: ClickMemory?
    @State private var bridge = ScrollBridge()
    @State private var shadeCache = ShadeCache()

    private let map = PreparedMap.shared
    private static let pinGrabDistance = 14.0
    private static let shadeStep = 4
    private static var labelSizes: [String: CGSize] = [:]

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                Canvas { context, canvasSize in draw(context, canvasSize, timeline.date) }
            }
            .contentShape(Rectangle())
            .gesture(drag(proxy.size))
            .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { doubleClick(at: $0.location, in: proxy.size) })
            .simultaneousGesture(pinch(proxy.size))
            .onContinuousHover { phase in
                if case .active(let point) = phase { bridge.hover = point } else { bridge.hover = nil }
            }
            .overlay(alignment: .topTrailing) { zoomButtons(proxy.size) }
            .onAppear {
                size = proxy.size
                bridge.handle = { dx, dy, precise, at in
                    if precise {
                        viewport = viewport.panned(by: CGSize(width: dx, height: dy), in: size)
                    } else {
                        viewport = viewport.zoomed(by: exp(Double(dy) * 0.15), around: at, in: size)
                    }
                }
                bridge.start()
            }
            .onDisappear { bridge.stop() }
            .onChange(of: proxy.size) { _, new in size = new }
        }
    }

    // MARK: Gestures

    private func drag(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStart == nil {
                    let nearPin = pin.map { hypot(pinPoint($0, size).x - value.startLocation.x,
                                                  pinPoint($0, size).y - value.startLocation.y) < Self.pinGrabDistance } ?? false
                    dragStart = DragStart(viewport: viewport, movesPin: nearPin)
                }
                guard let start = dragStart else { return }
                if start.movesPin {
                    pin = viewport.geo(at: value.location, in: size)
                } else {
                    viewport = start.viewport.panned(by: value.translation, in: size)
                }
            }
            .onEnded { value in
                defer { dragStart = nil }
                guard let start = dragStart, !start.movesPin,
                      hypot(value.translation.width, value.translation.height) < 3 else { return }
                click(at: value.startLocation, in: size)
            }
    }

    /// A click puts the pin down. If it turns out to be the first half of a double click, `doubleClick` takes it back.
    private func click(at point: CGPoint, in size: CGSize) {
        let now = Date()
        let repeated = lastClick.map { now.timeIntervalSince($0.time) < NSEvent.doubleClickInterval } ?? false
        lastClick = ClickMemory(time: now, pinBefore: repeated ? lastClick?.pinBefore : pin)
        pin = viewport.geo(at: point, in: size)
    }

    private func doubleClick(at point: CGPoint, in size: CGSize) {
        if let memory = lastClick { pin = memory.pinBefore }
        lastClick = nil
        zoom(by: 2, at: point, in: size)
    }

    /// Where the pin is on screen, in whichever copy of the world lies nearest the middle of the view.
    private func pinPoint(_ pin: GeoPoint, _ size: CGSize) -> CGPoint {
        let shift = [0.0, 360, -360].min {
            abs(pin.longitude + $0 - viewport.center.longitude) < abs(pin.longitude + $1 - viewport.center.longitude)
        } ?? 0
        return viewport.point(for: GeoPoint(latitude: pin.latitude, longitude: pin.longitude + shift), in: size)
    }

    private func pinch(_ size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? viewport
                pinchStart = start
                viewport = start.zoomed(by: Double(value.magnification), around: value.startLocation, in: size)
            }
            .onEnded { _ in pinchStart = nil }
    }

    private func zoom(by factor: Double, at point: CGPoint, in size: CGSize) {
        viewport = viewport.zoomed(by: factor, around: point, in: size)
    }

    private func zoomButtons(_ size: CGSize) -> some View {
        VStack(spacing: 4) {
            Button { zoom(by: 2, at: CGPoint(x: size.width / 2, y: size.height / 2), in: size) } label: {
                Image(systemName: "plus").frame(width: 16, height: 16)
            }
            .accessibilityLabel(Text("Przybliż"))
            Button { zoom(by: 0.5, at: CGPoint(x: size.width / 2, y: size.height / 2), in: size) } label: {
                Image(systemName: "minus").frame(width: 16, height: 16)
            }
            .accessibilityLabel(Text("Oddal"))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(8)
    }

    // MARK: Drawing

    private func draw(_ context: GraphicsContext, _ size: CGSize, _ date: Date) {
        var context = context
        let palette = MapPalette.of(scheme)
        let window = CGRect(origin: .zero, size: size)
        context.fill(Path(window), with: .color(palette.outside.opacity(0.25)))

        // The world only reaches to the poles: what lies beyond stays empty.
        let top = viewport.point(for: GeoPoint(latitude: 90, longitude: 0), in: size).y
        let bottom = viewport.point(for: GeoPoint(latitude: -90, longitude: 0), in: size).y
        let world = CGRect(x: 0, y: top, width: size.width, height: bottom - top).intersection(window)
        guard !world.isNull else { return }
        context.clip(to: Path(world))
        context.fill(Path(world), with: .color(palette.ocean))
        context.fill(path(of: map.land, size: size, closed: true), with: .color(palette.land), style: FillStyle(eoFill: true))
        context.stroke(path(of: map.borders, size: size, closed: false), with: .color(palette.border), lineWidth: 0.6)
        context.stroke(path(of: map.land, size: size, closed: true), with: .color(palette.border.opacity(0.8)), lineWidth: 0.6)
        if let shade = shadeImage(size: size, date: date, palette: palette) {
            context.draw(Image(decorative: shade, scale: 1).interpolation(.high), in: window)
        }
        drawSun(context, size, date)
        drawCities(context, size, palette)
        if let pin { drawPin(context, pinPoint(pin, size)) }
    }

    /// The paths of one kind in the window, also the copies of the map to the east and west of it.
    private func path(of paths: [PreparedMap.Path], size: CGSize, closed: Bool) -> Path {
        let window = CGRect(origin: .zero, size: size).insetBy(dx: -20, dy: -20)
        var result = Path()
        for shift in [0.0, 360, -360] {
            for item in paths {
                let a = viewport.point(for: GeoPoint(latitude: item.maxLat, longitude: item.minLon + shift), in: size)
                let b = viewport.point(for: GeoPoint(latitude: item.minLat, longitude: item.maxLon + shift), in: size)
                guard CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y).intersects(window),
                      let first = item.points.first else { continue }
                result.move(to: viewport.point(for: GeoPoint(latitude: first.latitude, longitude: first.longitude + shift), in: size))
                for point in item.points.dropFirst() {
                    result.addLine(to: viewport.point(for: GeoPoint(latitude: point.latitude, longitude: point.longitude + shift), in: size))
                }
                if closed { result.closeSubpath() }
            }
        }
        return result
    }

    private func shadeImage(size: CGSize, date: Date, palette: MapPalette) -> CGImage? {
        let step = Self.shadeStep
        let width = max(Int(size.width) / step, 1), height = max(Int(size.height) / step, 1)
        let minute = Int(date.timeIntervalSince1970 / 60)
        let key = "\(viewport.center.latitude),\(viewport.center.longitude),\(viewport.zoom),\(width)x\(height),\(minute),\(scheme == .dark)"
        if shadeCache.key == key { return shadeCache.image }
        let shader = DayNight.shader(date: date)
        let night = NSColor(palette.night).usingColorSpace(.sRGB) ?? .black
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let geo = viewport.geo(at: CGPoint(x: (Double(x) + 0.5) * Double(step), y: (Double(y) + 0.5) * Double(step)), in: size)
                let alpha = palette.shade[min(shader(geo), palette.shade.count - 1)]
                let i = (y * width + x) * 4
                bytes[i] = UInt8(night.redComponent * alpha * 255)
                bytes[i + 1] = UInt8(night.greenComponent * alpha * 255)
                bytes[i + 2] = UInt8(night.blueComponent * alpha * 255)
                bytes[i + 3] = UInt8(alpha * 255)
            }
        }
        let image = CGDataProvider(data: Data(bytes) as CFData).flatMap {
            CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: $0, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }
        shadeCache.key = key
        shadeCache.image = image
        return image
    }

    private func drawSun(_ context: GraphicsContext, _ size: CGSize, _ date: Date) {
        let sun = DayNight.subsolarPoint(date: date)
        for shift in [0.0, 360, -360] {
            let point = viewport.point(for: GeoPoint(latitude: sun.latitude, longitude: sun.longitude + shift), in: size)
            guard CGRect(origin: .zero, size: size).insetBy(dx: -12, dy: -12).contains(point) else { continue }
            context.draw(Text(Image(systemName: "sun.max.fill")).font(.system(size: 18)).foregroundColor(.orange), at: point)
        }
    }

    private func drawCities(_ context: GraphicsContext, _ size: CGSize, _ palette: MapPalette) {
        let placed = CityLabels.place(cities: map.cities, viewport: viewport, size: size, labelSize: Self.labelSize)
        for item in placed {
            context.fill(Path(ellipseIn: CGRect(x: item.point.x - 2.5, y: item.point.y - 2.5, width: 5, height: 5)),
                         with: .color(palette.text))
            context.draw(Text(item.city.name).font(.system(size: 10)).foregroundColor(palette.text),
                         at: CGPoint(x: item.labelRect.minX, y: item.labelRect.midY), anchor: .leading)
        }
    }

    private func drawPin(_ context: GraphicsContext, _ point: CGPoint) {
        context.fill(Path(ellipseIn: CGRect(x: point.x - 14, y: point.y - 14, width: 28, height: 28)), with: .color(.red.opacity(0.22)))
        let dot = Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
        context.fill(dot, with: .color(.red))
        context.stroke(dot, with: .color(.white), lineWidth: 2)
    }

    private static func labelSize(_ text: String) -> CGSize {
        if let known = labelSizes[text] { return known }
        let measured = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10)])
        let size = CGSize(width: ceil(measured.width), height: ceil(measured.height))
        labelSizes[text] = size
        return size
    }
}
