# Intermezzo

[![CodeQL](https://github.com/usenetj23/Intermezzo/actions/workflows/codeql.yml/badge.svg)](https://github.com/usenetj23/Intermezzo/actions/workflows/codeql.yml)
[![Release](https://github.com/usenetj23/Intermezzo/actions/workflows/release.yml/badge.svg)](https://github.com/usenetj23/Intermezzo/actions/workflows/release.yml)

A break reminder for macOS that lives in the menu bar. It reminds you to step away from the screen, covers every display at the same time when a break starts, and stays out of the way during meetings, videos and time off.

The interface is available in **English** and **Polish**.

> Intermezzo is a personal project, built and tested on one Mac. It is not notarised and has no Developer ID signature, so macOS asks for confirmation on first launch (see [Installation](#installation)).

## Features

**Breaks**
- Short and long breaks on a rhythm you choose, with Pomodoro mode.
- The break screen covers all displays at once, with a countdown, Skip and +1/+5 min.
- Strictness levels, from relaxed (postpone a few times a day) to hard (no Skip).
- Soft breaks that dim the screen without blocking clicks, and a reminder-only mode.
- A countdown ring next to the cursor before a break, plus an edge glow and a flash reminder.
- Exercises, breathing and eye-care prompts during a break. The health content is documented in [docs/zrodla-zdrowie-oczu.md](docs/zrodla-zdrowie-oczu.md), written in Polish.
- Pauses whatever plays (a YouTube video, music) when a break starts and resumes it afterwards.

**Knows when not to interrupt**
- Pauses while you are away, in a video call (Zoom, Teams, Webex, Meet, Skype) or watching a video.
- Working hours per weekday, holidays and time off.
- An optional work zone: breaks run only while a calendar event, a VPN, a Wi-Fi network, a wired network or a saved place says you are at work.

**Focus and statistics**
- Projects, a daily plan and interruptions, with PDF and CSV reports.
- Statistics, streaks and a 12-week regularity map, with an option to turn off the scoring.
- Focus control through the Shortcuts app.

**Light and keep awake**
- Warmer screen colour in the evening, following the clock or the sun, with your own 24-hour curve.
- Ambient-light awareness and per-app or full-screen exceptions.
- Settings per monitor model: a limit for how warm the colour may get, its own evening dimming and a leave-alone switch (a TV). They are remembered, so the monitors at home and at work get their own settings again when you plug them in.
- Pick your location on an offline world map with day and night shading, or type the coordinates.
- Optional [BetterDisplay](https://github.com/waydabber/BetterDisplay) integration for dimming external displays.
- Keeps the Mac awake on request, during a focus session or while chosen apps run, with battery, Low Power Mode and heat limits.

**Automation and sync**
- `intermezzo://` URL commands and a gallery of ready-made AppleScript scripts.
- Settings sync between your Macs through any shared folder (iCloud Drive, OneDrive, Dropbox, SMB). No server and no account.

Everything runs locally. Intermezzo does not collect or send usage data. The only network request is the optional weather effect on the break screen ([Open-Meteo](https://open-meteo.com), sends approximate coordinates).

## Requirements

- macOS 14 or later, Apple Silicon.
- To build: Xcode command-line tools with Swift 5.10 or later.

## Building

```bash
cd app
swift test --scratch-path ~/.cache/intermezzo-test   # unit tests
./scripts/build_app.sh                               # builds dist/Intermezzo.app
./scripts/build_app.sh --run                         # builds and launches it
```

Build outside folders synced by OneDrive or iCloud (the default scratch path is `~/.cache/intermezzo-build`). The extended attributes those services add can break code signing.

The script signs the app ad hoc with a designated requirement based on the bundle identifier, so macOS keeps granted permissions across rebuilds.

## Installation

1. Download `Intermezzo-<version>.zip` from [Releases](https://github.com/usenetj23/Intermezzo/releases), or build the app yourself. Move `Intermezzo.app` to `/Applications`.
2. The app is not notarised, so macOS blocks the first launch. Open System Settings › Privacy & Security and click **Open Anyway** next to Intermezzo. In Terminal you can instead run `xattr -dr com.apple.quarantine /Applications/Intermezzo.app`.
3. Grant only the permissions you want to use. Intermezzo works without any of them, and Settings › Advanced › Permissions shows what each one is for:
   - Calendar: meeting and holiday detection.
   - Location: weather, sun position, the saved-place work zone and the Wi-Fi network name.
   - Input Monitoring: detecting a natural pause in typing.
   - Screen Recording: the real desktop behind the rain and glass effects.
   - Accessibility and Automation: AppleScript rules and gallery scripts.

## Verifying a download

Release zips are built on GitHub's servers from the tagged source by the [Release workflow](.github/workflows/release.yml), not on a personal machine. Each zip carries a signed [build provenance attestation](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations) that ties it to the exact commit and workflow run. To check a download with the [GitHub CLI](https://cli.github.com):

```bash
gh attestation verify Intermezzo-1.39.3.zip -R usenetj23/Intermezzo
```

Other checks:
- Every push is scanned by [CodeQL](https://github.com/usenetj23/Intermezzo/security/code-scanning), GitHub's static security analysis, and the unit tests run on each change.
- Each release lists the zip's SHA-256 checksum. Compare it with `shasum -a 256 Intermezzo-1.39.3.zip`.
- The release notes link a [VirusTotal](https://www.virustotal.com) report for the zip.
- You can always build the app yourself from source (see [Building](#building)).

## Project layout

```
app/
├── Package.swift
├── Sources/IntermezzoKit/    # pure logic (break engine, rules, sync, light, statistics), fully tested
├── Sources/IntermezzoApp/    # AppKit + SwiftUI app: menu bar, break screen, Settings
├── Tests/IntermezzoKitTests/ # unit tests
├── Support/                  # Info.plist, icon, sounds, translations (en.lproj, pl.lproj)
├── scripts/                  # build, localisation, end-to-end and performance scripts
└── tools/                    # generator for the synthesised ambient sounds
docs/                         # sources for the health content (Polish)
```

## Translations

UI strings are written in Polish in the code. Translations live in `app/scripts/l10n/{pl,en}/*.py`, and this command generates `Support/{en,pl}.lproj`:

```bash
cd app
python3 scripts/gen_localization.py --check --orphans
```

A missing translation falls back to the original text.

## Known limitations

- HealthKit logging does not work with an ad hoc signature (Apple restricts that entitlement), so drinks stay in Intermezzo's own log.
- Some features use private macOS frameworks: MediaRemote for pausing media and DisplayServices for the ambient-light reading. They may stop working after a macOS update, and the app then falls back to simpler behaviour.
- URL commands such as `intermezzo://skip` can be opened by any web page. Turn off the ones you do not need.

## Support

Intermezzo is free and stays free. If it helps you take better breaks and you would like to buy me a coffee, you can do it through [GitHub Sponsors](https://github.com/sponsors/usenetj23). Bug reports and ideas in [Issues](https://github.com/usenetj23/Intermezzo/issues) help just as much.

## Licence

[MIT](LICENSE). Bundled music and sounds have their own licences, listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

---

## Po polsku

Intermezzo to przypominacz o przerwach dla macOS, działający z paska menu. Przerwa zasłania wszystkie ekrany naraz. Aplikacja wstrzymuje się w trakcie spotkań, filmów i poza godzinami pracy. Ma tryb Pomodoro i statystyki, cieplejsze światło wieczorem oraz synchronizację między Macami przez wspólny folder. Interfejs jest po polsku i po angielsku. Instrukcja budowania jest wyżej, w sekcji [Building](#building).
