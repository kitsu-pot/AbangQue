import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeeplink/src/app.dart';
import 'package:jeeplink/src/data/demo_jeepney_repository.dart';
import 'package:jeeplink/src/domain/jeepney_repository.dart';
import 'package:jeeplink/src/domain/passenger_route.dart';

import 'fakes.dart';

Future<void> startApp(
  WidgetTester tester, {
  Size size = const Size(1000, 1000),
  JeepneyRepository? repository,
  double textScale = 1,
  bool withRoutes = false,
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
      locationService: NoDeviceLocation(),
      repository: repository ?? DemoJeepneyRepository(),
      routeRepository: withRoutes
          ? TestRouteRepository()
          : const UnconfiguredRouteRepository(),
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

Future<void> chooseJourney(
  WidgetTester tester, {
  bool stayOnMap = false,
}) async {
  for (final entry in [(0, 'Boac'), (1, 'Gasan')]) {
    final field = find
        .byType(DropdownButtonFormField<Municipality>)
        .at(entry.$1);
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text(entry.$2).last);
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(find.text('Find Jeepneys'));
  await tester.tap(find.text('Find Jeepneys'));
  await tester.pumpAndSettle();
  if (!stayOnMap) await tab(tester, 'Jeepneys');
}

void main() {
  testWidgets('home labels demo and refresh never invents ETA', (tester) async {
    await startApp(tester);
    expect(find.byKey(const ValueKey('hero-title')), findsOneWidget);
    expect(find.text('DEMO'), findsWidgets);
    expect(find.text('ETA unavailable'), findsWidgets);
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.text('No registered routes available yet.'), findsOneWidget);
    expect(find.byKey(const ValueKey('vehicle-DEMO-01')), findsNothing);
    await tester.tap(find.byTooltip('Refresh demo'));
    await tester.pumpAndSettle();
    expect(find.text('ETA unavailable'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected route search, empty state, and full details work', (
    tester,
  ) async {
    await startApp(tester, withRoutes: true);
    expect(find.byKey(const ValueKey('vehicle-DEMO-02')), findsNothing);
    await chooseJourney(tester);
    expect(find.byKey(const ValueKey('vehicle-DEMO-02')), findsOneWidget);
    expect(find.byKey(const ValueKey('vehicle-DEMO-03')), findsNothing);
    await tester.enterText(find.byType(TextFormField), 'missing');
    await tester.pumpAndSettle();
    expect(find.text('No matching jeepneys'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'DEMO-02');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('vehicle-DEMO-02')));
    await tester.tap(find.byKey(const ValueKey('vehicle-DEMO-02')));
    await tester.pumpAndSettle();
    expect(find.text('Demo jeepney 02'), findsOneWidget);
    expect(find.text('MANUALLY REPORTED STATUS'), findsOneWidget);
    expect(find.text('Registered route'), findsOneWidget);
    expect(find.text('FULL'), findsWidgets);
    await tester.ensureVisible(find.text('View last location on map'));
    await tester.tap(find.text('View last location on map'));
    await tester.pumpAndSettle();
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byKey(const ValueKey('marker-DEMO-02')), findsOneWidget);
    await tester.tap(find.byTooltip('Expand full jeepney list'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('map markers open details and panel collapses', (tester) async {
    await startApp(tester, withRoutes: true);
    await chooseJourney(tester);
    await tab(tester, 'Map');
    await tester.ensureVisible(find.byKey(const ValueKey('marker-DEMO-01')));
    await tester.tap(find.byKey(const ValueKey('marker-DEMO-01')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selected-jeepney')), findsOneWidget);
    await tester.ensureVisible(find.text('View report details'));
    await tester.tap(find.text('View report details'));
    await tester.pumpAndSettle();
    expect(find.text('Demo jeepney 01'), findsWidgets);
    expect(find.text('MANUALLY REPORTED STATUS'), findsOneWidget);
    await tester.tap(find.byTooltip('Close details'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Collapse jeepney panel'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('guide explains limitations and returns to the map', (
    tester,
  ) async {
    await startApp(tester);
    await tab(tester, 'Guide');
    await tester.ensureVisible(
      find.text('Is AbangQue tracking real jeepneys?'),
    );
    await tester.tap(find.text('Is AbangQue tracking real jeepneys?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('It is not real GPS tracking.'), findsOneWidget);
    await tester.ensureVisible(find.text('Explore the map'));
    await tester.tap(find.text('Explore the map'));
    await tester.pumpAndSettle();
    expect(find.byType(FlutterMap), findsOneWidget);
  });

  testWidgets('empty, loading, and repository error states are recoverable', (
    tester,
  ) async {
    final repository = TestRepository();
    await tester.pumpWidget(
      JeepLinkApp(
        locationService: NoDeviceLocation(),
        repository: repository,
        tileProviderFactory: MemoryTileProvider.new,
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    repository.updates.addError(StateError('Unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to update the fleet'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to update the fleet'), findsNothing);
    expect(find.text('No registered routes available yet.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(repository.disposed, isTrue);
  });

  for (final scale in [1.0, 1.8, 2.0]) {
    testWidgets('small phone layout supports navigation at text scale $scale', (
      tester,
    ) async {
      await startApp(tester, size: const Size(320, 800), textScale: scale);
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
