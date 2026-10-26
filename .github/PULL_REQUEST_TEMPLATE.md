## What and why

<!-- A short description of the change and the reason for it. Link the issue if there is one. -->

## Checklist

- [ ] `swift test --scratch-path ~/.cache/intermezzo-test` passes (run in `app/`).
- [ ] `python3 scripts/gen_localization.py --check --orphans` ends with 0 problems and 0 unlocalized literals (run in `app/`), and new visible texts exist in both `pl` and `en`.
- [ ] New logic without a user interface is in `IntermezzoKit` and has a test.
- [ ] No telemetry, and no new network request unless the user turns the feature on (and it is described in `PRIVACY.md`).
- [ ] No personal data (network names, MAC addresses, VPN or employer names) in tests, fixtures or screenshots.
- [ ] README or `PRIVACY.md` updated if the behaviour they describe changed.
- [ ] A screenshot is attached for a visible change.

## AI assistance

<!-- If an AI tool wrote a significant part of this change, say so here. -->
