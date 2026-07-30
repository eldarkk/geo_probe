import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_probe/main.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('long-press on the map opens the region dialog', (tester) async {
    await tester.pumpWidget(const GeoProbeApp());
    await tester.pump(const Duration(seconds: 3));

    final map = find.byType(FlutterMap);
    expect(map, findsOneWidget);

    await tester.longPressAt(tester.getCenter(map));
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(AlertDialog), findsOneWidget,
        reason: 'region creation dialog should appear after long-press');

    // Interact with the dialog: move the slider and confirm.
    await tester.enterText(find.byType(TextField), 'Test zone');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byType(FilledButton));
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(AlertDialog), findsNothing);
  });
}
