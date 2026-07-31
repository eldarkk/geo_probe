import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale, PlatformDispatcher, Rect;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import 'db.dart';
import 'l10n/app_localizations.dart';
import 'models.dart';
import 'native_bridge.dart';
import 'wording.dart';

/// Central app state: regions, config, diagnostics, event ingestion.
/// Screens query the DB directly and listen to this notifier for refreshes.
class AppState extends ChangeNotifier {
  final ProbeDb db = ProbeDb();
  final NativeBridge bridge = NativeBridge();
  static const _uuid = Uuid();

  List<Region> regions = [];
  AppConfig config = const AppConfig();
  Map<String, dynamic> diagnostics = {};
  DateTime? lastHeartbeat;

  // Telegram logger settings (stored in the local config table).
  bool tgEnabled = false;
  String tgToken = '';
  String tgChatId = '';

  /// Bumped whenever the events table changes, so screens re-query.
  int eventsRevision = 0;

  StreamSubscription<Map<String, dynamic>>? _eventSub;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    regions = await db.getRegions();
    final storedConfig = await db.getConfigValue('app_config');
    if (storedConfig != null) {
      try {
        config = AppConfig.fromJson(storedConfig);
      } catch (_) {}
    }
    tgEnabled = await db.getConfigValue('tg_enabled') == '1';
    tgToken = await db.getConfigValue('tg_token') ?? '';
    tgChatId = await db.getConfigValue('tg_chat') ?? '';

    await bridge.setConfig(config);
    await bridge.syncRegions(regions);
    await bridge.requestInitialPermissions();

    _eventSub = bridge.eventStream.listen(_onLiveEvent);

    await drainNativeEvents();
    await heartbeat();
    await bridge.requestStateForRegions();
    notifyListeners();
  }

  Future<void> _onLiveEvent(Map<String, dynamic> raw) async {
    try {
      final event = GeoEvent.fromMap(raw);
      final fresh = await db.insertEvents([event]);
      eventsRevision++;
      notifyListeners();
      if (fresh.isNotEmpty && _tgWorthy(event)) {
        unawaited(_tgSend(_tgFormat(event)));
      }
    } catch (e) {
      debugPrint('geo_probe: bad live event: $e');
    }
  }

  /// Imports events written natively (including terminated-state ones).
  Future<void> drainNativeEvents() async {
    final events = await bridge.drainNativeEvents();
    if (events.isNotEmpty) {
      // The drain returns everything from the JSONL file, including events
      // already ingested via the live stream (and already sent to Telegram).
      // insertEvents filters those out — only genuinely new ones go further.
      final fresh = await db.insertEvents(events);
      eventsRevision++;
      notifyListeners();
      // Accumulated background events go out as ONE combined message to
      // avoid Telegram rate limits.
      final worthy = fresh.where(_tgWorthy).toList();
      if (worthy.isNotEmpty) {
        var text = worthy.map(_tgFormat).join('\n\n');
        if (text.length > 3800) text = '${text.substring(0, 3800)}\n…';
        unawaited(_tgSend(text));
      }
    }
  }

  // ---- Telegram logger ----

  static const _tgTypes = {
    EventType.enter,
    EventType.exit,
    EventType.slc,
    EventType.relaunch,
    EventType.permissionChange,
    EventType.error,
  };

  bool _tgWorthy(GeoEvent e) => _tgTypes.contains(e.type);

  AppLocalizations get _labels {
    try {
      return lookupAppLocalizations(PlatformDispatcher.instance.locale);
    } catch (_) {
      return lookupAppLocalizations(const Locale('en'));
    }
  }

  String _tgFormat(GeoEvent e) {
    final t = _labels;
    final emoji = switch (e.type) {
      EventType.enter => '🟢',
      EventType.exit => '🔴',
      EventType.slc => '🔵',
      EventType.relaunch => '🟣',
      EventType.permissionChange => '🔐',
      _ => '⚠️',
    };
    final zone = regions
        .where((r) => r.id == e.regionId)
        .map((r) => r.name)
        .firstOrNull;
    final buffer =
        StringBuffer('$emoji ${eventTypeLabel(t, e.type)}');
    if (zone != null) buffer.write(' «$zone»');
    buffer.write('\n🕐 ${DateFormat('dd.MM HH:mm:ss').format(e.eventTime)}');
    final delay = e.deliveryDelay;
    if (delay.inSeconds >= 1) buffer.write(' (+${delay.inSeconds}s)');
    if (e.lat != null && e.lng != null) {
      buffer.write(
          '\n📍 ${e.lat!.toStringAsFixed(5)}, ${e.lng!.toStringAsFixed(5)}');
      if (e.accuracy != null) buffer.write(' ±${e.accuracy!.round()}m');
    }
    if (e.detail != null && e.detail!.isNotEmpty) {
      buffer.write('\nℹ️ ${e.detail}');
    }
    buffer.write('\n${appStateLabel(t, e.appState)}');
    return buffer.toString();
  }

  Future<void> _tgSend(String text) async {
    if (!tgEnabled || tgToken.isEmpty || tgChatId.isEmpty) return;
    try {
      final response = await http
          .post(
            Uri.parse('https://api.telegram.org/bot$tgToken/sendMessage'),
            body: {'chat_id': tgChatId, 'text': text},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        debugPrint('geo_probe: telegram ${response.statusCode}: '
            '${response.body}');
      }
    } catch (e) {
      debugPrint('geo_probe: telegram send failed: $e');
    }
  }

  Future<void> setTelegram(
      {required bool enabled,
      required String token,
      required String chatId}) async {
    tgEnabled = enabled;
    tgToken = token.trim();
    tgChatId = chatId.trim();
    await db.setConfigValue('tg_enabled', enabled ? '1' : '0');
    await db.setConfigValue('tg_token', tgToken);
    await db.setConfigValue('tg_chat', tgChatId);
    notifyListeners();
  }

  /// Records a diagnostics snapshot (§6.2 of the spec: the layer whose
  /// absence made previous generations undebuggable).
  Future<void> heartbeat() async {
    diagnostics = await bridge.getDiagnostics();
    lastHeartbeat = DateTime.now();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insertEvents([
      GeoEvent(
        uuid: _uuid.v4(),
        type: EventType.heartbeat,
        eventTs: now,
        receivedTs: now,
        appState: 'foreground',
        detail: jsonEncode(diagnostics),
      ),
    ]);
    eventsRevision++;
    notifyListeners();
  }

  /// Called from the root widget on app resume.
  Future<void> onResumed() async {
    await drainNativeEvents();
    await heartbeat();
  }

  // ---- Regions ----

  int get activeRegionCount => regions.where((r) => r.active).length;

  Future<void> addRegion(
      {required String name,
      required double lat,
      required double lng,
      required double radius}) async {
    final region =
        Region(id: _uuid.v4(), name: name, lat: lat, lng: lng, radius: radius);
    await db.upsertRegion(region);
    regions = await db.getRegions();
    await bridge.syncRegions(regions);
    await bridge.requestStateForRegions();
    notifyListeners();
  }

  Future<void> updateRegion(Region region) async {
    await db.upsertRegion(region);
    regions = await db.getRegions();
    await bridge.syncRegions(regions);
    notifyListeners();
  }

  Future<void> deleteRegion(String id) async {
    await db.deleteRegion(id);
    regions = await db.getRegions();
    await bridge.syncRegions(regions);
    notifyListeners();
  }

  Future<void> resyncRegions() async {
    await bridge.syncRegions(regions);
    await bridge.requestStateForRegions();
  }

  // ---- Config ----

  Future<void> setConfig(AppConfig next) async {
    config = next;
    await db.setConfigValue('app_config', next.toJson());
    await bridge.setConfig(next);
    notifyListeners();
  }

  // ---- History ----

  Future<void> clearHistory() async {
    await db.clearEvents();
    eventsRevision++;
    notifyListeners();
  }

  /// [origin] anchors the iOS share sheet popover — required on iPad and
  /// on recent iOS versions, otherwise share_plus throws
  /// "sharePositionOrigin: argument must be set".
  Future<void> exportHistory({Rect? origin}) async {
    final events = await db.allEvents();
    final payload = jsonEncode({
      'exported_at': DateTime.now().toIso8601String(),
      'regions': regions.map((r) => r.toChannelMap()).toList(),
      'config': config.toMap(),
      'events': events.map((e) => e.toMap()).toList(),
    });
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/geo_probe_export_$stamp.json');
    await file.writeAsString(payload);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        sharePositionOrigin: origin,
      ),
    );
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }
}
