<div align="center">

<img src="assets/logo.png" alt="TravelTime" width="104">

# TravelTime

**A native macOS menu bar clock for people who work across time zones.**

Track any number of cities at a glance, and switch your Mac's system time zone
with a single click when you land.

[![CI](https://github.com/susunola/TravelTime/actions/workflows/ci.yml/badge.svg)](https://github.com/susunola/TravelTime/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/susunola/TravelTime?sort=semver)](https://github.com/susunola/TravelTime/releases)
[![Platform](https://img.shields.io/badge/macOS-14.0%2B-black?logo=apple)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

[Install](#install) · [Features](#features) · [Themes](#themes) · [Build](#build-from-source) · [How it works](#how-it-works) · [FAQ](#faq)

</div>

---

## Why

Most world-clock utilities show you what time it is elsewhere. The tedious part
of actually travelling is the other direction: you land, and your Mac is still
on the time zone you left. TravelTime keeps both halves in one place — a
multi-zone panel to read, and a one-click switch to act on.

No dependencies, no Electron, no telemetry, no account. One ~700 KB binary.

## Features

| | |
|---|---|
| **Multi-zone panel** | Local time in the menu bar, all tracked cities in the panel. Each row is labelled Today / Yesterday / Tomorrow relative to your system zone, so you never do the mental date arithmetic. |
| **One-click zone switching** | Click a row to move your entire Mac to that zone. Uses the standard macOS authorization dialog — no password is ever stored or seen by the app. |
| **Day/night at a glance** | A sun or moon per row, computed from a solar-elevation approximation, tells you whether it is a reasonable hour to call. |
| **DST badge** | Zones currently on daylight saving time are tagged, so a shifted offset is never a surprise. |
| **Live zone management** | Hover a row to replace or remove it; add from 24 preset cities. The panel grows or shrinks to fit the list. Duplicate IANA IDs are handled correctly — Berlin and Frankfurt can coexist as separate rows. |
| **IP geolocation** | "Detect current location" resolves your city and zone, previews it, and switches on confirmation. |
| **Conflict detection** | If macOS *Set time zone automatically* is on, it will silently revert manual switches. The panel warns you and deep-links to the relevant System Settings pane. |
| **Four themes** | Minimal, Glass, Midnight, Editorial — switchable at runtime from Settings → Appearance. |
| **Custom avatar** | Drop in any image; stored under `~/Library/Application Support/TravelTime/`. |
| **In-app updates** | Checks GitHub Releases and verifies the download against a SHA-256 published in the release notes before installing. Works for both the current and the legacy `TimeZoneBar.app`-named assets. |
| **Meeting-time planner** | Move a time slider and see the corresponding time and working-hours status across every saved city. |
| **Public holidays** | Enable bundled offline holidays for China, Hong Kong, Singapore, Malaysia, and Thailand. No account, API key, or network connection is required. |

## Themes

<table>
<tr>
<td width="50%"><img src="docs/screenshots/theme-minimal.png" alt="Minimal theme"></td>
<td width="50%"><img src="docs/screenshots/theme-glass.png" alt="Glass theme"></td>
</tr>
<tr>
<td align="center"><b>Minimal</b> — flat rows, hairline dividers</td>
<td align="center"><b>Glass</b> — card surfaces, generous spacing</td>
</tr>
<tr>
<td width="50%"><img src="docs/screenshots/theme-midnight.png" alt="Midnight theme"></td>
<td width="50%"><img src="docs/screenshots/theme-editorial.png" alt="Editorial theme"></td>
</tr>
<tr>
<td align="center"><b>Midnight</b> — dark, cyan accent</td>
<td align="center"><b>Editorial</b> — serif display type, quote-led</td>
</tr>
</table>

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
| Click a zone row | Switch the system time zone (authorization required) |
| Hover a row → ↻ | Replace that row with another city |
| Hover a row → ✕ | Remove that row (the current zone cannot be removed) |
| **Add time zone ⌄** | Add from 24 preset cities |
| **Detect current location** | IP geolocation → preview → confirm to switch |
| Click the avatar | Choose a custom image |
| Settings → Appearance | Switch theme |
| Settings → Software Update | Check GitHub Releases and update in place |
| Settings → Calendar & Holidays | Enable offline holiday calendars by country or region |
| Settings → Uninstall | Remove the app and all local data |
| **Quit TravelTime** | Quit |

## How it works

```
main.swift            NSApplication bootstrap
AppDelegate.swift     status item, panel window, 1 Hz tick (repaints on minute change)
MenuPanelView.swift   SwiftUI panel + ThemePalette (4 themes)
SettingsView.swift    preferences, theme picker, updater UI, uninstall
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

## Known limitations

Documented rather than hidden:

- **Not notarized.** Every release needs the Gatekeeper step above.
- **Day/night is approximate.** Latitude/longitude come from a 23-entry lookup
  table; zones outside it fall back to a longitude derived from the UTC offset at
  the equator. Good enough for a badge, not for astronomy.
- **IP geolocation is city-level at best**, and wrong on VPNs. Pick the zone
  manually when it matters.

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
