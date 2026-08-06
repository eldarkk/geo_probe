# geo_probe

Diagnostic Flutter app that validates the geolocation attendance architecture
from the *Geolocation Attendance & Presence* engineering spec (§5: platform
Geofence API on Android, classic `CLLocationManager` region monitoring on iOS,
no third-party background-geolocation SDK).

It is **not a product**. Its job is to answer, with real numbers from real
devices: how fast geofence events are delivered, whether they survive
force-quit / reboot / Background App Refresh off, and how Significant Location
Change (SLC) behaves as a backup channel. Everything is logged locally with
dual timestamps so delivery latency is measurable.

- **iOS: fully implemented** (Swift, all engine code in
  `ios/Runner/AppDelegate.swift`).
- **Android: stubbed** — the platform-channel contract is wired up and returns
  safe defaults; skeletons with implementation checklists are in place. See
  [What remains on Android](#what-remains-on-android).

---

## 1. High-level architecture

```
┌────────────────────────── Flutter (Dart) ──────────────────────────┐
│  UI: Map (flutter_map/OSM) · Journal · Settings · Diagnostics      │
│  AppState (ChangeNotifier) — regions, config, ingestion, Telegram  │
│  ProbeDb (sqflite) — regions / events / config tables              │
│  NativeBridge — MethodChannel 'geo_probe/engine'                   │
│                 EventChannel  'geo_probe/events'                   │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ platform channels
┌──────────────────────────────┴─────────────────────────────────────┐
│ iOS LocationService (Swift singleton)                              │
│   CLLocationManager: region monitoring + SLC + one-shot fixes      │
│   Event sink (live) + JSONL append (always) → drained by Dart      │
│   UNUserNotificationCenter local notifications                     │
│   Config & regions mirrored to UserDefaults (survive relaunch)     │
└────────────────────────────────────────────────────────────────────┘
```

**Design rule #1 — native-first persistence.** Every native event is appended
to a JSONL file *before* anything else. The Flutter engine may not exist when
an event arrives (terminated-state relaunch), so the JSONL file is the source
of truth; the Dart side drains it on every launch/resume and deduplicates by
event UUID. The live `EventChannel` sink is only an optimization for instant
UI updates while the engine is running.

**Design rule #2 — two timestamps per event.** `event_ts` is the event's own
timestamp (from the `CLLocation` fix when available); `received_ts` is when
our callback ran. `received_ts − event_ts` = delivery latency. Never log
receipt time as event time — that is the §4.2 defect that turned "slow" into
"lying" in the previous generation.

**Design rule #3 — no `UIBackgroundModes: location`.** Phase-1 architecture
per the spec: region monitoring and SLC do not require the background-location
plist key (the App-Review 2.5.4 trigger), and both relaunch the app after
termination when Always authorization is granted.

---

## 2. iOS implementation

### 2.1 Process bootstrap (`AppDelegate.swift`)

- `LocationService.shared.bootstrap(launchedByLocation:)` is called **inside
  `didFinishLaunchingWithOptions`, before `super`**. When iOS relaunches a
  terminated app for a location event, the `CLLocationManager` delegate must
  exist before `didFinishLaunching` returns or the event is dropped.
- `launchOptions[.location] != nil` is detected and logged as a `relaunch`
  event — the primary survivability metric (did the app come back from
  force-quit / OS kill for a geofence event?).
- Channels are attached in `didInitializeImplicitFlutterEngine` (the Flutter
  3.44 UIScene template) via `engineBridge.applicationRegistrar.messenger()`.
- App state (`foreground` / `background` / `launching` /
  `terminated-relaunch`) is tracked with NotificationCenter observers, never
  by reading `UIApplication.applicationState` from callbacks (thread-safety).

### 2.2 Region monitoring

- `CLCircularRegion` per user-defined zone, `notifyOnEntry/Exit` from config.
- Regions and config are mirrored to `UserDefaults` so a terminated-state
  relaunch knows what it monitors without the Flutter engine.
- Radius is clamped to `maximumRegionMonitoringDistance`; the UI enforces
  100–500 m (Apple/Google recommend ≥100–150 m) and the 20-region iOS limit.
- `requestState(for:)` after every (re)registration → `state_initial` events
  (`inside`/`outside`). Needed because geofences only fire on *crossings*: a
  user already inside a new zone would otherwise never produce an event.
- **Re-arm on authorization change**: registration fails with `kCLError 4`
  while authorization is insufficient, so `locationManagerDidChangeAuthorization`
  re-runs `applyConfig()` once WhenInUse/Always is granted. Without this,
  zones created before the grant stayed dead until the next app launch
  (found empirically via the simulator E2E test).

### 2.3 Significant Location Change

- Toggled from settings; `start/stopMonitoringSignificantLocationChanges`.
- Cell-tower granularity (~500 m–1 km), delivers via `didUpdateLocations`.
  Since the app never runs continuous foreground updates, an unsolicited
  `didUpdateLocations` delivery is classified as `slc` — but only while SLC
  monitoring is enabled; otherwise it is logged as `error` (a late one-shot
  fix arriving after a `didFailWithError` must not masquerade as movement).
  Pending one-shot `getCurrentLocation` requests are consumed first and not
  logged.
- Also relaunches a terminated app when Always is granted — the backup
  channel to region monitoring.

### 2.4 Permissions

- **On first launch** (`requestInitialPermissions`, called from
  `AppState.init`): notification prompt + WhenInUse location prompt, each
  only if not yet determined. Never escalates.
- **Manual escalation** (Settings → Request permissions): if status is
  WhenInUse → `requestAlwaysAuthorization()`. iOS shows the Always upgrade
  prompt **once per install**, and may defer it — hence it is spent
  deliberately, not on autostart.
- Every status change is logged as a `permission_change` event. Note: iOS
  always delivers one such callback at manager creation, so every cold start
  produces one — useful as a process-start marker.
- Downgrading Always → WhenInUse in system settings **kills the app process**
  and silences background events; on-device detection is only possible at the
  next launch. Server-side silence detection remains the real answer (spec
  §6.2).

### 2.5 Event pipeline

```
CL delegate callback (main thread)
  └─ writeEvent(type, regionId?, location?, detail?)
       ├─ builds dict: uuid, type, region_id, lat/lng/accuracy,
       │               event_ts, received_ts, app_state, battery, detail
       ├─ append JSON line to Application Support/geo_probe/native_events.jsonl
       │    (serial ioQueue, survives engine absence)
       ├─ push to EventChannel sink if attached (main queue)
       └─ local notification (enter/exit/slc/relaunch, if enabled)

Dart side (AppState)
  ├─ live: eventStream.listen → insert into SQLite (INSERT OR IGNORE by uuid)
  └─ drain: on init + every app resume → drainNativeEvents()
       native reads JSONL, returns array, deletes file → batch insert
```

Idempotency is mandatory: duplicate EXITs and the iOS double-fire on the
first event after reboot are documented platform behaviours; the uuid primary
key absorbs them.

### 2.6 Diagnostics ("heartbeat")

`getDiagnostics` snapshots everything that can silently kill the feature
(spec §6.2): authorization status, precise/approx accuracy, location services,
**Background App Refresh** (an OS-level kill switch independent of location
permission), notification permission, monitored-region count, engine config,
`launchedByLocationThisRun`, app/OS versions, battery. A heartbeat event with
this snapshot is written on every foreground entry and shown on the
Diagnostics tab (states that break background delivery are highlighted red).

**Background heartbeat (BGAppRefreshTask).** A periodic status report that
runs without the UI: permission status, a one-shot fix (falls back to the
last cached fix after 10 s — with WhenInUse-only auth background requests
deliver nothing), Background App Refresh, notification permission, battery,
Low Power Mode, monitored-zone count. The pipeline is native-only, so it
works even when the Flutter engine never spins up: JSONL heartbeat event
*first* (invariant), then a local notification, then Telegram directly from
Swift via URLSession (credentials mirrored to UserDefaults by `setTelegram`).
`event_ts` is the heartbeat's own "now" — a cached fix must not backdate it,
its age is recorded as `fixAgeSec` in `detail`. The configured interval
(Settings, default 60 min) is only `earliestBeginDate`: iOS decides real
delivery by usage patterns, battery and BAR — the requested-vs-actual gap is
itself a measurement this app exists to collect. The task re-chains itself
after every run, re-arms on entering background only when nothing is pending,
and is cancelled when disabled. It is resubmitted **only when the heartbeat
settings themselves change**: BGTask requests survive relaunches and Dart
pushes a config on every launch, so resubmitting unconditionally would
restart the interval each time the app opens and a frequently used app would
never see a background run. Settings → "Send heartbeat now" runs the same
pipeline immediately (works on the simulator too, where BGTaskScheduler is
unavailable). To force a scheduled run on a device under Xcode/lldb:

```
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.clockster.geoProbe.heartbeat"]
```

### 2.7 Local notifications

Posted natively for enter/exit/SLC/relaunch so triggers are observable
without opening the app. Titles are localized natively (RU/EN by device
locale). `willPresent` shows banners in foreground too.

### 2.8 Storage & export

SQLite (`sqflite`), all local:

| table | contents |
|---|---|
| `regions` | id (uuid), name, lat, lng, radius, active |
| `events` | uuid PK, type, region_id, lat, lng, accuracy, event_ts, received_ts, app_state, battery, detail |
| `config` | key/value: app config JSON, Telegram settings |

Event types: `enter`, `exit`, `slc`, `state_initial`, `relaunch`,
`heartbeat`, `permission_change`, `error`.

Export: one JSON file (regions + config + all events) via the iOS share
sheet. `sharePositionOrigin` is anchored to the export button's own
`RenderBox` — mandatory on iPad and recent iOS, otherwise share_plus throws.

### 2.9 Journal & presence report

- Per-day event list with type filters, per-event delivery delay, app state.
- Dwell computation (spec §1b deliverable): ENTER/EXIT pairs per zone per
  day → "on site 3h 20m, 2 exits", open intervals closed at now/day end;
  an EXIT with no preceding ENTER assumes inside-since-day-start.
- Day boundary is the local calendar day of `event_ts` — after midnight,
  yesterday's walk is behind the ← arrow (a real support case already).

### 2.10 Telegram logger (optional debug channel)

Settings → bot token (@BotFather) + chat ID. Live `enter/exit/slc/relaunch/
permission_change/error` events are POSTed to the Bot API as they happen;
events accumulated while backgrounded are sent as **one** combined message on
the next open (rate limits). The JSONL drain re-delivers events already seen
live — only events new to the SQLite journal are forwarded, so nothing is
sent twice. Heartbeats and `state_initial` are not sent by the Dart
forwarder: heartbeats go to Telegram **natively from Swift** as part of the
background-heartbeat pipeline (§2.6), which is also why `heartbeat` must
never be added to `AppState._tgTypes` — the JSONL drain would double-send
them. Credentials are mirrored to native UserDefaults via `setTelegram`.
The local journal remains the source of truth — Telegram is a mirror that
only works while iOS lets the app run.

### 2.11 Localization

`gen-l10n`, ARB in `lib/l10n/` (en template + ru). Human wording everywhere
in UI (event names, permission statuses, app states, diagnostics values);
raw technical codes stay in the DB and JSON export. Native notification
titles localized in Swift. `CFBundleLocalizations` declares en+ru.

### 2.12 Known iOS platform behaviours encoded in the app

| Behaviour | Consequence |
|---|---|
| 20 monitored regions max | UI warns and refuses beyond 20 active |
| Region events need Always | WhenInUse works only in foreground; diagnostics highlights it |
| Geofences fire on network location, ~100–150 m minimum radius | slider floor 100 m, hint in dialog |
| After reboot, events resume only after first unlock | test-protocol item |
| BAR off → no background relaunches at all | shown red in diagnostics |
| BGAppRefreshTask timing is opportunistic (usage-pattern budgeted); BAR off stops it entirely | heartbeat interval is a floor, not a schedule; absence of heartbeats is itself signal |
| Always-upgrade prompt shown once per install | escalation is a deliberate button |
| The keyboard summoned together with a dialog hangs debug sessions under the VSCode debugger (flutter/flutter#123021) | no `autofocus` in dialogs |

---

## 3. Platform-channel contract

`MethodChannel('geo_probe/engine')`:

| method | args | returns | purpose |
|---|---|---|---|
| `requestPermissions` | — | current auth status string | notifications + WhenInUse→Always escalation |
| `requestInitialPermissions` | — | null | first-launch prompts, never escalates |
| `getDiagnostics` | — | map | heartbeat snapshot (§2.6) |
| `syncRegions` | list of region maps | null | replace native region set, re-register |
| `setConfig` | config map | null | persist + apply engine config |
| `drainNativeEvents` | — | list of event maps | read & clear the native JSONL buffer |
| `requestStateForRegions` | — | null | ask inside/outside for every region |
| `getCurrentLocation` | — | `{lat,lng,accuracy,ts}` or null | one-shot foreground fix |
| `setTelegram` | `{enabled,token,chatId}` | null | mirror TG credentials for the native heartbeat |
| `heartbeatNow` | — | null (after the TG attempt) | run the heartbeat pipeline immediately |

`EventChannel('geo_probe/events')`: pushes the same event maps live while the
engine runs. Consumers must deduplicate by `uuid` (events also land in JSONL).

Event map keys: `uuid`, `type`, `region_id?`, `lat?`, `lng?`, `accuracy?`,
`event_ts` (ms epoch, event's own time), `received_ts` (ms epoch),
`app_state`, `battery?`, `detail?`.

Config map keys: `regionMonitoringEnabled`, `slcEnabled`, `notifyOnEntry`,
`notifyOnExit`, `localNotifications`, `heartbeatEnabled`,
`heartbeatIntervalMin`. Dart defaults (models.dart) and native fallbacks
(AppDelegate.swift) must stay identical — native may run from a
terminated-state relaunch before Dart re-pushes the config.

---

## 4. What remains on Android

Current state: `MainActivity.kt` answers every channel method with safe
defaults (`getDiagnostics` → `{available: false}`, `drainNativeEvents` → `[]`);
`GeofenceBroadcastReceiver.kt` and `BootReceiver.kt` are compiling skeletons
with checklists. The Dart layer needs **no changes** — implementing the
contract below lights the whole app up.

### 4.1 Geofencing engine (core)

- [ ] `GeofencingClient` (play-services-location) — **not** a location
  foreground service: Google removes geofencing as an approved FGS use case
  on 26 Aug 2026 (spec §5.2). Add the dependency to `app/build.gradle`.
- [ ] Register geofences from `syncRegions`: one `Geofence` per active region,
  `GEOFENCE_TRANSITION_ENTER | EXIT`, `setExpirationDuration(NEVER_EXPIRE)`.
  Android's limit is 100 (vs 20 on iOS).
- [ ] **Mutable `PendingIntent`** (`FLAG_MUTABLE | FLAG_UPDATE_CURRENT`) to
  `GeofenceBroadcastReceiver`. With `FLAG_IMMUTABLE` on Android 12+ events
  are silently never delivered — the prime Gen-1 failure suspect.
- [ ] In the receiver: `GeofencingEvent.fromIntent()`, log the event's own
  timestamp from `triggeringLocation.time` as `event_ts`, `System.
  currentTimeMillis()` as `received_ts`. Map transition types to
  `enter`/`exit`.
- [ ] Persist regions + config in `SharedPreferences` (parity with
  UserDefaults on iOS) so the receiver and boot re-registration work without
  the Flutter engine.
- [ ] `state_initial` equivalent: Android has `GEOFENCE_TRANSITION_DWELL` /
  initial-trigger flags — use `INITIAL_TRIGGER_ENTER` on registration and log
  it as `state_initial`, or compute distance to region centers from one fix.

### 4.2 Native event store (parity with iOS JSONL)

- [ ] Append every event as a JSON line to
  `Context.getFilesDir()/geo_probe/native_events.jsonl` from the receiver
  (receivers run without Flutter). Same keys as §3.
- [ ] `drainNativeEvents`: read, parse, delete, return. Same idempotency
  contract (uuid per event, duplicate EXITs happen on Android too).
- [ ] Live path: keep an `EventChannel` sink in `MainActivity` and push
  events when the engine is up (receiver → e.g. local broadcast/shared flow,
  or simply rely on drain-on-resume for v1 of the stub).

### 4.3 Permissions & prompts

- [ ] `requestInitialPermissions`: `POST_NOTIFICATIONS` (API 33+) +
  `ACCESS_FINE_LOCATION`.
- [ ] `requestPermissions` (escalation): `ACCESS_BACKGROUND_LOCATION` —
  **must be requested separately and after** foreground location on
  Android 10+ (system sends the user to settings on 11+; "Allow all the
  time" is the required state for background geofencing).
- [ ] `permission_change` events: compare current grants on every
  `onResume`/receiver invocation against the last stored state (Android has
  no authorization-change callback).

### 4.4 Boot & lifecycle survival

- [ ] `BootReceiver` (`RECEIVE_BOOT_COMPLETED`): geofences are **not**
  restored after reboot — re-register from SharedPreferences and log a
  `relaunch`-class event (detail: `boot`). Without this, geofencing dies
  permanently at first reboot (documented Gen-1 candidate cause).
- [ ] Re-register on `MY_PACKAGE_REPLACED` (app update clears geofences too).
- [ ] Idempotent handlers throughout.

### 4.5 SLC analog

There is no SLC on Android. Closest equivalents, pick per test goals:
- [ ] `FusedLocationProviderClient.requestLocationUpdates` with
  `PRIORITY_BALANCED_POWER_ACCURACY` + large interval into a `PendingIntent`
  (works without a service, throttled heavily in background), or
- [ ] passive provider updates piggybacking on other apps' requests.
Log either as `slc` to keep the Dart layer unchanged. Note in results that
cadence semantics differ from iOS SLC.

### 4.6 One-shot fix & diagnostics

- [ ] `getCurrentLocation`: `FusedLocationProviderClient.getCurrentLocation
  (PRIORITY_HIGH_ACCURACY)`.
- [ ] `getDiagnostics` map (feed the same UI): fine/background location grant
  state, precise vs approximate (API 31+ `ACCESS_COARSE` only?), location
  services on/off (`LocationManagerCompat.isLocationEnabled`), notification
  permission, **battery-optimization state**
  (`PowerManager.isIgnoringBatteryOptimizations`) and OEM restriction hints,
  `Build.MANUFACTURER`/`MODEL` (per spec §6.1 the watchdog telemetry key),
  app hibernation status (`PackageManagerCompat.getUnusedAppRestrictionsStatus`),
  battery level, versions.
- [ ] Local notifications on events (`NotificationCompat`, channel required;
  remember: on Android 13+ with notifications denied, nothing is visible).

### 4.7 Manifest checklist

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>

<receiver android:name=".GeofenceBroadcastReceiver" android:exported="false"/>
<receiver android:name=".BootReceiver" android:exported="false">
  <intent-filter>
    <action android:name="android.intent.action.BOOT_COMPLETED"/>
  </intent-filter>
</receiver>
```

### 4.8 Explicitly out of scope for the test app (prod-only, spec §6.1)

Per-OEM battery-settings onboarding flows, self-healing watchdog service,
`promoteToForeground()` around network calls from headless context, Play
Store declaration forms. The test app should however **measure** what these
would fix: log every case of a geofence event arriving late/never keyed by
`Build.MANUFACTURER` — that telemetry decides which OEM flow to build first.

---

## 5. Distributing builds to testers

See [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md) — TestFlight internal
testing (recommended, no beta review) vs Ad Hoc IPA, step by step.

## 6. Running & testing

```bash
flutter run                     # device or simulator
flutter analyze
flutter test integration_test/longpress_test.dart -d <device>   # UI smoke
flutter test integration_test/pipeline_test.dart  -d <sim>      # native JSONL→SQLite
flutter test integration_test/geofence_test.dart  -d <sim>      # E2E enter/exit
```

The geofence E2E test expects an external driver teleporting the simulator
location in/out of the test zone (see the loop pattern below) and granting
`location-always` while the app is installed:

```bash
xcrun simctl privacy <UDID> grant location-always com.clockster.geoProbe
xcrun simctl location <UDID> set 51.2400,71.5200   # outside
xcrun simctl location <UDID> set 51.1694,71.4491   # inside → ENTER within ~20 s
```

### Field-test protocol (real device)

1. ENTER/EXIT with app foreground — baseline latency.
2. App backgrounded 30+ min stationary → cross the boundary.
3. Force-quit → cross the boundary (expect `relaunch` + event; Always only).
4. Reboot device (events resume only after first unlock).
5. Background App Refresh OFF → confirm silence + red diagnostics.
6. Airplane mode inside zone → exit → restore network.
7. SLC-only mode (region monitoring off) → observe granularity.
8. Stand 150 m outside a zone boundary — confirm "left the building" is
   not detectable, only "left the area" (spec §7.1).

Verify results in the Journal (per-event delivery delay) and the Diagnostics
counters; export JSON for offline analysis.
