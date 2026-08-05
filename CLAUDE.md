# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this project is

`geo_probe` — a **diagnostic Flutter app**, not a product. It validates the
geolocation-attendance architecture from the Clockster "Geolocation
Attendance & Presence" engineering spec (§5): classic `CLLocationManager`
region monitoring + Significant Location Change on iOS, platform
`GeofencingClient` on Android (currently stubbed). Its purpose is to measure
real geofence delivery latency and survivability (force-quit, reboot,
Background App Refresh off) on real devices. Full architecture doc:
[README.md](README.md). Distribution to testers:
[docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

Keep it simple: no Clean Architecture layers, no bloc — `ChangeNotifier`
(`AppState`) + direct sqflite queries from screens.

## Commands

```bash
flutter run                                   # dev run (device/simulator)
flutter analyze                               # lint — keep at zero issues
flutter gen-l10n                              # regenerate l10n after ARB edits
flutter build ios --debug --no-codesign       # compile check incl. Swift
flutter build ipa --release                   # TestFlight/Ad Hoc build
flutter test integration_test/longpress_test.dart -d <sim-udid>   # UI smoke
flutter test integration_test/pipeline_test.dart  -d <sim-udid>   # JSONL→SQLite
flutter test integration_test/geofence_test.dart  -d <sim-udid>   # E2E (needs driver, see below)
```

There are no meaningful unit tests (`test/widget_test.dart` is a placeholder):
everything interesting depends on platform channels and CoreLocation, so
verification happens via integration tests on a simulator/device.

### E2E geofence test driver

`geofence_test.dart` expects an external script teleporting the simulator
in/out of the zone at 51.1694,71.4491 (r=200 m) and granting permission
while the app is installed:

```bash
xcrun simctl privacy <UDID> grant location-always com.clockster.geoProbe
xcrun simctl location <UDID> set 51.2400,71.5200   # outside
xcrun simctl location <UDID> set 51.1694,71.4491   # inside → ENTER ~20 s
```

Run grants/teleports in a background loop concurrently with the test
(permission grants don't survive the test runner's reinstall, so grant
*during* the run).

## Layout

```
lib/
  main.dart            4-tab shell (Map/Journal/Settings/Diagnostics), resume hook
  app_state.dart       AppState: regions, config, ingestion, Telegram logger
  db.dart              ProbeDb (sqflite): regions/events/config tables
  native_bridge.dart   channel wrapper; Android-safe fallbacks on every call
  models.dart          Region, GeoEvent, EventType, AppConfig
  wording.dart         human-readable labels (event types, statuses, values)
  l10n/                ARB (en template, ru) + generated app_localizations*
  ui/                  map_screen, journal_screen, settings_screen,
                       diagnostics_screen
ios/Runner/AppDelegate.swift   ALL native iOS code (AppDelegate + LocationService)
android/.../MainActivity.kt    channel stubs (safe defaults)
android/.../GeofenceBroadcastReceiver.kt, BootReceiver.kt   skeletons + checklists
integration_test/              longpress, pipeline, geofence E2E
```

## Invariants — do not break these

1. **Native-first persistence.** Every native event is appended to
   `Application Support/geo_probe/native_events.jsonl` *before* anything
   else; the EventChannel sink is only a live-UI optimization. The Flutter
   engine may not exist when events arrive (terminated-state relaunch).
   Dart drains the file on init/resume; `ProbeDb.insertEvents` deduplicates
   by uuid and **returns only the genuinely new events** — Telegram
   forwarding relies on that return value to avoid double-sends. Never
   bypass it with raw inserts.

2. **Two timestamps per event.** `event_ts` = the event's own time (from the
   CLLocation fix when available), `received_ts` = callback time. The
   difference is the delivery latency this app exists to measure. Never log
   receipt time as event time (§4.2 of the spec — the defect that turned
   "slow" into "lying").

3. **No `UIBackgroundModes: location`** in Info.plist, ever (App Review
   2.5.4 trigger; region monitoring and SLC don't need it). Related:
   `manager.allowsBackgroundLocationUpdates` stays `false`.
   `UIBackgroundModes` currently contains only `fetch` — required by the
   heartbeat BGAppRefreshTask; that one is fine.

4. **`LocationService.shared.bootstrap(...)` must run inside
   `didFinishLaunchingWithOptions` before `super`** — on a location-triggered
   relaunch the CLLocationManager delegate must exist before launch ends or
   the event is lost. `launchOptions[.location]` detection feeds the
   `relaunch` event (the key survivability metric).

5. **Config and regions are mirrored to `UserDefaults`** (native side) so a
   terminated-state relaunch knows what to monitor without the engine.
   Dart's SQLite is the UI source of truth; native UserDefaults is the
   engine's. `syncRegions`/`setConfig` keep them aligned — preserve that on
   any change.

6. **Permissions flow is deliberately two-step.** Startup
   (`requestInitialPermissions`): notifications + WhenInUse, only if
   notDetermined, never escalates. The Always upgrade is ONLY behind
   Settings → Request permissions — iOS shows that prompt once per install.
   `locationManagerDidChangeAuthorization` re-runs `applyConfig()` on grant
   (region registration fails with kCLError 4 while unauthorized; without
   the re-arm, zones created pre-grant stay dead until next launch).

7. **Idempotent event handling everywhere.** Duplicate EXITs and the iOS
   post-reboot double-fire are documented platform behaviour; the uuid PK
   plus `insertEvents` filtering absorb them.

8. **All `getCurrentLocation` callers are queued** (`pendingLocationResults`
   array in Swift) — overlapping calls must each get an answer or the Dart
   Future hangs forever. Don't collapse it back to a single slot.

9. **No `autofocus: true` on TextFields inside dialogs** — summoning the
   keyboard with the dialog hangs debug sessions on physical iOS devices
   under the VSCode debugger (flutter/flutter#123021).

10. **iOS share sheet needs an anchor**: any `SharePlus` call must pass
    `sharePositionOrigin` derived from a real RenderBox (see the export
    button in journal_screen), or share_plus throws on iPad/recent iOS.

11. **Heartbeat BGTask discipline.** `BGTaskScheduler.register` happens in
    `bootstrap()` (must complete before launch ends); the identifier
    `com.clockster.geoProbe.heartbeat` is fixed in Info.plist. The heartbeat
    writes JSONL **before** notification/Telegram (invariant 1 applies), and
    its `event_ts` is "now" (`timestampFromFix: false`) — the possibly-cached
    fix must not backdate it. Heartbeat Telegram goes out natively from
    Swift; never add `heartbeat` to `AppState._tgTypes` or the JSONL drain
    double-sends it. `heartbeatEnabled`/`heartbeatIntervalMin` defaults in
    Swift (true/60) must equal the `AppConfig` defaults.

## Localization

Standard gen-l10n: edit `lib/l10n/app_en.arb` (template) **and**
`app_ru.arb`, then run `flutter gen-l10n`. Every user-facing string goes
through `AppLocalizations`; human wording for technical values lives in
`lib/wording.dart` (event types, auth statuses, app states, diagnostics
values). Raw technical codes stay in the DB/JSON export — do not localize
stored data. Native iOS notification titles are localized in Swift
(`postNotification`), RU/EN by device language. Russian plurals use ICU
`few/many` categories — keep them when editing `dwellLine`-style keys.

## Platform-channel contract

One `MethodChannel('geo_probe/engine')` + one
`EventChannel('geo_probe/events')`. The full method table with argument/
return shapes is in [README.md §3](README.md). When adding a method:
implement iOS in `AppDelegate.swift`, add a **safe default** to
`MainActivity.kt` (Android must degrade gracefully, never crash), wrap it in
`NativeBridge` (which already swallows `MissingPluginException` /
`PlatformException`), and update README §3.

## Event types

`enter`, `exit`, `slc`, `state_initial`, `relaunch`, `heartbeat`,
`permission_change`, `error` — defined in `models.dart` (`EventType`).
Adding one requires: constant + `all` list, label in both ARB files +
`wording.dart`, icon/color in journal_screen, and (if native-originated) the
Swift `writeEvent` call. Telegram forwards only the types in
`AppState._tgTypes` — heartbeats and `state_initial` are deliberately
excluded there; the periodic background heartbeat posts to Telegram natively
from Swift instead (see invariant 11).

## Android status

Stub only. The implementation checklist (GeofencingClient with **mutable**
PendingIntent, JSONL parity store, `ACCESS_BACKGROUND_LOCATION` two-step
request, BootReceiver re-registration, diagnostics map) lives in
[README.md §4](README.md) and as comments in the receiver skeletons. The
Dart layer needs no changes when Android lands — implement to the channel
contract.

## Conventions

- Code comments and test names: English only.
- Do not create new .md files unless explicitly requested.
- `flutter analyze` must stay clean; the project uses `flutter_lints`.
- Signing: automatic, team `SJ8ZA5APB3` (Clockster PTE LTD), bundle id
  `com.clockster.geoProbe`. iOS deployment target 14.0.
- Map tiles are public OSM — keep the `userAgentPackageName` and don't hit
  tile servers from tests in tight loops.
- Journal day filter is the local calendar day of `event_ts`: events from
  before midnight live on yesterday's page (recurring support question, not
  a bug).
