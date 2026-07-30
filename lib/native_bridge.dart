import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

/// Bridge to the native geolocation engine.
///
/// iOS: fully implemented (CLLocationManager region monitoring + SLC).
/// Android: stubbed — every call degrades gracefully until the
/// GeofencingClient implementation lands.
class NativeBridge {
  static const MethodChannel _method = MethodChannel('geo_probe/engine');
  static const EventChannel _events = EventChannel('geo_probe/events');

  Stream<Map<String, dynamic>>? _eventStream;

  /// Live events pushed by the native side while the Flutter engine is alive.
  /// Events are ALSO always written to the native JSONL log, so the Dart side
  /// deduplicates by uuid on insert.
  Stream<Map<String, dynamic>> get eventStream {
    _eventStream ??= _events
        .receiveBroadcastStream()
        .map((e) => Map<String, dynamic>.from(e as Map))
        .handleError((Object err) {
      debugPrint('geo_probe event stream error: $err');
    });
    return _eventStream!;
  }

  Future<T?> _invoke<T>(String method, [dynamic args]) async {
    try {
      return await _method.invokeMethod<T>(method, args);
    } on MissingPluginException {
      debugPrint('geo_probe: $method not implemented on this platform');
      return null;
    } on PlatformException catch (e) {
      debugPrint('geo_probe: $method failed: ${e.code} ${e.message}');
      return null;
    }
  }

  /// Requests notification + location permission (WhenInUse, then Always).
  Future<String> requestPermissions() async {
    final res = await _invoke<String>('requestPermissions');
    return res ?? 'unavailable';
  }

  /// First-launch prompts: notifications + WhenInUse location, only when
  /// not yet determined. Never escalates to Always.
  Future<void> requestInitialPermissions() async {
    await _invoke<void>('requestInitialPermissions');
  }

  /// Snapshot of everything that can silently kill the feature:
  /// authorization status, precise/approx, location services,
  /// Background App Refresh, notification permission, versions.
  Future<Map<String, dynamic>> getDiagnostics() async {
    final res = await _invoke<Map<Object?, Object?>>('getDiagnostics');
    if (res == null) return {'available': false};
    return Map<String, dynamic>.from(res);
  }

  /// Replaces the native region set with [regions] (active only are armed).
  Future<void> syncRegions(List<Region> regions) async {
    await _invoke<void>(
        'syncRegions', regions.map((r) => r.toChannelMap()).toList());
  }

  Future<void> setConfig(AppConfig config) async {
    await _invoke<void>('setConfig', config.toMap());
  }

  /// Drains events the native side wrote to its JSONL file (including events
  /// captured while the app was terminated). The native file is cleared.
  Future<List<GeoEvent>> drainNativeEvents() async {
    final res = await _invoke<List<Object?>>('drainNativeEvents');
    if (res == null) return const [];
    final out = <GeoEvent>[];
    for (final item in res) {
      try {
        out.add(GeoEvent.fromMap(Map<String, dynamic>.from(item as Map)));
      } catch (e) {
        debugPrint('geo_probe: bad native event skipped: $e');
      }
    }
    return out;
  }

  /// Asks iOS for the initial inside/outside state of every monitored region.
  Future<void> requestStateForRegions() async {
    await _invoke<void>('requestStateForRegions');
  }

  /// One-shot foreground fix. Returns {lat, lng, accuracy, ts} or null.
  Future<Map<String, dynamic>?> getCurrentLocation() async {
    final res = await _invoke<Map<Object?, Object?>>('getCurrentLocation');
    if (res == null) return null;
    return Map<String, dynamic>.from(res);
  }
}
