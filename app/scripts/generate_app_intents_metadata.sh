#!/bin/zsh
# Writes Metadata.appintents into the app bundle so that the Shortcuts app lists Intermezzo's actions.
#
# SwiftPM compiles the App Intents in Sources/IntermezzoApp but never runs Apple's metadata processor (only an
# Xcode app target does), so without this step Shortcuts sees nothing. The default SwiftPM build emits the constant
# values the processor reads (*.swiftconstvalues); this script hands them to `appintentsmetadataprocessor`.
#
# Soft by design: a failure here is reported but does not stop the build (the app works without the actions).
#
#   generate_app_intents_metadata.sh <Resources dir> [scratch dir]
set -uo pipefail

RESOURCES="${1:?usage: generate_app_intents_metadata.sh <Resources dir> [scratch dir]}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="${2:-${INTERMEZZO_SCRATCH:-$HOME/.cache/intermezzo-build}}"
MODULE="IntermezzoApp"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

warn() { echo "WARNING (app intents): $*" >&2; exit 0; }

DEV="$(xcode-select -p)"
TOOLCHAIN="$DEV/Toolchains/XcodeDefault.xctoolchain"
PROCESSOR="$(xcrun -f appintentsmetadataprocessor 2>/dev/null)" || warn "appintentsmetadataprocessor not found (full Xcode needed)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
XCODE_BUILD="$(xcodebuild -version | awk '/Build version/ {print $3}')"
PLIST="$ROOT/Support/Info.plist"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
TARGET="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")"
ARCH="$(uname -m)"

# The constant values of this module only (not IntermezzoKit's).
find "$SCRATCH" -name '*.swiftconstvalues' -path "*${MODULE}*" 2>/dev/null | sort > "$WORK/constvalues.txt"
find "$ROOT/Sources/$MODULE" -name '*.swift' | sort > "$WORK/sources.txt"
echo "app intents: $(wc -l < "$WORK/constvalues.txt" | tr -d ' ') const-value files, $(wc -l < "$WORK/sources.txt" | tr -d ' ') sources"
if [[ ! -s "$WORK/constvalues.txt" ]]; then
  echo "app intents: const-value files found anywhere under the scratch dir:" >&2
  find "$SCRATCH" -name '*.swiftconstvalues' 2>/dev/null | head -5 >&2
  warn "no .swiftconstvalues for $MODULE: the SwiftPM build did not emit them"
fi

run_processor() {
  "$PROCESSOR" \
    --toolchain-dir "$TOOLCHAIN" \
    --module-name "$MODULE" \
    --sdk-root "$SDK" \
    --xcode-version "$XCODE_BUILD" \
    --platform-family macOS \
    --deployment-target "$TARGET" \
    --target-triple "${ARCH}-apple-macos${TARGET}" \
    --bundle-identifier "$BUNDLE_ID" \
    --source-file-list "$WORK/sources.txt" \
    --swift-const-vals-list "$WORK/constvalues.txt" \
    --output "$RESOURCES" \
    "$@" > "$WORK/processor.log" 2>&1
}

OUT="$RESOURCES/Metadata.appintents/extract.actionsdata"
rm -rf "$RESOURCES/Metadata.appintents"
run_processor --compile-time-extraction || true
if [[ ! -f "$OUT" ]]; then
  echo "app intents: first attempt left no metadata, trying without --compile-time-extraction" >&2
  cat "$WORK/processor.log" >&2
  run_processor || true
fi
if [[ ! -f "$OUT" ]]; then
  cat "$WORK/processor.log" >&2
  warn "the processor wrote no extract.actionsdata"
fi

# Say what it found, so a missing action shows up in the build log.
python3 - "$OUT" <<'PY' || true
import json, sys
data = json.load(open(sys.argv[1]))
actions = data.get("actions", {})
names = sorted(actions) if isinstance(actions, dict) else sorted(a.get("identifier", "?") for a in actions)
print(f"app intents: {len(names)} actions in Metadata.appintents")
for n in names: print("  -", n)
for key in ("entities", "enums", "queries"):
    items = data.get(key)
    if isinstance(items, dict):
        print(f"app intents: {len(items)} {key}: {', '.join(sorted(items))}")
    elif isinstance(items, list):
        print(f"app intents: {len(items)} {key}")
PY
