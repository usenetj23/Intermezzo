# Privacy policy

Intermezzo is a free, open-source macOS app. This page says what it stores, what it reads, and what it sends over the network. The source code is in this repository, so you can check every statement here.

**In short:** no account, no telemetry, no analytics, no advertising and no third-party SDKs. The author of the app receives no data from it. Everything runs on your Mac. The only things that can leave it are listed under [Network requests](#network-requests), and each of them is optional.

## What the app stores on your Mac

- **Settings**, in the app's preferences.
- **Break history, the work log (intervals, corrections, notes) and Pomodoro plans and projects**, in the app's local database.
- **The last known location** used for the weather effect and for sunrise and sunset, and the coordinates you type in Light settings.
- **A diagnostic log** at `~/Library/Logs/Intermezzo/trace.log`, which you can open or delete from Settings › About. It stays on your Mac.
- **Rule scripts** you install or write, in `~/Library/Application Scripts/com.automit.Intermezzo/Rules`.
- **An API key** for the optional AI features, if you enter one. It is kept in the macOS Keychain, not in the settings.

## What the app reads, only locally

Each of these needs a permission you grant in macOS, and the app works without any of them (the relevant feature is then unavailable). Nothing read this way is sent anywhere.

- **Calendar:** event times, titles, calendar names, your availability and your reply status, compared on your Mac with the calendars and keywords you choose for meetings, work and holidays.
- **Full Disk Access (optional):** lets the app read which Focus mode is on, from the files macOS keeps in `~/Library/DoNotDisturb`. They are read on your Mac only and nothing from them is stored or sent.
- **Location:** for the weather effect, sun position and the saved-place work zone. The name of the Wi-Fi network you are on is compared locally with the names you list.
- **Input Monitoring:** a listen-only event tap that notes *when* you last pressed a key or clicked, to tell that you are away or took a natural pause. It does not record which keys you press or what you type.
- **Screen Recording:** the picture of your desktop behind the rain and glass effects on the break screen. It is used only to draw the break screen, and the app does not send it anywhere.
- **Accessibility and Automation:** used by AppleScript rules and gallery scripts that ask System Events about running apps and window titles. Scripts run on your Mac.
- **Notifications:** to show break reminders.

## Diagnostics you copy yourself

Settings › About › **Copy diagnostics** puts a text on your clipboard: the app and macOS versions, the Mac model and chip, the displays, the permission states, which features fell back (for example no light sensor) and a few log lines about light, media and sensors. It has no Wi-Fi or VPN names, calendar titles, places or user name. The app sends it nowhere; you decide whether to paste it into a GitHub issue.

## Network requests

All of these are optional and off unless you use the feature.

- **Weather effect on the break screen.** The app asks [Open-Meteo](https://open-meteo.com) for the current weather. The request contains the latitude and longitude of the Mac's location (the app asks for about 100 m accuracy), or the cached location. If the Mac gives no position, the place you typed in Light settings or the city of your time zone is used instead. Open-Meteo sees your IP address like any web server does. See its own privacy policy.
- **YouTube background theme.** If you choose a YouTube video as the break background, the app loads that video from YouTube in an embedded web view, and YouTube sees the request. By default this is not used.
- **AI features** (settings assistant, rule-script author, weekly summary). Off by default. A request is sent only when you click one of the features:
  - With the **Apple on-device model** nothing leaves your Mac.
  - With a **server compatible with the OpenAI API** the request goes to the address you enter (for example a local LM Studio or Ollama on your own computer or network, or a service you choose). A remote address must use `https://`, and the app warns you that the data leaves your computer.
  - What is sent is only what the feature needs: your description, the list of settings the assistant may change with their values, a description of the rule you want, or summary numbers about your breaks (counts and times of day). Window titles, network names, project names and file paths are never sent. The model's answers are never run or applied without your approval.
- **Sync folder (optional).** If you turn on sync, the app writes files with your settings, work log, break history and Pomodoro data into the folders you pick (for example iCloud Drive, OneDrive or Dropbox). That storage is then handled by that provider under its own policy. The app has no server of its own.

## What the app does not do

It does not create accounts, collect usage statistics, send crash reports, track you, or share data with the author or with advertisers.

## Your control

You can switch each feature and permission off in Settings and in System Settings › Privacy & Security, delete the log, clear the sync folders, and remove the app together with its data (`~/Library/Application Support`, `~/Library/Logs/Intermezzo`, `~/Library/Application Scripts/com.automit.Intermezzo`, the preferences file and the Keychain item `com.automit.Intermezzo.ai`).

## Changes and contact

If this changes, the change will appear in this file and in the release notes. Questions: open an issue at https://github.com/usenetj23/Intermezzo/issues.

*Last updated: 2026-10-31, for version 1.42.0.*
