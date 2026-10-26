

https://github.com/user-attachments/assets/40f744f5-ea90-47ec-8063-807d48bffce3

# Intermezzo

[![CodeQL](https://github.com/usenetj23/Intermezzo/actions/workflows/codeql.yml/badge.svg)](https://github.com/usenetj23/Intermezzo/actions/workflows/codeql.yml)
[![Release](https://github.com/usenetj23/Intermezzo/actions/workflows/release.yml/badge.svg)](https://github.com/usenetj23/Intermezzo/actions/workflows/release.yml)

A break reminder for macOS that lives in the menu bar. It reminds you to step away from the screen, covers every display at the same time when a break starts, and stays out of the way during meetings, videos and time off.

The interface is available in **English** and **Polish**.

> Intermezzo is a personal project, built and tested on one Mac. It is not notarised and has no Developer ID signature, so macOS asks for confirmation on first launch (see [Installation](#installation)).

<p align="center">
  <img src="docs/screenshots/break-screen.png" alt="The break screen: a countdown, an exercise to do, and a trend of recent breaks over the desktop" width="860">
</p>

<!-- A short video of the break screen can go here: upload the .mp4 on github.com (drag it into the README editor or an issue comment) and paste the user-attachments URL on its own line. -->

<table>
  <tr>
    <td align="center" valign="bottom"><img src="docs/screenshots/status-bar-popup.png" alt="The menu-bar panel: countdown, Break now, Long break, +1 and +5 minutes, Keep awake and Light shortcuts" height="360"></td>
    <td align="center" valign="bottom"><img src="docs/screenshots/break-warning.png" alt="A pill that warns a short break is coming, with a countdown ring next to the cursor" width="420"></td>
  </tr>
  <tr>
    <td align="center"><sub>The menu-bar panel</sub></td>
    <td align="center"><sub>A warning before the break, and the countdown next to the cursor</sub></td>
  </tr>
</table>

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

**Optional AI (off by default)**
- A settings assistant that turns "I work Monday to Friday, 8 to 16, no breaks in meetings" into a list of changes you approve (and can undo), an author of rule scripts that writes the AppleScript for a rule from a description (you check, test and save it), and a short weekly summary of your breaks.
- Runs on the model built into macOS (Apple Intelligence, macOS 26 or newer, on the Mac) or on a server that speaks the OpenAI API, for example a local LM Studio or Ollama. Nothing is sent unless you click one of the features; window titles, network names, projects and file paths are never sent, and the answer of the model is never run or applied without your approval. An API key, if you use one, is kept in the Keychain.

**Automation and sync**
- `intermezzo://` URL commands and a gallery of ready-made AppleScript scripts.
- Settings sync between your Macs through any shared folder (iCloud Drive, OneDrive, Dropbox, SMB). No server and no account.

Everything runs locally. Intermezzo does not collect or send usage data. The only network requests are the optional weather effect on the break screen ([Open-Meteo](https://open-meteo.com), sends approximate coordinates) and, only if you turn them on, the optional AI features described above.

## Screenshots

<table>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/settings-status.png" alt="Status: live countdown, break trend and actions" width="440"><br><sub>Status: the countdown, the trend of recent breaks and quick actions</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/settings-statistics.png" alt="Statistics: the last 7 days, success rate and an AI weekly summary" width="440"><br><sub>Statistics, with the optional AI weekly summary</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/settings-light.png" alt="Light: the screen colour through the day, drawn as an hourly chart" width="440"><br><sub>Light: the screen colour follows the sun, or your own curve</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/settings-light-monitors.png" alt="Light: settings per monitor model, and picking the location on a map" width="440"><br><sub>Settings per monitor, and a location picker with an offline map</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/settings-ai.png" alt="AI: the Apple on-device model or a server compatible with the OpenAI API" width="440"><br><sub>Optional AI: the on-device model or your own server</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/settings-script-gallery.png" alt="Script gallery: ready-made rules for video calls, games, presentations and more" width="440"><br><sub>Rules and a gallery of ready-made scripts</sub></td>
  </tr>
</table>

<details>
<summary>All settings panes</summary>

<table>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/settings-breaks.png" alt="Breaks: presets, strictness and micro-reminders" width="440"><br><sub>Breaks</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/settings-general.png" alt="General: startup, idle time, working hours and the settings assistant" width="440"><br><sub>General</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/settings-focus-sessions.png" alt="Focus sessions: Pomodoro, natural seam and rhythm experiment" width="440"><br><sub>Focus sessions</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/settings-rules.png" alt="Rules: scripts that postpone or skip a break" width="440"><br><sub>Rules</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/settings-end-of-day.png" alt="End of day: an evening reminder to stop working" width="440"><br><sub>End of day</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/settings-flash-reminder.png" alt="Flash reminder: gentle flashes and a blink reminder" width="440"><br><sub>Flash reminder</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/settings-keep-awake.png" alt="Keep awake: keeps the Mac awake, with safety limits" width="440"><br><sub>Keep awake</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/settings-messages.png" alt="Messages: tips and articles shown during breaks" width="440"><br><sub>Messages</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/settings-exercises.png" alt="Exercises: a library of eye, neck, wrist and back exercises" width="440"><br><sub>Exercises</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/settings-appearance.png" alt="Appearance: surface themes, language and notifications" width="440"><br><sub>Appearance</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/settings-sync.png" alt="Sync and backup through any shared folder" width="440"><br><sub>Sync and backup</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/settings-advanced.png" alt="Advanced: natural-break detection and permissions" width="440"><br><sub>Advanced</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/settings-about.png" alt="About: version and a tip of the day" width="440"><br><sub>About</sub></td>
  </tr>
</table>

</details>

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
gh attestation verify Intermezzo-1.40.0.zip -R usenetj23/Intermezzo
```

Other checks:
- Every push is scanned by [CodeQL](https://github.com/usenetj23/Intermezzo/security/code-scanning), GitHub's static security analysis, and the unit tests run on each change.
- Each release lists the zip's SHA-256 checksum. Compare it with `shasum -a 256 Intermezzo-1.40.0.zip`.
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
