import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeeplink/src/app.dart';
import 'package:jeeplink/src/data/demo_jeepney_repository.dart';
import 'package:jeeplink/src/domain/jeepney_repository.dart';

import 'fakes.dart';

Future<void> startApp(
  WidgetTester tester, {
  Size size = const Size(1000, 1000),
  JeepneyRepository? repository,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(
    JeepLinkApp(
      repository: repository ?? DemoJeepneyRepository(),
      tileProviderFactory: MemoryTileProvider.new,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tab(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(name)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('home identifies the demo and refresh changes the sample ETA', (
    tester,
  ) async {
    await startApp(tester);
    expect(find.text('Tara, sakay na.'), findsOneWidget);
    expect(find.text('DEMO'), findsWidgets);
    expect(find.text('4 min'), findsWidgets);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    await tester.tap(find.byTooltip('Refresh demo'));
    await tester.pumpAndSettle();
    expect(find.text('5 min'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fleet filter, search, empty state, and full details work', (
    tester,
  ) async {
    await startApp(tester);
    await tab(tester, 'Jeepneys');
    expect(find.byKey(const ValueKey('vehicle-DEMO-02')), findsOneWidget);
    await tester.tap(find.text('Available (2)'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vehicle-DEMO-02')), findsNothing);
    await tester.enterText(find.byType(TextFormField), 'DEMO-02');
    await tester.pumpAndSettle();
    expect(find.text('No matching jeepneys'), findsOneWidget);
    await tester.tap(find.text('All jeepneys (3)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vehicle-DEMO-02')));
    await tester.pumpAndSettle();
    expect(find.text('Demo jeepney 02'), findsOneWidget);
    expect(find.text('0 of 18 seats open'), findsOneWidget);
    expect(find.text('No official route assigned'), findsOneWidget);
    expect(find.text('FULL'), findsWidgets);
    await tester.ensureVisible(find.text('View on demo map'));
    await tester.tap(find.text('View on demo map'));
    await tester.pumpAndSettle();
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byKey(const ValueKey('marker-DEMO-02')), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).initialValue,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('map markers open details and zoom/reset controls work', (
    tester,
  ) async {
    await startApp(tester);
    await tab(tester, 'Map');
    await tester.tap(find.byKey(const ValueKey('marker-DEMO-01')));
    await tester.pumpAndSettle();
    expect(find.text('Demo jeepney 01'), findsOneWidget);
    expect(find.text('8 of 18 seats open'), findsOneWidget);
    await tester.tap(find.byTooltip('Close details'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reset to demo area'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('guide explains limitations and returns to the map', (
    tester,
  ) async {
    await startApp(tester);
    await tab(tester, 'Guide');
    await tester.ensureVisible(
      find.text('Is JeepLink tracking real jeepneys?'),
    );
    await tester.tap(find.text('Is JeepLink tracking real jeepneys?'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Real GPS hardware and a backend are not connected.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Try the demo map'));
    await tester.tap(find.text('Try the demo map'));
    await tester.pumpAndSettle();
    expect(find.byType(FlutterMap), findsOneWidget);
  });

  testWidgets('empty, loading, and repository error states are recoverable', (
    tester,
  ) async {
    final repository = TestRepository();
    await tester.pumpWidget(
      JeepLinkApp(
        repository: repository,
        tileProviderFactory: MemoryTileProvider.new,
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.updates.addError(StateError('Unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to update the fleet'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to update the fleet'), findsNothing);
    expect(find.text('No jeepneys to show'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(repository.disposed, isTrue);
  });

  for (final scale in [1.0, 1.8]) {
    testWidgets('small phone layout supports navigation at text scale $scale', (
      tester,
    ) async {
      await startApp(tester, size: const Size(360, 800), textScale: scale);
      expect(tester.takeException(), isNull);
      for (final name in ['Jeepneys', 'Map', 'Guide', 'Home']) {
        await tab(tester, name);
        expect(
          tester.takeException(),
          isNull,
          reason: '$name must not overflow',
        );
      }
    });
  }
}
