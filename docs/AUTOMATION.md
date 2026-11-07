# Automating Intermezzo

Three ways in, one way out. Nothing here talks to a server: it is all on your Mac.

## 1. Read the state

Turn on **Settings › General › Automation: state and events › Publish the state and events for other programs**
(off by default). Intermezzo then keeps this file current (mode 0600) and refreshes it at least once a minute:

```
~/Library/Application Support/Intermezzo/state.json
```

```json
{
  "appVersion" : "1.44.0",
  "timer" : "running",                      // running | paused | onBreak
  "pauseReasons" : [],                      // why it is held: manual, userAway, outsideWorkingHours, inMeeting, ...
  "nextBreakAt" : "2026-11-08T09:41:00Z",   // while running
  "nextBreakKind" : "short",
  "breakKind" : null,                       // short | long, while on a break
  "breakEndsAt" : null,
  "inWorkZone" : true,                      // null when no work-zone source is switched on
  "inWorkingHours" : null,                  // null when the working hours are not enforced
  "workZoneSources" : ["vpn", "lan"],       // calendar, vpn, wifi, place, lan, focus
  "inMeeting" : false,
  "watchingVideo" : false,
  "focusActive" : false,
  "focusModes" : [],
  "away" : false,                           // no input for the idle time: the timer is held
  "screenLocked" : false,                   // locked, asleep or on the screen saver
  "vpnConnected" : true,
  "lightOn" : true,
  "lightKelvin" : 5200,
  "keepAwake" : false,
  "updatedAt" : "2026-11-08T09:12:03Z"
}
```

There are no event titles, network names or places in it.

## 2. Listen for events

With publishing on, Intermezzo posts two notifications to `DistributedNotificationCenter`:

| Name | When | userInfo |
|---|---|---|
| `com.automit.Intermezzo.state` | every change of the state | `json`, `timer` |
| `com.automit.Intermezzo.event` | every event | `event`, `json` |

Events: `breakBegan`, `breakCompleted`, `breakSkipped`, `breakPostponed`, `timerPaused`, `timerResumed`, `zoneEntered`,
`zoneLeft`, `meetingBegan`, `meetingEnded`, `focusOn`, `focusOff`, `awayBegan`, `awayEnded`, `screenLocked`,
`screenUnlocked`, `vpnConnected`, `vpnDisconnected`.

Listening from a shell (Swift one-liner):

```
swift -e 'import Foundation; DistributedNotificationCenter.default().addObserver(forName: .init("com.automit.Intermezzo.event"), object: nil, queue: .main) { print($0.userInfo?["event"] ?? "") }; RunLoop.main.run()'
```

## 3. Send commands

`intermezzo://…` addresses (see Settings › General › Automation, each with a Copy button), for example
`intermezzo://break/long`, `intermezzo://postpone/10m`, `intermezzo://pause`, `intermezzo://awake/for/2h`.

`intermezzo://state?x-success=<url>` hands the state to another app: it opens `<url>` with the state added as the `state`
query item. It works only while publishing is on and never for `http`, `https` or `file` addresses, so a web page cannot
use it to read your state.

## 4. Run your Shortcuts from Intermezzo

**Settings › Breaks › Break Actions** has the action **Run Shortcut** and triggers that are not tied to a break:
timer paused or resumed, entering or leaving the work zone, a meeting starting or ending, Focus on or off, going idle or
returning, the screen locking or unlocking, a VPN connecting or disconnecting.

Every action, whatever its kind, has **conditions** (the filter icon): only in the work zone or only outside it, not during
a meeting, only with the screen unlocked, and a least pause between runs.

A shortcut run this way receives a JSON file as its input:

```json
{ "trigger": "zoneEntered", "event": "zoneEntered", "state": { ...the state above... } }
```

In the shortcut, use **Get Dictionary from Input**, then **Get Dictionary Value**. Shortcuts started from Intermezzo may run
for up to a minute.

## 5. Intermezzo's actions in the Shortcuts app

The Shortcuts app lists Intermezzo's own actions (search "Intermezzo" in the action list):

- **Conditions for "If"** (they return yes or no): Is a break on, Is the break timer running, Is the Mac in the work zone,
  Is a meeting on, Is Focus on, Is the Mac idle.
- **State as one thing**: **Get Intermezzo state** returns an item whose properties you pick from a list, like the
  properties of a VPN: timer, a break is on, in the work zone, the work-zone sources (a list of calendar, VPN, Wi-Fi,
  place, LAN, Focus), a meeting is on, Focus is on, idle, screen locked, VPN connected, kind of the next break, seconds
  until it, when the next break starts and when the current one ends.
- **Single values**: Intermezzo timer state (counting down, held or on a break: Shortcuts offers these in "If"),
  Seconds until the next break (-1 when the timer is not counting down), Kind of the next break (short or long), Full
  Intermezzo state (JSON text).
- **Commands**: Start a break (short or long), Skip the break, Postpone the break (minutes), Pause, Resume and Reset the
  break timer, Turn Light on or off, Turn keep-awake on or off.

SwiftPM does not write the metadata Shortcuts reads (`Metadata.appintents`), so `scripts/generate_app_intents_metadata.sh`
runs Apple's `appintentsmetadataprocessor` after the build (it needs full Xcode; the step is soft, so without it the app
still works and only the Shortcuts actions are missing). The first time, the Shortcuts app may need a moment to notice
a new or updated app; if the actions do not show, open Intermezzo once, then restart Shortcuts.
