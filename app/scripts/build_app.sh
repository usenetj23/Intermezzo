#!/bin/zsh
# Intermezzo — budowanie natywnego arm64 .app + ad-hoc signing + uruchomienie.
# Środowisko: macOS 27 / Xcode 27 / Swift 6, Apple Silicon (M3+).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="${INTERMEZZO_SCRATCH:-$HOME/.cache/intermezzo-build}"
CONFIG_DIR="$ROOT/Support"

echo "==> swift build (release, arm64)"
swift build -c release --scratch-path "$SCRATCH"

BIN="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)/Intermezzo"
echo "==> binary: $BIN"
file "$BIN"

APP="$ROOT/dist/Intermezzo.app"
echo "==> pakietyzacja: $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Intermezzo"
cp "$CONFIG_DIR/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$CONFIG_DIR/AppIcon.icns" ]]; then
  cp "$CONFIG_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
# Utwory muzyki relaksacyjnej — picker audio skanuje Resources/tracks.
if [[ -d "$CONFIG_DIR/tracks" ]]; then
  cp -R "$CONFIG_DIR/tracks" "$APP/Contents/Resources/tracks"
fi
if ! ls "$APP/Contents/Resources/tracks/"* >/dev/null 2>&1; then
  echo "BŁĄD: brak Support/tracks — picker audio byłby pusty" >&2
  exit 1
fi
# Mapa offline do wyboru lokalizacji (Support/worldmap, generowana przez scripts/gen_world_map.py).
if [[ ! -f "$CONFIG_DIR/worldmap/worldmap.bin" ]]; then
  echo "BŁĄD: brak Support/worldmap/worldmap.bin — uruchom scripts/gen_world_map.py" >&2
  exit 1
fi
cp "$CONFIG_DIR/worldmap/worldmap.bin" "$APP/Contents/Resources/worldmap.bin"
# Tłumaczenia interfejsu (Support/en.lproj, pl.lproj; generowane przez scripts/gen_localization.py).
for lproj in "$CONFIG_DIR"/*.lproj; do
  [[ -d "$lproj" ]] && cp -R "$lproj" "$APP/Contents/Resources/"
done
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Bez symboli debugowania: zawierają ścieżki budowania (nazwę użytkownika) i nie są potrzebne do działania.
strip -S -x "$APP/Contents/MacOS/Intermezzo"

echo "==> codesign (ad-hoc)"
# OneDrive dodaje atrybuty (Finder info) które blokują codesign: usuń je.
xattr -cr "$APP" 2>/dev/null || true
# Ad-hoc, BEZ --entitlements: entitlement HealthKit jest zastrzeżony i wymaga
# Developer ID + provisioning profile; z podpisem ad-hoc macOS zablokowałby start.
#
# Domyślny wymóg ad-hoc to `cdhash H"..."` — hash JEDNEJ kompilacji. TCC zapisuje
# właśnie ten wymóg, więc każda przebudowa unieważniała wszystkie zgody (Input
# Monitoring, Nagrywanie ekranu, Kalendarz, Automatyzacja…): w Ustawieniach
# systemowych ptaszek jest, a aplikacja go "nie widzi". Wymóg oparty na
# identyfikatorze pakietu przeżywa przebudowy. Kompromis: każdy podpisany
# ad-hoc program o tym samym identyfikatorze dziedziczy zgody (maszyna lokalna).
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
codesign --force --deep -s - -r="designated => identifier \"$BUNDLE_ID\"" "$APP"
codesign --verify --strict "$APP"
codesign -d -r- "$APP" 2>&1 | grep designated
codesign -dv "$APP" 2>&1 | head -3

echo "==> gotowe: $APP"
if [[ "${1:-}" == "--run" ]]; then
  open "$APP"
  echo "uruchomiono."
fi
