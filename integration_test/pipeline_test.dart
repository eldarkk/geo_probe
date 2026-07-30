import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_probe/db.dart';
import 'package:geo_probe/main.dart';
import 'package:geo_probe/models.dart';
import 'package:geo_probe/native_bridge.dart';
import 'package:integration_test/integration_test.dart';

/// Verifies the native event pipeline that the journal depends on:
///   writeEvent (Swift) -> JSONL file -> drainNativeEvents -> SQLite.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('stage 1: native writeEvent lands in JSONL and drains',
      (tester) async {
    final bridge = NativeBridge();
    // bootstrap() already wrote at least one permission_change event at
    // process launch; registering a region and requesting state adds
    // state_initial (or error, if unauthorized). Either way the drain
    // must return something if the JSONL path works.
    await bridge.syncRegions([
      const Region(
          id: 'probe-test',
          name: 'Probe',
          lat: 51.1694,
          lng: 71.4491,
          radius: 200),
    ]);
    await bridge.requestStateForRegions();

    final drained = <GeoEvent>[];
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 3)));
      final batch = await tester.runAsync(bridge.drainNativeEvents);
      drained.addAll(batch ?? const []);
      if (drained.isNotEmpty) break;
    }
    debugPrint(
        'STAGE1 DRAINED: ${drained.map((e) => '${e.type}(${e.detail})').toList()}');
    expect(drained, isNotEmpty,
        reason: 'native JSONL/drain path returned nothing');
  });

  testWidgets('stage 2: full app ingests native events into SQLite',
      (tester) async {
    // Seed a region so app init registers it and requests its state,
    // producing native events (state_initial or error).
    final db = ProbeDb();
    await tester.runAsync(() => db.upsertRegion(const Region(
        id: 'probe-test-2',
        name: 'Probe2',
        lat: 51.1694,
        lng: 71.4491,
        radius: 200)));

    await tester.pumpWidget(const GeoProbeApp());
    await tester.pump(const Duration(seconds: 2));

    List<GeoEvent> nativeOnes = [];
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 3)));
      await tester.pump(const Duration(milliseconds: 100));
      final events =
          await tester.runAsync(() => db.eventsForDay(DateTime.now()));
      nativeOnes = (events ?? [])
          .where((e) =>
              e.type == EventType.stateInitial ||
              e.type == EventType.permissionChange ||
              e.type == EventType.error)
          .toList();
      if (nativeOnes.isNotEmpty) break;
    }
    final all = await tester.runAsync(() => db.eventsForDay(DateTime.now()));
    debugPrint(
        'STAGE2 DB EVENTS: ${(all ?? []).map((e) => '${e.type}(${e.detail})').toList()}');
    expect(nativeOnes, isNotEmpty,
        reason: 'no native-originated events reached SQLite via the app');
  });
}
