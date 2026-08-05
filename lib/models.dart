import 'dart:convert';

/// A user-defined circular geofence region.
class Region {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final double radius;
  final bool active;

  const Region({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.radius,
    this.active = true,
  });

  Region copyWith({String? name, double? lat, double? lng, double? radius, bool? active}) {
    return Region(
      id: id,
      name: name ?? this.name,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      radius: radius ?? this.radius,
      active: active ?? this.active,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lng': lng,
        'radius': radius,
        'active': active ? 1 : 0,
      };

  /// Map sent over the platform channel (bool instead of int).
  Map<String, dynamic> toChannelMap() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lng': lng,
        'radius': radius,
        'active': active,
      };

  factory Region.fromMap(Map<String, dynamic> m) => Region(
        id: m['id'] as String,
        name: m['name'] as String,
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        radius: (m['radius'] as num).toDouble(),
        active: (m['active'] == 1 || m['active'] == true),
      );
}

/// Event types produced by the native layer or the Dart layer.
class EventType {
  static const enter = 'enter';
  static const exit = 'exit';
  static const slc = 'slc';
  static const stateInitial = 'state_initial';
  static const relaunch = 'relaunch';
  static const heartbeat = 'heartbeat';
  static const permissionChange = 'permission_change';
  static const error = 'error';

  static const all = [
    enter,
    exit,
    slc,
    stateInitial,
    relaunch,
    heartbeat,
    permissionChange,
    error,
  ];
}

/// One logged geolocation event. `eventTs` is the event's own timestamp,
/// `receivedTs` is when our code received it — the difference is the
/// delivery latency we are measuring.
class GeoEvent {
  final String uuid;
  final String type;
  final String? regionId;
  final double? lat;
  final double? lng;
  final double? accuracy;
  final int eventTs;
  final int receivedTs;
  final String appState;
  final int? battery;
  final String? detail;

  const GeoEvent({
    required this.uuid,
    required this.type,
    this.regionId,
    this.lat,
    this.lng,
    this.accuracy,
    required this.eventTs,
    required this.receivedTs,
    this.appState = 'foreground',
    this.battery,
    this.detail,
  });

  Duration get deliveryDelay => Duration(milliseconds: receivedTs - eventTs);

  DateTime get eventTime => DateTime.fromMillisecondsSinceEpoch(eventTs);
  DateTime get receivedTime => DateTime.fromMillisecondsSinceEpoch(receivedTs);

  Map<String, dynamic> toMap() => {
        'uuid': uuid,
        'type': type,
        'region_id': regionId,
        'lat': lat,
        'lng': lng,
        'accuracy': accuracy,
        'event_ts': eventTs,
        'received_ts': receivedTs,
        'app_state': appState,
        'battery': battery,
        'detail': detail,
      };

  factory GeoEvent.fromMap(Map<String, dynamic> m) => GeoEvent(
        uuid: m['uuid'] as String,
        type: m['type'] as String,
        regionId: m['region_id'] as String?,
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        accuracy: (m['accuracy'] as num?)?.toDouble(),
        eventTs: (m['event_ts'] as num).toInt(),
        receivedTs: (m['received_ts'] as num).toInt(),
        appState: (m['app_state'] as String?) ?? 'unknown',
        battery: (m['battery'] as num?)?.toInt(),
        detail: m['detail'] as String?,
      );
}

/// Engine configuration pushed to the native side and persisted there,
/// so a terminated-state relaunch knows what to do.
///
/// Heartbeat defaults must match the Swift side (`heartbeatEnabled` /
/// `heartbeatInterval` in AppDelegate.swift): native may run before Dart
/// re-pushes the config after an app update.
class AppConfig {
  final bool regionMonitoringEnabled;
  final bool slcEnabled;
  final bool notifyOnEntry;
  final bool notifyOnExit;
  final bool localNotifications;
  final bool heartbeatEnabled;
  final int heartbeatIntervalMin;

  const AppConfig({
    this.regionMonitoringEnabled = true,
    this.slcEnabled = false,
    this.notifyOnEntry = true,
    this.notifyOnExit = true,
    this.localNotifications = true,
    this.heartbeatEnabled = true,
    this.heartbeatIntervalMin = 60,
  });

  AppConfig copyWith({
    bool? regionMonitoringEnabled,
    bool? slcEnabled,
    bool? notifyOnEntry,
    bool? notifyOnExit,
    bool? localNotifications,
    bool? heartbeatEnabled,
    int? heartbeatIntervalMin,
  }) {
    return AppConfig(
      regionMonitoringEnabled: regionMonitoringEnabled ?? this.regionMonitoringEnabled,
      slcEnabled: slcEnabled ?? this.slcEnabled,
      notifyOnEntry: notifyOnEntry ?? this.notifyOnEntry,
      notifyOnExit: notifyOnExit ?? this.notifyOnExit,
      localNotifications: localNotifications ?? this.localNotifications,
      heartbeatEnabled: heartbeatEnabled ?? this.heartbeatEnabled,
      heartbeatIntervalMin: heartbeatIntervalMin ?? this.heartbeatIntervalMin,
    );
  }

  Map<String, dynamic> toMap() => {
        'regionMonitoringEnabled': regionMonitoringEnabled,
        'slcEnabled': slcEnabled,
        'notifyOnEntry': notifyOnEntry,
        'notifyOnExit': notifyOnExit,
        'localNotifications': localNotifications,
        'heartbeatEnabled': heartbeatEnabled,
        'heartbeatIntervalMin': heartbeatIntervalMin,
      };

  String toJson() => jsonEncode(toMap());

  factory AppConfig.fromMap(Map<String, dynamic> m) => AppConfig(
        regionMonitoringEnabled: m['regionMonitoringEnabled'] as bool? ?? true,
        slcEnabled: m['slcEnabled'] as bool? ?? false,
        notifyOnEntry: m['notifyOnEntry'] as bool? ?? true,
        notifyOnExit: m['notifyOnExit'] as bool? ?? true,
        localNotifications: m['localNotifications'] as bool? ?? true,
        heartbeatEnabled: m['heartbeatEnabled'] as bool? ?? true,
        heartbeatIntervalMin:
            (m['heartbeatIntervalMin'] as num?)?.toInt() ?? 60,
      );

  factory AppConfig.fromJson(String s) =>
      AppConfig.fromMap(jsonDecode(s) as Map<String, dynamic>);
}
