import Flutter
import UIKit
import CoreLocation
import UserNotifications

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
  private var pendingLocationResult: FlutterResult?
  private var launchedByLocation = false
  // Tracked manually so callbacks never need UIApplication on a background thread.
  private var appState = "launching"

  private static let configKey = "geo_probe.config"
  private static let regionsKey = "geo_probe.regions"

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

  // MARK: Bootstrap

  func bootstrap(launchedByLocation: Bool) {
    self.launchedByLocation = launchedByLocation
    appState = launchedByLocation ? "terminated-relaunch" : "launching"

    UIDevice.current.isBatteryMonitoringEnabled = true
    manager.delegate = self
    manager.allowsBackgroundLocationUpdates = false // no UIBackgroundModes: location by design

    UNUserNotificationCenter.current().delegate = self

    let center = NotificationCenter.default
    center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                       object: nil, queue: .main) { [weak self] _ in
      self?.appState = "foreground"
    }
    center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                       object: nil, queue: .main) { [weak self] _ in
      self?.appState = "background"
    }

    applyConfig()

    if launchedByLocation {
      writeEvent(type: "relaunch", detail: "relaunched by iOS for a location event")
    }
  }

  private func applyConfig() {
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
        config = cfg
        applyConfig()
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
    pendingLocationResult = result
    manager.requestLocation()
  }

  private static func fixMap(_ location: CLLocation) -> [String: Any] {
    [
      "lat": location.coordinate.latitude,
      "lng": location.coordinate.longitude,
      "accuracy": location.horizontalAccuracy,
      "ts": Int64(location.timestamp.timeIntervalSince1970 * 1000),
    ]
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
  private func writeEvent(type: String,
                          regionId: String? = nil,
                          location: CLLocation? = nil,
                          detail: String? = nil) {
    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
    var eventTs = nowMs
    if let loc = location {
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
    if let pending = pendingLocationResult {
      pendingLocationResult = nil
      DispatchQueue.main.async { pending(Self.fixMap(latest)) }
      return
    }
    // No continuous foreground updates in this app: any unsolicited
    // didUpdateLocations delivery comes from SLC.
    writeEvent(type: "slc", location: latest)
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
    if let pending = pendingLocationResult {
      pendingLocationResult = nil
      DispatchQueue.main.async { pending(nil) }
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
