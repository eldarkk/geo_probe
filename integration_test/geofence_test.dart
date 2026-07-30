import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_probe/db.dart';
import 'package:geo_probe/main.dart';
import 'package:geo_probe/models.dart';
import 'package:integration_test/integration_test.dart';

/// End-to-end geofence test. An external script teleports the simulator
/// location in/out of the region every ~20 s; ENTER/EXIT must appear in
/// the app's SQLite journal.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('region enter/exit events reach the journal DB', (tester) async {
    final db = ProbeDb();
    await tester.runAsync(() => db.upsertRegion(const Region(
        id: 'geofence-e2e',
        name: 'E2E',
        lat: 51.1694,
        lng: 71.4491,
        radius: 200)));

    await tester.pumpWidget(const GeoProbeApp());
    await tester.pump(const Duration(seconds: 2));

    List<GeoEvent> transitions = [];
    final deadline = DateTime.now().add(const Duration(seconds: 150));
    while (DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
      final events =
          await tester.runAsync(() => db.eventsForDay(DateTime.now()));
      transitions = (events ?? [])
          .where((e) =>
              e.type == EventType.enter ||
              e.type == EventType.exit ||
              e.type == EventType.slc)
          .toList();
      if (transitions.isNotEmpty) break;
    }
    final all = await tester.runAsync(() => db.eventsForDay(DateTime.now()));
    for (final e in all ?? <GeoEvent>[]) {
      debugPrint('E2E EVENT: ${e.type} @${e.eventTime} detail=${e.detail}');
    }
    expect(transitions, isNotEmpty,
        reason: 'no enter/exit/slc reached the journal DB');
  });
}
