import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:jeeplink/src/app.dart';
import 'package:jeeplink/src/data/api_jeepney_repository.dart';
import 'package:jeeplink/src/data/api_route_repository.dart';
import 'package:jeeplink/src/domain/passenger_route.dart';

import 'fakes.dart';
import 'widget_test.dart' show tab;

// Native HTTP only in this explicitly enabled test. No test device secret enters Dart.
class _NativeHttp extends HttpOverrides {}

http.Client nativeClient() => HttpOverrides.runWithHttpOverrides(
  () => IOClient(HttpClient()),
  _NativeHttp(),
);

class _LoadedRoutes implements RouteRepository {
  _LoadedRoutes(this.catalog);
  final RouteCatalog catalog;
  @override
  Future<RouteCatalog> loadCatalog() async => catalog;
}

void main() {
  const url = String.fromEnvironment('GPS_E2E_URL');
  testWidgets(
    'real PostgreSQL simulator updates Flutter details, route markers and stale recovery',
    (tester) async {
      final origin = Uri.parse(url);
      expect(origin.host, '127.0.0.1');
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final control = nativeClient();
      addTearDown(control.close);
      final repo = ApiJeepneyRepository(
        baseUrl: origin,
        client: nativeClient(),
        pollInterval: null,
        allowSimulation: true,
      );
      Future<void> command(String name) async {
        await tester.runAsync(() async {
          final result = await control
              .post(origin.resolve('/__test/$name'))
              .timeout(const Duration(seconds: 10));
          expect(result.statusCode, 204);
          await repo.refresh();
        });
        await tester.pumpAndSettle();
      }

      await tester.runAsync(() async {
        expect(
          (await control.post(origin.resolve('/__test/available'))).statusCode,
          204,
        );
        await repo.watchJeepneys().first;
      });
      final catalog = await tester.runAsync(
        () => ApiRouteRepository(
          baseUrl: origin,
          allowSimulation: true,
          clientFactory: nativeClient,
        ).loadCatalog(),
      );
      expect(catalog!.routes.single.isDemo, true);
      expect(catalog.assignments.single.jeepneyId, 'SIM-GPS-001');
      await tester.pumpWidget(
        JeepLinkApp(
          repository: repo,
          routeRepository: _LoadedRoutes(catalog),
          apiMode: true,
          tileProviderFactory: MemoryTileProvider.new,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vehicle-SIM-GPS-001')), findsNothing);
      for (final entry in [(0, 'Boac'), (1, 'Mogpog')]) {
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
      expect(find.byKey(const ValueKey('vehicle-UNASSIGNED')), findsNothing);
      final card = find.byKey(const ValueKey('vehicle-SIM-GPS-001'));
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.text('Cooperative / operator'), findsOneWidget);
      expect(find.text('Information unavailable'), findsOneWidget);
      expect(find.text('SIMULATED / DEMO'), findsOneWidget);
      expect(find.text('13.44600, 121.84000'), findsOneWidget);
      await command('full');
      expect(find.text('FULL'), findsWidgets);
      expect(find.text('13.44630, 121.84030'), findsOneWidget);
      await tester.ensureVisible(find.text('View last location on map'));
      await tester.tap(find.text('View last location on map'));
      await tester.pumpAndSettle();
      Marker marker() =>
          tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.single;
      expect(marker().point.latitude, closeTo(13.4463, .000001));
      await command('available');
      expect(marker().point.latitude, closeTo(13.4466, .000001));
      expect(
        tester
            .widget<FlutterMap>(find.byType(FlutterMap))
            .mapController!
            .camera
            .center
            .latitude,
        closeTo(13.4466, .000001),
      );
      await command('stale');
      expect(find.text('STALE / UNKNOWN'), findsWidgets);
      expect(find.textContaining('OFFLINE / STALE'), findsWidgets);
      await command('full');
      expect(find.text('STALE / UNKNOWN'), findsNothing);
      expect(find.text('FULL'), findsWidgets);
      expect(find.textContaining('ETA unavailable'), findsWidgets);
      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .join(' ');
      expect(
        text,
        isNot(
          matches(RegExp(r'\d+\s+(seats?|minutes?)', caseSensitive: false)),
        ),
      );
      await tab(tester, 'Home');
      await tester.ensureVisible(find.byTooltip('Swap origin and destination'));
      await tester.tap(find.byTooltip('Swap origin and destination'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Find Jeepneys'));
      await tester.tap(find.text('Find Jeepneys'));
      await tester.pumpAndSettle();
      await tab(tester, 'Map');
      expect(
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    skip: url.isEmpty,
  );
}
