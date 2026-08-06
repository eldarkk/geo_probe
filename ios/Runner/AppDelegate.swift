import Flutter
import UIKit
import CoreLocation
import UserNotifications
import BackgroundTasks

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // MUST happen before the end of didFinishLaunching: when iOS relaunches
    // the terminated app for a location event, the CLLocationManager delegate
    // has to exist already or the event is lost.
    let launchedByLocation = launchOptions?[.location] != nil
    LocationService.shared.bootstrap(launchedByLocation: launchedByLocation)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    LocationService.shared.attachChannels(
      messenger: engineBridge.applicationRegistrar.messenger())
  }
}

// MARK: - LocationService

/// Native geolocation engine. Owns CLLocationManager, region monitoring and
/// SignificantLocationChange. Every event is appended to a JSONL file so that
/// events captured in the terminated state survive even if the Flutter engine
/// never spins up; the Dart side drains the file on launch/resume and
/// deduplicates by uuid.
final class LocationService: NSObject {
  static let shared = LocationService()

  private let manager = CLLocationManager()
  private let ioQueue = DispatchQueue(label: "geo_probe.events.io")
  private let defaults = UserDefaults.standard

  private var eventSink: FlutterEventSink?
  // Every getCurrentLocation caller waiting for a fix. An array, not a single
  // slot: overlapping calls (initState + FAB) must all get their answer, or
  // the overwritten Dart Future would hang forever. Entries carry an id so an
  // internal caller that gave up can withdraw instead of clogging the queue.
  private var pendingLocationResults: [(id: UUID, result: FlutterResult)] = []
  private var launchedByLocation = false
  // Tracked manually so callbacks never need UIApplication on a background thread.
  private var appState = "launching"

  private static let configKey = "geo_probe.config"
  private static let regionsKey = "geo_probe.regions"
  // Telegram credentials mirrored from Dart so the background heartbeat can
  // post without the Flutter engine.
  private static let telegramKey = "geo_probe.telegram"
  private static let lastHeartbeatTsKey = "geo_probe.lastHeartbeatTs"
  // Must match BGTaskSchedulerPermittedIdentifiers in Info.plist.
  private static let heartbeatTaskId = "com.clockster.geoProbe.heartbeat"

  // MARK: Config

  private var config: [String: Any] {
    get { defaults.dictionary(forKey: Self.configKey) ?? [:] }
    set { defaults.set(newValue, forKey: Self.configKey) }
  }

  private var storedRegions: [[String: Any]] {
    get { defaults.array(forKey: Self.regionsKey) as? [[String: Any]] ?? [] }
    set { defaults.set(newValue, forKey: Self.regionsKey) }
  }

  private func configBool(_ key: String, default def: Bool) -> Bool {
    config[key] as? Bool ?? def
  }

  // Defaults must match AppConfig in lib/models.dart (enabled, 60 min): a
  // terminated-state relaunch may run before Dart re-pushes the config.
  private var heartbeatEnabled: Bool { configBool("heartbeatEnabled", default: true) }

  private var heartbeatInterval: TimeInterval {
    let minutes = (config["heartbeatIntervalMin"] as? NSNumber)?.doubleValue ?? 60
    return max(15, minutes) * 60
  }

  // MARK: Bootstrap

  func bootstrap(launchedByLocation: Bool) {
    self.launchedByLocation = launchedByLocation
    appState = launchedByLocation ? "terminated-relaunch" : "launching"

    UIDevice.current.isBatteryMonitoringEnabled = true
    manager.delegate = self
    manager.allowsBackgroundLocationUpdates = false // no UIBackgroundModes: location by design

    UNUserNotificationCenter.current().delegate = self

    // BGTaskScheduler requires every launch handler to be registered before
    // the app finishes launching — bootstrap() runs first thing in
    // didFinishLaunching, so this is the only safe place.
    let registered = BGTaskScheduler.shared.register(
      forTaskWithIdentifier: Self.heartbeatTaskId, using: .main) { [weak self] task in
      guard let self = self, let refresh = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false)
        return
      }
      self.handleHeartbeatTask(refresh)
    }
    if !registered {
      NSLog("geo_probe: BGTask registration failed — identifier missing from Info.plist?")
    }

    let center = NotificationCenter.default
    center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                       object: nil, queue: .main) { [weak self] _ in
      self?.appState = "foreground"
    }
    center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                       object: nil, queue: .main) { [weak self] _ in
      self?.appState = "background"
      self?.scheduleHeartbeat(replacePending: false)
    }

    applyConfig()

    if launchedByLocation {
      writeEvent(type: "relaunch", detail: "relaunched by iOS for a location event")
    }
  }

  /// [rescheduleHeartbeat] must be true ONLY when the heartbeat settings
  /// actually changed. BGTask requests survive relaunches, and every launch
  /// pushes a config down: resubmitting unconditionally would restart the
  /// interval each time the app opens, so a frequently used app would never
  /// see a background heartbeat at all.
  private func applyConfig(rescheduleHeartbeat: Bool = false) {
    if configBool("slcEnabled", default: false) {
      manager.startMonitoringSignificantLocationChanges()
    } else {
      manager.stopMonitoringSignificantLocationChanges()
    }
    if configBool("regionMonitoringEnabled", default: true) {
      registerRegions()
    } else {
      stopAllRegionMonitoring()
    }
    if heartbeatEnabled {
      scheduleHeartbeat(replacePending: rescheduleHeartbeat)
    } else {
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.heartbeatTaskId)
    }
  }

  // MARK: Regions

  private func stopAllRegionMonitoring() {
    for region in manager.monitoredRegions {
      manager.stopMonitoring(for: region)
    }
  }

  private func registerRegions() {
    stopAllRegionMonitoring()
    let notifyOnEntry = configBool("notifyOnEntry", default: true)
    let notifyOnExit = configBool("notifyOnExit", default: true)
    let active = storedRegions.filter { ($0["active"] as? Bool) ?? true }
    // iOS hard limit: 20 monitored regions per app.
    for dict in active.prefix(20) {
      guard let id = dict["id"] as? String,
            let lat = dict["lat"] as? Double,
            let lng = dict["lng"] as? Double,
            let radius = dict["radius"] as? Double else { continue }
      let clamped = min(radius, manager.maximumRegionMonitoringDistance)
      let region = CLCircularRegion(
        center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
        radius: clamped,
        identifier: id)
      region.notifyOnEntry = notifyOnEntry
      region.notifyOnExit = notifyOnExit
      manager.startMonitoring(for: region)
    }
  }

  // MARK: Channels

  func attachChannels(messenger: FlutterBinaryMessenger) {
    let method = FlutterMethodChannel(name: "geo_probe/engine", binaryMessenger: messenger)
    method.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    let events = FlutterEventChannel(name: "geo_probe/events", binaryMessenger: messenger)
    events.setStreamHandler(self)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestPermissions":
      requestPermissions(result: result)
    case "requestInitialPermissions":
      // First-launch prompts: notifications (system no-ops if already
      // determined) + WhenInUse location ONLY if never asked. The upgrade
      // to Always stays behind the explicit settings button.
      UNUserNotificationCenter.current()
        .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
      if manager.authorizationStatus == .notDetermined {
        manager.requestWhenInUseAuthorization()
      }
      result(nil)
    case "getDiagnostics":
      buildDiagnostics(result: result)
    case "syncRegions":
      if let regions = call.arguments as? [[String: Any]] {
        storedRegions = regions
        if configBool("regionMonitoringEnabled", default: true) {
          registerRegions()
        }
      }
      result(nil)
    case "setConfig":
      if let cfg = call.arguments as? [String: Any] {
        let before = [heartbeatEnabled ? 1 : 0, Int(heartbeatInterval)]
        config = cfg
        let after = [heartbeatEnabled ? 1 : 0, Int(heartbeatInterval)]
        applyConfig(rescheduleHeartbeat: before != after)
      }
      result(nil)
    case "drainNativeEvents":
      drainEvents(result: result)
    case "requestStateForRegions":
      for region in manager.monitoredRegions {
        manager.requestState(for: region)
      }
      result(nil)
    case "getCurrentLocation":
      getCurrentLocation(result: result)
    case "setTelegram":
      if let args = call.arguments as? [String: Any] {
        defaults.set(args, forKey: Self.telegramKey)
      }
      result(nil)
    case "heartbeatNow":
      // Full pipeline (JSONL event → notification → Telegram); the Future
      // resolves after the Telegram attempt so the UI can confirm delivery.
      performHeartbeat(trigger: "manual") { result(nil) }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Permissions

  private func requestPermissions(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current()
      .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .authorizedWhenInUse:
      // Two-step escalation: WhenInUse first, then the Always upgrade prompt.
      manager.requestAlwaysAuthorization()
    default:
      break
    }
    result(Self.describe(manager.authorizationStatus))
  }

  // MARK: Diagnostics

  private func buildDiagnostics(result: @escaping FlutterResult) {
    let auth = Self.describe(manager.authorizationStatus)
    let accuracy = manager.accuracyAuthorization == .fullAccuracy
      ? "fullAccuracy" : "reducedAccuracy"
    let monitoredCount = manager.monitoredRegions.count
    let refreshStatus: String
    switch UIApplication.shared.backgroundRefreshStatus {
    case .available: refreshStatus = "available"
    case .denied: refreshStatus = "denied"
    case .restricted: refreshStatus = "restricted"
    @unknown default: refreshStatus = "unknown"
    }
    let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
      + " (" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?") + ")"
    let launched = launchedByLocation
    let slc = configBool("slcEnabled", default: false)
    let regionMonitoring = configBool("regionMonitoringEnabled", default: true)
    let battery = Self.batteryPercent() ?? -1
    let heartbeatOn = heartbeatEnabled
    let heartbeatMin = (config["heartbeatIntervalMin"] as? NSNumber)?.intValue ?? 60
    let lastHeartbeat =
      (defaults.object(forKey: Self.lastHeartbeatTsKey) as? NSNumber)?.int64Value ?? 0

    // locationServicesEnabled() may block — never call it on the main thread.
    DispatchQueue.global(qos: .userInitiated).async {
      let servicesEnabled = CLLocationManager.locationServicesEnabled()
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        let notifAuthorized = settings.authorizationStatus == .authorized
          || settings.authorizationStatus == .provisional
        let diag: [String: Any] = [
          "authorizationStatus": auth,
          "accuracyAuthorization": accuracy,
          "locationServicesEnabled": servicesEnabled,
          "backgroundRefreshStatus": refreshStatus,
          "notificationsAuthorized": notifAuthorized,
          "monitoredRegionsCount": monitoredCount,
          "slcEnabled": slc,
          "regionMonitoringEnabled": regionMonitoring,
          "launchedByLocationThisRun": launched,
          "appVersion": appVersion,
          "osVersion": UIDevice.current.systemVersion,
          "batteryPercent": battery,
          "heartbeatEnabled": heartbeatOn,
          "heartbeatIntervalMin": heartbeatMin,
          "lastNativeHeartbeatTs": lastHeartbeat,
        ]
        DispatchQueue.main.async { result(diag) }
      }
    }
  }

  // MARK: One-shot fix

  private func getCurrentLocation(result: @escaping FlutterResult) {
    if let last = manager.location, -last.timestamp.timeIntervalSinceNow < 15 {
      result(Self.fixMap(last))
      return
    }
    enqueueFixWaiter(result)
  }

  /// Registers a waiter for the next fix and returns its id. Only the first
  /// waiter triggers requestLocation(): calling it again would cancel the
  /// in-flight request.
  @discardableResult
  private func enqueueFixWaiter(_ handler: @escaping FlutterResult) -> UUID {
    let id = UUID()
    pendingLocationResults.append((id: id, result: handler))
    if pendingLocationResults.count == 1 {
      manager.requestLocation()
    }
    return id
  }

  /// Drops a waiter that gave up. Mandatory for the background heartbeat:
  /// CoreLocation may answer neither success nor failure before iOS suspends
  /// the process, and a stranded entry would keep count > 1 forever — which
  /// suppresses requestLocation() for every later caller and hangs their Dart
  /// Futures (invariant 8).
  private func withdrawFixWaiter(_ id: UUID) {
    pendingLocationResults.removeAll { $0.id == id }
  }

  private static func fixMap(_ location: CLLocation) -> [String: Any] {
    [
      "lat": location.coordinate.latitude,
      "lng": location.coordinate.longitude,
      "accuracy": location.horizontalAccuracy,
      "ts": Int64(location.timestamp.timeIntervalSince1970 * 1000),
    ]
  }

  /// Rebuilds a CLLocation from the fixMap dictionary handed to fix waiters.
  private static func location(fromFixMap any: Any?) -> CLLocation? {
    guard let dict = any as? [String: Any],
          let lat = dict["lat"] as? Double,
          let lng = dict["lng"] as? Double else { return nil }
    let ts = (dict["ts"] as? NSNumber)
      .map { Date(timeIntervalSince1970: $0.doubleValue / 1000) } ?? Date()
    return CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
      altitude: 0,
      horizontalAccuracy: dict["accuracy"] as? Double ?? -1,
      verticalAccuracy: -1,
      timestamp: ts)
  }

  // MARK: Heartbeat (BGAppRefreshTask)

  /// Submits the next heartbeat request. iOS treats earliestBeginDate as a
  /// lower bound only — real delivery depends on usage patterns and
  /// Background App Refresh; measuring that gap is itself diagnostic data.
  private func scheduleHeartbeat(replacePending: Bool) {
    guard heartbeatEnabled else { return }
    let submit = {
      let request = BGAppRefreshTaskRequest(identifier: Self.heartbeatTaskId)
      request.earliestBeginDate = Date(timeIntervalSinceNow: self.heartbeatInterval)
      do {
        try BGTaskScheduler.shared.submit(request)
      } catch {
        // Expected on the simulator, where BGTaskScheduler is unavailable.
        NSLog("geo_probe: BGTask submit failed: \(error)")
      }
    }
    if replacePending {
      submit()
    } else {
      // Entering background must not push a pending request further into the
      // future for an active user — keep the earliest date already submitted.
      BGTaskScheduler.shared.getPendingTaskRequests { pending in
        if pending.contains(where: { $0.identifier == Self.heartbeatTaskId }) { return }
        submit()
      }
    }
  }

  private func handleHeartbeatTask(_ task: BGAppRefreshTask) {
    guard heartbeatEnabled else {
      // A request submitted before the feature was switched off may still fire.
      task.setTaskCompleted(success: true)
      return
    }
    scheduleHeartbeat(replacePending: true) // chain the next run first
    var completed = false
    let finish: (Bool) -> Void = { success in // main thread only
      if completed { return }
      completed = true
      task.setTaskCompleted(success: success)
    }
    // On expiry the JSONL event is already written — at worst the Telegram
    // delivery is cut short.
    task.expirationHandler = { DispatchQueue.main.async { finish(false) } }
    performHeartbeat(trigger: "bgtask") { finish(true) }
  }

  /// Status snapshot → JSONL heartbeat event (FIRST — invariant 1) → local
  /// notification → Telegram. [completion] fires on the main thread after the
  /// Telegram attempt, so a BGTask can hold the process alive until then.
  private func performHeartbeat(trigger: String, completion: @escaping () -> Void) {
    let auth = Self.describe(manager.authorizationStatus)
    let precise = manager.accuracyAuthorization == .fullAccuracy
    let bar: String
    switch UIApplication.shared.backgroundRefreshStatus {
    case .available: bar = "available"
    case .denied: bar = "denied"
    case .restricted: bar = "restricted"
    @unknown default: bar = "unknown"
    }
    let monitored = manager.monitoredRegions.count
    let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    requestOneShotFix(timeout: 10) { fix in
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        let notifOk = settings.authorizationStatus == .authorized
          || settings.authorizationStatus == .provisional
        DispatchQueue.main.async {
          var detail: [String: Any] = [
            "trigger": trigger,
            "authorizationStatus": auth,
            "accuracyAuthorization": precise ? "fullAccuracy" : "reducedAccuracy",
            "backgroundRefreshStatus": bar,
            "notificationsAuthorized": notifOk,
            "monitoredRegionsCount": monitored,
            "lowPowerMode": lowPower,
          ]
          if let fix = fix {
            detail["fixAgeSec"] = Int((-fix.timestamp.timeIntervalSinceNow).rounded())
          }
          let json = (try? JSONSerialization.data(withJSONObject: detail))
            .flatMap { String(data: $0, encoding: .utf8) }
          self.writeEvent(type: "heartbeat", location: fix,
                          timestampFromFix: false, detail: json)
          if trigger == "bgtask" {
            // Only real background runs may stamp this: it is the metric that
            // answers "does iOS actually fire the task?", so a manual test
            // press must not forge it.
            self.defaults.set(Int64(Date().timeIntervalSince1970 * 1000),
                              forKey: Self.lastHeartbeatTsKey)
          }

          let summary = self.heartbeatSummary(
            auth: auth, precise: precise, bar: bar, notifOk: notifOk,
            fix: fix, monitored: monitored, lowPower: lowPower)
          if self.configBool("localNotifications", default: true) {
            self.postHeartbeatNotification(body: summary)
          }
          let ru = Self.isRussian
          let triggerLabel = trigger == "manual"
            ? (ru ? "вручную" : "manual")
            : (ru ? "фоновая задача" : "background task")
          let fmt = DateFormatter()
          fmt.dateFormat = "dd.MM HH:mm:ss"
          let tgText = "💓 Heartbeat (\(triggerLabel))\n\(summary)\n"
            + "🕐 \(fmt.string(from: Date())) · \(self.appState)"
          // Barrier through ioQueue: even with Telegram off, completion (and
          // the BGTask suspend that follows) must wait for the JSONL append.
          self.ioQueue.async {
            DispatchQueue.main.async {
              self.sendTelegram(text: tgText, completion: completion)
            }
          }
        }
      }
    }
  }

  /// One-shot fix for the heartbeat. Shares the fix-waiter queue with
  /// getCurrentLocation (overlapping callers must each get an answer —
  /// invariant 8) and falls back to the last cached fix on timeout: in the
  /// background with WhenInUse-only authorization requestLocation() may
  /// deliver nothing at all. On timeout the waiter is withdrawn so it cannot
  /// block later callers.
  private func requestOneShotFix(timeout: TimeInterval,
                                 completion: @escaping (CLLocation?) -> Void) {
    if let last = manager.location, -last.timestamp.timeIntervalSinceNow < 15 {
      completion(last)
      return
    }
    var done = false // main thread only
    let id = enqueueFixWaiter { [weak self] any in
      if done { return }
      done = true
      completion(Self.location(fromFixMap: any) ?? self?.manager.location)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
      if done { return }
      done = true
      self?.withdrawFixWaiter(id)
      completion(self?.manager.location)
    }
  }

  private static var isRussian: Bool {
    Locale.preferredLanguages.first?.hasPrefix("ru") ?? false
  }

  /// Human-readable status for the notification body and Telegram, RU/EN by
  /// device language. Wording mirrors the ARB translations.
  private func heartbeatSummary(auth: String, precise: Bool, bar: String,
                                notifOk: Bool, fix: CLLocation?,
                                monitored: Int, lowPower: Bool) -> String {
    let ru = Self.isRussian
    let authNames: [String: (en: String, ru: String)] = [
      "always": ("Always", "Всегда"),
      "whenInUse": ("When in use", "При использовании"),
      "denied": ("Denied", "Запрещено"),
      "notDetermined": ("Not requested", "Не запрошено"),
      "restricted": ("Restricted", "Ограничено"),
    ]
    let authName = authNames[auth].map { ru ? $0.ru : $0.en } ?? auth
    var lines: [String] = []
    var authLine = "🔐 " + (ru ? "Геолокация: " : "Location: ") + authName
    if !precise { authLine += ru ? " · приблизительная" : " · approximate" }
    lines.append(authLine)
    let barName: String
    switch bar {
    case "available": barName = ru ? "включено" : "on"
    case "denied": barName = ru ? "выключено" : "off"
    case "restricted": barName = ru ? "ограничено" : "restricted"
    default: barName = bar
    }
    lines.append("🔄 " + (ru ? "Фоновое обновление: " : "Background refresh: ") + barName)
    if let fix = fix {
      var line = String(format: "📍 %.5f, %.5f",
                        fix.coordinate.latitude, fix.coordinate.longitude)
      if fix.horizontalAccuracy >= 0 {
        line += String(format: " ±%.0f m", fix.horizontalAccuracy)
      }
      let ageMin = Int((-fix.timestamp.timeIntervalSinceNow / 60).rounded())
      if ageMin >= 1 {
        line += ru ? " (фикс \(ageMin) мин назад)" : " (fix \(ageMin) min old)"
      }
      lines.append(line)
    } else {
      lines.append(ru ? "📍 нет координат" : "📍 no fix")
    }
    var statusBits: [String] = []
    if let battery = Self.batteryPercent() { statusBits.append("🔋 \(battery)%") }
    statusBits.append((ru ? "зон: " : "zones: ") + "\(monitored)")
    if lowPower { statusBits.append(ru ? "энергосбережение" : "low power") }
    if !notifOk { statusBits.append(ru ? "уведомления запрещены" : "notifications off") }
    lines.append(statusBits.joined(separator: " · "))
    return lines.joined(separator: "\n")
  }

  private func postHeartbeatNotification(body: String) {
    let content = UNMutableNotificationContent()
    content.title = "💓 Heartbeat"
    let fmt = DateFormatter()
    fmt.dateFormat = "HH:mm:ss"
    content.body = body + "\n🕐 \(fmt.string(from: Date())) · \(appState)"
    content.sound = .default
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: UUID().uuidString,
                            content: content, trigger: nil))
  }

  /// Posts [text] to the Telegram Bot API with the credentials mirrored into
  /// UserDefaults by the Dart side (`setTelegram`). Always calls [completion]
  /// on the main thread — a BGTask must know when it may suspend.
  private func sendTelegram(text: String, completion: @escaping () -> Void) {
    let tg = defaults.dictionary(forKey: Self.telegramKey) ?? [:]
    guard tg["enabled"] as? Bool == true,
          let token = tg["token"] as? String, !token.isEmpty,
          let chatId = tg["chatId"] as? String, !chatId.isEmpty,
          let url = URL(string: "https://api.telegram.org/bot\(token)/sendMessage")
    else {
      completion()
      return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(
      withJSONObject: ["chat_id": chatId, "text": text])
    URLSession.shared.dataTask(with: request) { _, response, error in
      if let error = error {
        NSLog("geo_probe: heartbeat telegram failed: \(error.localizedDescription)")
      } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
        NSLog("geo_probe: heartbeat telegram HTTP \(http.statusCode)")
      }
      DispatchQueue.main.async { completion() }
    }.resume()
  }

  // MARK: Event log (JSONL, written natively so terminated-state events survive)

  private var eventsFileURL: URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                       in: .userDomainMask)[0]
      .appendingPathComponent("geo_probe", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("native_events.jsonl")
  }

  /// event_ts is the event's OWN timestamp (from the CLLocation fix when
  /// available); received_ts is "now". The difference is the delivery latency
  /// this whole test app exists to measure. Never log receipt time as event
  /// time — that is the §4.2 defect that turned "slow" into "lying".
  /// Heartbeats pass timestampFromFix=false: their own time IS "now", and a
  /// cached fix must not backdate them (its age goes into detail instead).
  private func writeEvent(type: String,
                          regionId: String? = nil,
                          location: CLLocation? = nil,
                          timestampFromFix: Bool = true,
                          detail: String? = nil) {
    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
    var eventTs = nowMs
    if timestampFromFix, let loc = location {
      eventTs = Int64(loc.timestamp.timeIntervalSince1970 * 1000)
    }
    var dict: [String: Any] = [
      "uuid": UUID().uuidString,
      "type": type,
      "event_ts": eventTs,
      "received_ts": nowMs,
      "app_state": appState,
    ]
    if let regionId = regionId { dict["region_id"] = regionId }
    if let loc = location {
      dict["lat"] = loc.coordinate.latitude
      dict["lng"] = loc.coordinate.longitude
      dict["accuracy"] = loc.horizontalAccuracy
    }
    if let battery = Self.batteryPercent() { dict["battery"] = battery }
    if let detail = detail { dict["detail"] = detail }

    appendToFile(dict)

    if let sink = eventSink {
      DispatchQueue.main.async { sink(dict) }
    }

    if configBool("localNotifications", default: true),
       ["enter", "exit", "slc", "relaunch"].contains(type) {
      postNotification(type: type, regionId: regionId, detail: detail)
    }
  }

  private func appendToFile(_ dict: [String: Any]) {
    let url = eventsFileURL
    ioQueue.async {
      guard var data = try? JSONSerialization.data(withJSONObject: dict) else { return }
      data.append(0x0A) // newline
      if let handle = try? FileHandle(forWritingTo: url) {
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
      } else {
        try? data.write(to: url)
      }
    }
  }

  private func drainEvents(result: @escaping FlutterResult) {
    let url = eventsFileURL
    ioQueue.async {
      var events: [[String: Any]] = []
      if let data = try? Data(contentsOf: url), !data.isEmpty {
        let lines = data.split(separator: 0x0A)
        for line in lines {
          if let obj = try? JSONSerialization.jsonObject(with: line),
             let dict = obj as? [String: Any] {
            events.append(dict)
          }
        }
        try? FileManager.default.removeItem(at: url)
      }
      DispatchQueue.main.async { result(events) }
    }
  }

  // MARK: Notifications

  private func postNotification(type: String, regionId: String?, detail: String?) {
    let regionName = storedRegions
      .first { ($0["id"] as? String) == regionId }?["name"] as? String
    let content = UNMutableNotificationContent()
    // Simple human titles, localized for a Russian device locale. The app
    // name is already shown by iOS, so no prefix needed.
    let isRussian = Locale.preferredLanguages.first?.hasPrefix("ru") ?? false
    let titles: [String: (en: String, ru: String)] = [
      "enter": ("Entered zone", "Вход в зону"),
      "exit": ("Left zone", "Выход из зоны"),
      "slc": ("Movement", "Перемещение"),
      "relaunch": ("Relaunched by location event", "Перезапуск по геособытию"),
    ]
    let pair = titles[type] ?? (en: type, ru: type)
    content.title = isRussian ? pair.ru : pair.en
    var body = regionName ?? detail ?? ""
    let fmt = DateFormatter()
    fmt.dateFormat = "HH:mm:ss"
    body += " · \(fmt.string(from: Date())) · \(appState)"
    content.body = body
    content.sound = .default
    let request = UNNotificationRequest(
      identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
  }

  // MARK: Helpers

  private static func batteryPercent() -> Int? {
    let level = UIDevice.current.batteryLevel
    guard level >= 0 else { return nil }
    return Int((level * 100).rounded())
  }

  private static func describe(_ status: CLAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "notDetermined"
    case .restricted: return "restricted"
    case .denied: return "denied"
    case .authorizedAlways: return "always"
    case .authorizedWhenInUse: return "whenInUse"
    @unknown default: return "unknown"
    }
  }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
  func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    writeEvent(type: "enter", regionId: region.identifier, location: manager.location)
  }

  func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    writeEvent(type: "exit", regionId: region.identifier, location: manager.location)
  }

  func locationManager(_ manager: CLLocationManager,
                       didDetermineState state: CLRegionState,
                       for region: CLRegion) {
    let stateName: String
    switch state {
    case .inside: stateName = "inside"
    case .outside: stateName = "outside"
    case .unknown: stateName = "unknown"
    }
    writeEvent(type: "state_initial", regionId: region.identifier,
               location: manager.location, detail: stateName)
  }

  func locationManager(_ manager: CLLocationManager,
                       didUpdateLocations locations: [CLLocation]) {
    guard let latest = locations.last else { return }
    if !pendingLocationResults.isEmpty {
      let pending = pendingLocationResults
      pendingLocationResults = []
      let fix = Self.fixMap(latest)
      DispatchQueue.main.async { pending.forEach { $0.result(fix) } }
      return
    }
    // No continuous foreground updates in this app: an unsolicited delivery
    // comes from SLC — but only if SLC monitoring is actually on. A late
    // one-shot fix arriving after didFailWithError already cleared the
    // waiters must not be logged as movement.
    if configBool("slcEnabled", default: false) {
      writeEvent(type: "slc", location: latest)
    } else {
      writeEvent(type: "error", location: latest,
                 detail: "unsolicited didUpdateLocations while SLC is off")
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let status = manager.authorizationStatus
    writeEvent(type: "permission_change", detail: Self.describe(status))
    // Region registration fails (kCLError 4) while authorization is
    // insufficient — re-arm everything once the user grants access.
    if status == .authorizedAlways || status == .authorizedWhenInUse {
      applyConfig()
    }
  }

  func locationManager(_ manager: CLLocationManager,
                       monitoringDidFailFor region: CLRegion?,
                       withError error: Error) {
    writeEvent(type: "error", regionId: region?.identifier,
               detail: "monitoringDidFail: \(error.localizedDescription)")
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    if !pendingLocationResults.isEmpty {
      let pending = pendingLocationResults
      pendingLocationResults = []
      DispatchQueue.main.async { pending.forEach { $0.result(nil) } }
    }
    writeEvent(type: "error", detail: "didFail: \(error.localizedDescription)")
  }
}

// MARK: - FlutterStreamHandler

extension LocationService: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?,
                eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}

// MARK: - UNUserNotificationCenterDelegate

extension LocationService: UNUserNotificationCenterDelegate {
  // Show event banners even while the app is in the foreground.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }
}
