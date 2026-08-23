<div align="center">

<img src="assets/logo.png" alt="TravelTime" width="104">

# TravelTime

**A native macOS world clock, calendar, and meeting planner for people who work across time zones.**

Track any number of cities at a glance, then select and confirm a new macOS
system time zone when you land.

[![CI](https://github.com/susunola/TravelTime/actions/workflows/ci.yml/badge.svg)](https://github.com/susunola/TravelTime/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/susunola/TravelTime?sort=semver)](https://github.com/susunola/TravelTime/releases)
[![Platform](https://img.shields.io/badge/macOS-14.0%2B-black?logo=apple)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

[Install](#install) · [Features](#features) · [Usage](#usage) · [Build](#build-from-source) · [How it works](#how-it-works) · [FAQ](#faq)

</div>

---

<table>
  <tr>
    <td width="33%"><img src="docs/screenshots/traveltime-1.8.13.png" alt="TravelTime World clocks tab"></td>
    <td width="33%"><img src="docs/screenshots/traveltime-calendar-1.8.13.png" alt="TravelTime Calendar tab"></td>
    <td width="33%"><img src="docs/screenshots/traveltime-meeting-planner-1.8.13.png" alt="TravelTime Meeting planner tab"></td>
  </tr>
  <tr>
    <td align="center"><b>World clocks</b></td>
    <td align="center"><b>Calendar</b></td>
    <td align="center"><b>Meeting planner</b></td>
  </tr>
</table>

## Why

Most world-clock utilities show you what time it is elsewhere. The tedious part
of actually travelling is the other direction: you land, and your Mac is still
on the time zone you left. TravelTime keeps both halves in one place — a
multi-zone panel to read, and a safe, confirmed switch to act on.

No Electron, no telemetry, no account, and no runtime third-party dependencies.
The release binary is about 2 MB.

## Features

| | |
|---|---|
| **World clocks** | Local time in the menu bar and every tracked city in a clean panel. Each row shows Today / Yesterday / Tomorrow relative to the selected system zone, plus its live UTC offset. |
| **Safe zone switching** | Select a city, then confirm with the Switch button. TravelTime uses the standard macOS authorization dialog; your password is never stored or seen by the app. |
| **Searchable city picker** | Add from common cities or search the full macOS IANA time-zone catalogue. Duplicate IANA IDs are handled correctly — Berlin and Frankfurt can coexist as separate rows. |
| **Adaptive panel** | The window grows with normal content, keeps its footer fixed, hides native scroll tracks, and only scrolls the middle region when the display is genuinely too short. |
| **IP geolocation** | "Detect current location" resolves your city and zone, previews it, and switches on confirmation. |
| **Conflict detection** | If macOS *Set time zone automatically* is on, it will silently revert manual switches. The panel warns you and deep-links to the relevant System Settings pane. |
| **Custom avatar** | Drop in any image; stored under `~/Library/Application Support/TravelTime/`. |
| **In-app updates** | Checks GitHub Releases and verifies the download against a SHA-256 published in the release notes before installing. Works for both the current and the legacy `TimeZoneBar.app`-named assets. |
| **Meeting-time planner** | Move a time slider and see the corresponding time and working-hours status across every saved city. |
| **Solar + lunar calendar** | Browse months with Gregorian dates, Chinese lunar dates, solar terms, today/selection states, and event markers in a complete six-week grid. |
| **ICS calendars** | Import `.ics` files, expand common recurring-event rules, mark event days, and inspect the selected day's agenda. |
| **Offline public holidays** | Enable bundled 2026 holidays for China, Hong Kong, Singapore, Malaysia, and Thailand. Region-colored dots distinguish overlapping holidays, and each holiday includes a concise explanation. No API key, account, or network connection is required. |

## Requirements

- macOS 14.0 (Sonoma) or later — Apple silicon or Intel
- To build: Swift 5.9+ toolchain (Xcode 15+ or Command Line Tools)

## Install

### From a release

1. Download the latest `.app.zip` from the [Releases page](https://github.com/susunola/TravelTime/releases).
2. Unzip and move `TravelTime.app` to `/Applications`.
3. The build is ad-hoc signed and **not notarized**, so Gatekeeper will block the
   first launch. Right-click the app → **Open** → **Open** to allow it, or:

   ```bash
   xattr -dr com.apple.quarantine /Applications/TravelTime.app
   ```

### Build from source

```bash
git clone https://github.com/susunola/TravelTime.git
cd TravelTime

swift build -c release --disable-sandbox   # --disable-sandbox: see note below
python3 make_icon.py Resources             # generates AppIcon.icns, stdlib only
./build.sh                                 # bundle + sign + install to /Applications
```

Notes:

- `--disable-sandbox` is required on recent macOS, where SwiftPM's own sandbox
  fails with `sandbox_apply: Operation not permitted` while compiling the
  manifest. `build.sh` already passes it.
- `build.sh` signs with a self-signed identity named `TravelTime Developer`
  and installs straight to `/Applications`. If you do not have that certificate
  in your keychain, either create one in Keychain Access (*Certificate
  Assistant → Create a Certificate*, type: Code Signing) or change the identity
  to `-` for ad-hoc signing.
- `dist/` is emptied after a successful build on purpose: Launchpad indexes every
  `.app` **and every zip** it finds and would otherwise show ghost duplicates.

### Cutting a release

```bash
./build.sh release
```

This builds, installs, packages `release/TravelTime-<version>.app.zip`, and
prints its SHA-256. The release notes **must** contain a line
`SHA256: <64 hex chars>` — the updater verifies against it and aborts the install
if it is missing or does not match, so a release published without it cannot be
installed by existing users.

## Usage

| Action | Result |
|---|---|
| Click the Dock icon (or the menu bar clock) | Show / hide the panel |
| Click a zone row | Select it and reveal the Switch action |
| **Switch to _city_** | Change the macOS system time zone (authorization required) |
| Right-click a zone row | Switch to or remove that city (the current zone cannot be removed) |
| **Add city** | Search common cities or the complete IANA time-zone catalogue |
| **Detect current location** | IP geolocation → preview → confirm to switch |
| Click the avatar | Choose a custom image |
| **Calendar** tab | Browse Gregorian/lunar dates and inspect events or holidays |
| **Meeting planner** tab | Compare a candidate time and working-hours status across cities |
| Settings → Software Update | Check GitHub Releases and update in place |
| Settings → Calendar & Holidays | Import `.ics` calendars and enable offline holidays by region |
| Settings → Uninstall | Remove the app and all local data |
| **Quit TravelTime** | Quit |

## How it works

```
main.swift            NSApplication bootstrap
AppDelegate.swift     status item, panel window, 1 Hz tick (repaints on minute change)
MenuPanelView.swift   three-tab SwiftUI panel, adaptive content, shared footer
PanelHeader.swift     current time, displayed-zone date, avatar, rotating quote
CalendarCardView.swift Gregorian/lunar month grid and event/holiday details
EventStore.swift      ICS parsing, recurrence expansion, persistence, queries
HolidayStore.swift    bundled offline holiday catalogue and region selection
SettingsView.swift    preferences, cities, calendars, updater, uninstall
ZonePicker.swift      searchable common-city and IANA time-zone picker
TimeZoneStore.swift   @MainActor state, persistence, solar day/night, DST, day-offset
SystemZoneSwitcher    privileged `systemsetup -settimezone` via osascript
LocationDetector      IP geolocation with fallback endpoint
Updater.swift         GitHub Releases check, SHA-256 verify, in-place replace
```

Design notes worth knowing before you touch the code:

- **UI is AppKit-hosted SwiftUI.** An `NSWindow` with `.utilityWindow` style
  hosting an `NSHostingView`. Borderless and transparent-titlebar variants are
  deliberately avoided: on macOS 26 they trip a FrontBoard scene fence for
  self-signed apps and simply never render.
- **Privilege boundary.** Switching zones shells out to
  `/usr/sbin/systemsetup -settimezone` through `osascript ... with administrator
  privileges`, on a background queue with a 15 s timeout so an ignored dialog
  cannot hang the UI or leak a child process. The zone identifier is validated
  against `TimeZone.knownTimeZoneIdentifiers` *before* it reaches a shell string
  — geolocation responses are untrusted input on a privileged path.
- **Both geo endpoints are HTTPS** (`ipwho.is`, falling back to `ipapi.co`) for
  the same reason: a spoofable plaintext response would feed a privileged call.
  ip-api.com is not used — its free tier has no HTTPS, and ATS blocks plain HTTP.
- **Updates fail closed.** If no SHA-256 is found in the release notes, or it does
  not match the download, installation is aborted. The post-extraction bundle is
  located by `.app` extension (not by name), so legacy `TimeZoneBar.app` and
  current `TravelTime.app` releases both upgrade in place. The install replaces
  the running bundle wherever it lives (`~/Applications` included).
- **Zone rows are identified by UUID, not IANA ID**, because IANA IDs are not
  unique per city (Berlin and Frankfurt share `Europe/Berlin`). Persisted
  payloads from before the UUID field migrate on decode.
- **Auto-timezone detection reads the on-disk plist only** and assumes *off* when
  absent. On macOS 26 `defaults read` returns a stale cfprefsd value — observed
  reporting `Active = 1` long after the setting was turned off.
- **The minute tick is deduplicated.** The 1 Hz timer only publishes when the
  minute actually changes, collapsing 60 redraws per minute into one.
- **Public holidays are bundled data.** They never call timeanddate or another
  holiday API. Enabled regions are materialized as local all-day event sources;
  the current catalogue covers 2026 and is refreshed through app updates.
- **Calendar markers preserve provenance.** Holiday source names carry a stable
  region code, which drives the same low-saturation color in Settings, month
  markers, and event details. Imported ICS calendars use the app accent.

## Known limitations

Documented rather than hidden:

- **Not notarized.** Every release needs the Gatekeeper step above.
- **Day/night is approximate.** Latitude/longitude come from a 23-entry lookup
  table; zones outside it fall back to a longitude derived from the UTC offset at
  the equator. Good enough for a badge, not for astronomy.
- **IP geolocation is city-level at best**, and wrong on VPNs. Pick the zone
  manually when it matters.
- **Bundled public-holiday coverage currently ends in 2026.** Install a newer
  TravelTime release when a later catalogue becomes available. Malaysia data
  contains federal holidays only; state-only holidays are omitted.

## FAQ

**Every switch asks for my password. Why?**
Changing the system time zone is a privileged operation on macOS. The app uses
the system authorization dialog and never stores or sees the password.
Cancelling is treated as a deliberate "no" and reports no error.

**My switch was reverted.**
System Settings → General → Date & Time → *Set time zone automatically* takes
precedence. The panel detects this and links you straight there; turn it off and
the warning clears within 30 seconds.

**No icon in the menu bar?**
On macOS 26 the scene manager may refuse a status item for self-signed builds
with no Team ID. TravelTime is a regular Dock app, so click the Dock icon
instead — nothing is lost.

**Two TravelTime icons in Launchpad.**
Launchpad indexes bundle metadata inside zip files too, so a release zip sitting
in `~/Downloads` shows up as a second entry. Rename or remove the zip, then
`killall Dock`.

**I uninstalled but the icon is still there.**
Launchpad caches its tile list. Run `killall Dock` or log out and back in.

## Contributing

Bug reports and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).
For anything security-related, please read [SECURITY.md](SECURITY.md) first.

## License

[MIT](LICENSE) © susunola
