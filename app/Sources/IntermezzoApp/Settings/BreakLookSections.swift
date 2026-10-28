import SwiftUI
import AppKit
import IntermezzoKit

// What the break screen looks like: background glass, own texts, a slideshow, a YouTube video.
// Shown in Appearance; the break rhythm itself stays in Breaks.

struct BreakGlassSection: View {
    @AppStorage(GlassKeys.effect) private var glassEffect = "blur"
    @AppStorage(GlassKeys.weatherFX) private var weatherFX = false

    var body: some View {
        Section("Szyba i pogoda") {
            Picker("Tło przerwy", selection: $glassEffect) {
                Text("Blur systemowy (tapeta za oknem)").tag("blur")
                Text("Glass — rozmycie obecnego ekranu").tag("glass")
                Text("Frost — mrożone szkło").tag("frost")
            }.settingsAnchor("appearance-tlo-przerwy")
            .onChange(of: glassEffect) { _, v in
                UserDefaults.standard.set(v, forKey: GlassKeys.effect)
            }
            if glassEffect != "blur" {
                Toggle("Pokazuj pogodę na szybie (Open-Meteo)", isOn: $weatherFX).settingsAnchor("appearance-pokazuj-pogode-na-szybie-open-meteo")
                    .expertOnly()
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: ScreenGlass.hasPermission
                             ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(ScreenGlass.hasPermission ? .green : .red)
                        Text(ScreenGlass.hasPermission
                             ? "Nagrywanie ekranu przyznane — Glass działa"
                             : "Brak uprawnień do nagrywania ekranu")
                    }
                    .font(.callout)
                    if !ScreenGlass.hasPermission {
                        Button("Przyznaj uprawnienia…") {
                            ScreenGlass.requestPermission()
                        }.settingsAnchor("appearance-przyznaj-uprawnienia")
                        .controlSize(.small)
                    }
                }
            }
        }
    }
}

struct BreakTextThemeSection: View {
    @AppStorage(TextThemeKeys.enabled) private var textThemeEnabled = false
    @AppStorage(TextThemeKeys.random) private var textThemeRandom = false
    @AppStorage(TextThemeKeys.seconds) private var textThemeSeconds = 0
    @AppStorage(TextThemeKeys.font) private var textThemeFontName = "default"
    @AppStorage(TextThemeKeys.color) private var textThemeColorHex = "FFFFFF"
    @AppStorage(TextThemeKeys.scale) private var textThemeScale = 40
    @AppStorage(TextThemeKeys.offset) private var textThemeOffset = 0
    @State private var items: [String] = []

    var body: some View {
        Section("Text Theme") {
            Toggle("Show your own texts during breaks", isOn: $textThemeEnabled).settingsAnchor("appearance-show-your-own-texts-during-breaks")
                .onChange(of: textThemeEnabled) { _, on in
                    if on {
                        textThemeSeedIfEmpty()
                        items = loadTextThemeItems()
                    }
                }
            if textThemeEnabled {
                ForEach(items.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        TextField("Text \(i + 1):", text: textItemBinding(i))
                            .textFieldStyle(.editable)
                        Button { moveItem(i, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(i == 0)
                        Button { moveItem(i, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(i == items.count - 1)
                        Button { removeItem(i) } label: { Image(systemName: "trash") }
                    }
                }
                Button("＋ Add text") {
                    items.append("")
                    saveTextThemeItems(items)
                }.settingsAnchor("appearance-add-text")

                Group {
                    Picker("Order:", selection: $textThemeRandom) {
                        Text("Sequential").tag(false)
                        Text("Random").tag(true)
                    }.settingsAnchor("appearance-order")
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)

                    Stepper(value: $textThemeSeconds, in: 0...600, step: 5) {
                        Text(textThemeSeconds == 0
                             ? "Seconds per text: 0 (one text per break)"
                             : "Seconds per text: \(textThemeSeconds)")
                    }

                    Picker("Font:", selection: $textThemeFontName) {
                        Text("System").font(.system(size: 12)).tag("default")
                        Text("Serif").font(.system(size: 12, design: .serif)).tag("serif")
                        Text("Rounded").font(.system(size: 12, design: .rounded)).tag("rounded")
                        Text("Monospaced").font(.system(size: 12, design: .monospaced)).tag("mono")
                    }.settingsAnchor("appearance-font")
                    .frame(maxWidth: 300)

                    ColorPicker("Text color:", selection: hexColorBinding)

                    Slider(value: Binding(get: { Double(textThemeScale) },
                                         set: { textThemeScale = Int($0) }), in: 10...100)
                    Text("Scale \(textThemeScale)% — how much of the screen the text uses")
                        .settingsNote()

                    Slider(value: Binding(get: { Double(textThemeOffset) },
                                         set: { textThemeOffset = Int($0) }), in: -50...50)
                    Text("Vertical offset \(textThemeOffset)% — positive moves text up, away from the Dock")
                        .settingsNote()

                }
                .expertOnly()
                Button("Preview — 8 s, click-through") {
                    AppDelegate.shared?.coordinator.previewWeatherScene()
                }.settingsAnchor("appearance-preview-8-s-click-through")
            }
        }
        .onAppear { items = loadTextThemeItems() }
    }

    private func textItemBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: { i < items.count ? items[i] : "" },
            set: { newValue in
                guard i < items.count else { return }
                items[i] = newValue
                saveTextThemeItems(items)
            })
    }

    private func moveItem(_ i: Int, by delta: Int) {
        let j = i + delta
        guard items.indices.contains(i), items.indices.contains(j) else { return }
        items.swapAt(i, j)
        saveTextThemeItems(items)
    }

    private func removeItem(_ i: Int) {
        guard items.indices.contains(i) else { return }
        items.remove(at: i)
        saveTextThemeItems(items)
    }

    private var hexColorBinding: Binding<Color> {
        Binding(
            get: { colorFromHex(textThemeColorHex) },
            set: { newColor in
                let ns = NSColor(newColor).usingColorSpace(.deviceRGB)
                let r = Int((ns?.redComponent ?? 1) * 255)
                let g = Int((ns?.greenComponent ?? 1) * 255)
                let b = Int((ns?.blueComponent ?? 1) * 255)
                textThemeColorHex = String(format: "%02X%02X%02X", r, g, b)
            })
    }
}

struct BreakImageThemeSection: View {
    @AppStorage(ImageThemeKeys.enabled) private var imageThemeEnabled = false
    @AppStorage(ImageThemeKeys.random) private var imageThemeRandom = false
    @AppStorage(ImageThemeKeys.seconds) private var imageThemeSeconds = 0
    @AppStorage(ImageThemeKeys.transition) private var imageThemeTransition = "crossfade"
    @AppStorage(ImageThemeKeys.crossfade) private var imageThemeCrossfadeSeconds = 2
    @AppStorage(ImageThemeKeys.scale) private var imageThemeScaleMode = "fill"
    @AppStorage(ImageThemeKeys.scalePercent) private var imageThemeScalePercent = 60
    @AppStorage(ImageThemeKeys.span) private var imageThemeSpan = 0
    @State private var items: [String] = []

    var body: some View {
        Section("Image Theme") {
            Toggle("Show a photo slideshow during breaks", isOn: $imageThemeEnabled).settingsAnchor("appearance-show-a-photo-slideshow-during-breaks")
            if imageThemeEnabled {
                ForEach(items.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        if let img = NSImage(contentsOfFile:
                            (items[i] as NSString).expandingTildeInPath) {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 72, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        } else {
                            Image(systemName: "photo.badge.exclamationmark")
                                .frame(width: 72, height: 48)
                        }
                        Text((items[i] as NSString).lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button { moveItem(i, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(i == 0)
                        Button { moveItem(i, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(i == items.count - 1)
                        Button { removeItem(i) } label: { Image(systemName: "trash") }
                    }
                }
                Button("＋ Add images…") {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = true
                    panel.canChooseDirectories = false
                    panel.allowedContentTypes = [.image]
                    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Pictures")
                    if panel.runModal() == .OK {
                        items.append(contentsOf: panel.urls.map(\.path))
                        saveImageThemeItems(items)
                    }
                }.settingsAnchor("appearance-add-images")
                Text("Photos and images are only shown if you add them here — the app does not scan your library. Tip: the picker can open Photos.app → Library.photoslibrary contents.")
                    .settingsNote().settingsAnchor("appearance-photos-and-images-are-only-shown-if")

                Group {
                    Picker("Order:", selection: $imageThemeRandom) {
                        Text("Sequential").tag(false)
                        Text("Random").tag(true)
                    }.settingsAnchor("appearance-order-2")
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)

                    Picker("Transition:", selection: $imageThemeTransition) {
                        Text("None").tag("none")
                        Text("Crossfade").tag("crossfade")
                    }.settingsAnchor("appearance-transition")
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                    if imageThemeTransition != "none" {
                        Stepper("Crossfade duration: \(imageThemeCrossfadeSeconds)s",
                              value: $imageThemeCrossfadeSeconds, in: 0...5)
                    }

                    Stepper(value: $imageThemeSeconds, in: 0...600, step: 5) {
                        Text(imageThemeSeconds == 0
                             ? "Seconds per image: 0 (one image per break)"
                             : "Seconds per image: \(imageThemeSeconds)")
                    }

                    Picker("Image scale:", selection: $imageThemeScaleMode) {
                        Text("Fit — show whole image").tag("fit")
                        Text("Fill — crop edges to cover").tag("fill")
                        Text("Percent of screen").tag("percent")
                    }.settingsAnchor("appearance-image-scale")
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 380)
                    if imageThemeScaleMode == "percent" {
                        Slider(value: Binding(get: { Double(imageThemeScalePercent) },
                                             set: { imageThemeScalePercent = Int($0) }), in: 10...100)
                        Text("Percent: \(imageThemeScalePercent)%")
                            .settingsNote()
                    }

                    if imageThemeScaleMode == "fill" {
                        Toggle("Jeden obraz rozpięty na wszystkie monitory", isOn: Binding(
                            get: { imageThemeSpan != 0 }, set: { imageThemeSpan = $0 ? 1 : 0 })).settingsAnchor("appearance-jeden-obraz-rozpiety-na-wszystkie-mo")
                    }
                }
                .expertOnly()
                Button("Preview — 8 s, click-through") {
                    AppDelegate.shared?.coordinator.previewWeatherScene()
                }.settingsAnchor("appearance-preview-8-s-click-through-2")
            }
        }
        .onAppear { items = loadImageThemeItems() }
    }

    private func moveItem(_ i: Int, by delta: Int) {
        let j = i + delta
        guard items.indices.contains(i), items.indices.contains(j) else { return }
        items.swapAt(i, j)
        saveImageThemeItems(items)
    }

    private func removeItem(_ i: Int) {
        guard items.indices.contains(i) else { return }
        items.remove(at: i)
        saveImageThemeItems(items)
    }
}

struct BreakYouTubeSection: View {
    @AppStorage(YouTubeThemeKeys.enabled) private var ytEnabled = false
    @AppStorage(YouTubeThemeKeys.url) private var ytUrl = ""
    @AppStorage(YouTubeThemeKeys.startRandom) private var ytRandom = false
    @AppStorage(YouTubeThemeKeys.startOffset) private var ytOffset = 0
    @AppStorage(YouTubeThemeKeys.volume) private var ytVolume = 0

    var body: some View {
        Section("YouTube Theme") {
            Toggle("Play a YouTube video during breaks (main screen)", isOn: $ytEnabled).settingsAnchor("appearance-play-a-youtube-video-during-breaks-m")
            if ytEnabled {
                TextField("YouTube URL (video or playlist)", text: $ytUrl)
                    .textFieldStyle(.editable)
                    .frame(maxWidth: 420)
                Group {
                    Toggle("Start at a random point", isOn: $ytRandom).settingsAnchor("appearance-start-at-a-random-point")
                    if !ytRandom {
                        Stepper("Start at: \(ytOffset)s", value: $ytOffset, in: 0...7200, step: 30)
                    }
                    Slider(value: Binding(get: { Double(ytVolume) },
                                          set: { ytVolume = Int($0) }), in: 0...100)
                    Text("Volume — set to 0 to keep it muted")
                        .settingsNote().settingsAnchor("appearance-volume-set-to-0-to-keep-it-muted")
                }
                .expertOnly()
                if let parsed = youTubeIds(from: ytUrl).video ?? youTubeIds(from: ytUrl).playlist,
                   !parsed.isEmpty {
                    Text("Detected: \(parsed)")
                        .settingsNote()
                } else if !ytUrl.isEmpty {
                    Text("Could not find a video or playlist ID in that URL.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
