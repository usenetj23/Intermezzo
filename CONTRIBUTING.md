# Contributing to Intermezzo

Thanks for your interest. Intermezzo is a personal project tested on three Macs (MacBook Pro M5, MacBook Air M4, Mac Studio M3 Ultra), so bug reports and suggestions from other setups are especially useful. Settings › About › **Copy diagnostics** puts the details a bug report needs on your clipboard. Please be patient: replies may take a few days.

By taking part you agree to follow the [code of conduct](CODE_OF_CONDUCT.md). Contributions are accepted under the project's [MIT licence](LICENSE).

## Reporting a problem or suggesting a feature

Use the issue templates. For a bug, tell me the Intermezzo version (Settings › About), your macOS version and Mac, what you did, what you expected and what happened. If you attach the log (`~/Library/Logs/Intermezzo/trace.log`) or a screenshot, **check it first**: it can contain app names, network names or other personal details. Remove them.

Security problems do not belong in a public issue; see [SECURITY.md](SECURITY.md).

## Before a larger change

For anything bigger than a small fix, please open an issue first and describe what you want to change and why. This avoids work on something that does not fit the project.

## Building and testing

You need macOS 14 or later on Apple Silicon and the Xcode command-line tools with Swift 5.10 or later.

```bash
cd app
swift test --scratch-path ~/.cache/intermezzo-test   # unit tests
./scripts/build_app.sh                               # builds dist/Intermezzo.app
```

Build outside folders synced by OneDrive or iCloud: the extended attributes those services add can break code signing.

## How the code is organised

- `app/Sources/IntermezzoKit` holds the logic that has no user interface. It is covered by unit tests (XCTest) and is where new logic should go, with a test written first.
- `app/Sources/IntermezzoApp` holds the SwiftUI and AppKit code (windows, settings panes, controllers).
- Keep functions small, prefer new values to mutation, handle errors explicitly, and match the style of the surrounding code.

## Texts and translations

The interface is available in English and Polish. UI strings are written in the code, and their translations live in `app/scripts/l10n/{pl,en}/*.py`. Every new visible text needs an entry in both languages. Check it with:

```bash
cd app
python3 scripts/gen_localization.py --check --orphans
```

The result must be `0 problems` and `0 possible unlocalized literals`. Descriptions in Settings use the shared `.settingsNote()` style, not their own fonts.

## Privacy rules for changes

Intermezzo does not collect usage data and has no account. A change must keep that true:

- no telemetry, analytics or third-party SDKs;
- no new network request unless the user turns the feature on, and any such request must be described in [PRIVACY.md](PRIVACY.md);
- no real network names, MAC addresses, VPN names, employer names or other personal data in tests, fixtures or screenshots.

## Pull requests

- Keep a pull request focused on one thing, with a short description of what and why.
- Use commit messages of the form `type: description`, where type is `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf` or `ci`.
- Make sure the tests and the translation check above pass, and update the README and PRIVACY.md if behaviour they describe changes.
- For a visible change, add a screenshot.
- If you used an AI tool to write a significant part of the change, say so in the description. It is welcome; it just has to be disclosed and reviewed by you.
