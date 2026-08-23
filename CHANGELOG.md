# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **Panel layout:** the calendar card now sits at the top of the panel and the
  time / avatar header moves to the bottom (above the footer), so the date is
  the first thing you see.

### Added
- **Calendar card (阳历 + 农历).** The panel now shows today's full solar date
  and weekday alongside the Chinese lunar date (干支年 / 月 / 日) and the
  current solar term, plus a 7-column month mini-grid with each day's lunar
  label and today highlighted. Shown by default; toggle in *Settings →
  Display* with "Show calendar (阳历 + 农历)". The lunar conversion is a
  classic 16-bit `lunarInfo` table covering 1900–2100, generated and
  byte-verified against the 6tail astronomical oracle (73,384 days, 0
  mismatches; all 24 solar terms per year match).
- `LICENSE` (MIT). The README had declared MIT since v1.3.0, but the file was
  missing, so GitHub reported the repository as unlicensed.
- `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`, and issue / pull request
  templates.

### Changed
- README rewritten: verified feature list, architecture overview, documented
  privilege and update-verification model, release-cutting instructions, and a
  **Known limitations** section.
- Theme screenshots regenerated. All four are now captured from the same build
  and zone set, per-window so no desktop is visible, from a throwaway bundle ID
  so no personal preferences or avatar appear in the images.
- CI passes `--disable-sandbox` (the workflow could not build without it),
  caches `.build`, and now assembles and verifies an ad-hoc signed app bundle to
  catch `Info.plist` and bundle-layout regressions.

### Fixed
- `docs/screenshots/theme-minimal.png` was not the app at all — an unrelated
  editor window had been committed in its place.
- README claimed 25 preset cities; the actual list has 24.
- README's build instructions omitted `--disable-sandbox`, which recent macOS
  requires (`swift build` otherwise fails with `sandbox_apply: Operation not
  permitted`), and did not mention that `build.sh` needs a self-signed
  `TimeZoneBar Developer` certificate.
- Removed a FAQ entry that told users to enable the menu bar icon under
  *Siri & Spotlight → Spotlight Privacy*. No such mechanism exists, and nothing
  in the codebase relates to Spotlight.
- **Panel did not size to its zones at launch.** `AppDelegate` only called
  `updatePanelHeight()` from store callbacks assigned *after* the store had
  already loaded its zones, so the initial window stayed at the hardcoded 640
  pt regardless of zone count (measured 672 pt at both 3 and 12 zones). The
  sizing rule is now a pure static function `AppDelegate.panelContentHeight`,
  exercised by three new unit tests, and `setupPanel()` calls it explicitly
  once the store and window exist.
- **In-app update could not install legacy releases.** `Updater` hardcoded
  `TravelTime.app` after extraction, so any release that extracted to the
  former `TimeZoneBar.app` (every published release up to and including
  v1.3.3) failed with "Could not unzip the installer". Resolution now scans
  the unzip directory for the first `.app` bundle, extracted into a tested
  pure helper `Updater.appBundle(in:)`. Combined with the new
  `./build.sh release` flow, users on v1.3.3 can now upgrade in place.

### Added (1.3.4 review round)
- `TimeZoneStore.dayLabel(for:)` — the Today/Yesterday/Tomorrow label as a
  shared pure function with unit tests.

### Fixed (1.3.4 review round)
- **Editorial theme labelled every row "Today".** `MenuPanelView` hardcoded
  the text in the editorial branch while the other three themes used
  `dayLabel`, so cross-day zones (New York, Tokyo…) showed the wrong day.
  All themes now share `TimeZoneStore.dayLabel(for:)`.
- **Header and menu-bar dates used the host time zone.** The time shown is the
  selected zone's, but the date beside it was formatted in the host zone, so
  an hour either side of midnight could show 01:30 with the wrong weekday.
  Both `dateText` and the optional menu-bar date now format in the displayed
  zone.
- **Location detection always failed on the primary endpoint.** ip-api.com's
  free tier has no HTTPS at all, and ATS blocks plain HTTP, so every call
  timed out and fell back to ipapi.co. The primary endpoint is now ipwho.is
  (free, HTTPS). Also, both providers report throttling as HTTP 200 with an
  `error` field, which the decoder previously misread; `GeoResult` now parses
  the flat and nested shapes and surfaces a "rate-limited" message.
- **Panel could grow past the screen.** With many zones the computed height
  exceeded the visible frame and macOS clamped it unpredictably. The height is
  now capped against `NSScreen.visibleFrame`.
- **`build.sh` killed unrelated processes.** `pkill -9 -f TravelTime` matched
  any command line containing the string (e.g. an editor with the repo open);
  it now matches the deployed binary path exactly.
- **Updater targeted a hardcoded `/Applications/TravelTime.app`.** An app
  installed in `~/Applications` would have spawned a second copy. The updater
  now replaces `Bundle.main.bundlePath`, and `appBundle(in:)` prefers
  `TravelTime.app` deterministically instead of a filesystem-order first match.
- **`Asia/Kolkata` coordinates were Kolkata's** while the picker labels it
  New Delhi (about 45 minutes of sun-position drift). Now `(28.6, 77.2)`.
- Removed the unused `BorderlessPanel` class.

### Changed (1.3.4)
- Version bumped to 1.3.4 — the previous release's fixes could never reach
  users because `CFBundleShortVersionString` still said 1.3.3 and the updater
  only fires on a strictly greater version.
- Theme preview swatch now ticks from the store clock instead of `Date()`, so
  the mini clock updates with the panel.

### Known issues
- *None at the time of writing. If you find one, open an issue — see
  `CONTRIBUTING.md` for the report template.*

## [1.3.3] — 2026-08-17

### Fixed
- 15 second timeout on `switchTo()`, so cancelling the authorization dialog no
  longer leaves a permanent spinner.
- 10 second timeout on `detectLocation()`, so a network stall no longer leaves a
  permanent "Detecting…" state.
- Distinct geolocation error messages (network unavailable vs. no time zone
  returned).
- `save()` surfaces failures instead of failing silently.
- Launch-at-login shows an alert when the toggle fails instead of silently
  reverting.
- Panel width mismatch between `AppDelegate` (340) and `MenuPanelView` (330).
- Menu bar time refreshes immediately on wake from sleep.

### Changed
- More tolerant SHA-256 parsing from release notes (several label formats).
- `ZoneRowView` caches its day/night computation, previously evaluated twice per
  row.

### Added
- Rebranded from TimeZoneBar to TravelTime.
- Four themes: Minimal, Glass, Midnight, Editorial.
- In-place zone management (replace / remove on hover, add from a preset list).
- Custom avatar support.
- Auto-timezone conflict monitor with a deep link to System Settings.

## [1.3.2] — 2026-08-17

### Fixed
- Uninstall now removes every known leftover path: caches, saved application
  state, preferences plist, `HTTPStorages`, logs, containers, and temporary
  update directories. The Launchpad tile is cleared via `killall Dock`.

## [1.3.1] — 2026-08-17

### Fixed
- Minimum macOS corrected to 14.0 (was declared 13.0).
- More robust version parsing for update checks.
- HTTP status codes are checked on all GitHub API calls.
- SHA-256 verification is fail-closed: a missing checksum aborts the update.
- Unzip failures are detected via exit status.
- Day/night indicator uses a solar-position calculation instead of a fixed
  06:00–18:00 window.
- Reading the system auto-timezone flag no longer blocks the main thread.

## [1.3.0] — 2026-08-17

### Changed
- Full English localization across UI, README, code comments and build scripts.

## [1.2.0] — 2026-08-17

### Added
- Day/night indicator per zone.
- Daylight saving time badge.
- Optional date in the menu bar, and a 12/24-hour format toggle.

## [1.1.1] — 2026-08-17

### Fixed
- Update downloads use the GitHub API asset endpoint, fixing 404s from
  `releases/download` URLs.

## [1.1.0] — 2026-08-17

### Added
- In-app updates distributed through GitHub Releases, with SHA-256 verification
  and in-place replacement.

## [1.0.0] — 2026-08-17

### Added
- Initial release as TimeZoneBar: `NSStatusItem` menu bar clock, multiple time
  zones, one-click system time zone switching, and IP-based location detection.

[Unreleased]: https://github.com/susunola/TravelTime/compare/v1.3.3...HEAD
[1.3.3]: https://github.com/susunola/TravelTime/releases/tag/v1.3.3
[1.3.2]: https://github.com/susunola/TravelTime/releases/tag/v1.3.2
[1.3.1]: https://github.com/susunola/TravelTime/releases/tag/v1.3.1
[1.3.0]: https://github.com/susunola/TravelTime/releases/tag/v1.3.0
[1.2.0]: https://github.com/susunola/TravelTime/releases/tag/v1.2.0
[1.1.1]: https://github.com/susunola/TravelTime/releases/tag/v1.1.1
[1.1.0]: https://github.com/susunola/TravelTime/releases/tag/v1.1.0
