import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeeplink/src/data/demo_jeepney_repository.dart';
import 'package:jeeplink/src/domain/passenger_route.dart';
import 'package:jeeplink/src/presentation/jeepney_controller.dart';

import 'fakes.dart';
import 'widget_test.dart' show startApp, tab, chooseJourney;

Future<void> flush() => Future<void>.delayed(Duration.zero);
void selectForward(JeepneyController c) {
  c.setOrigin(Municipality.boac);
  c.setDestination(Municipality.gasan);
  c.findJeepneys();
}

void main() {
  test('default catalog never assigns API or offline demo vehicles', () async {
    for (final api in [true, false]) {
      final repository = DemoJeepneyRepository();
      final c = JeepneyController(repository, apiMode: api);
      await flush();
      selectForward(c);
      expect(c.vehicles, hasLength(3));
      expect(c.routes, isEmpty);
      expect(c.journeyVehicles, isEmpty);
      expect(c.filteredVehicles, isEmpty);
      c.dispose();
      await repository.dispose();
    }
  });

  test(
    'directions, explicit assignments, search and changed journey are isolated',
    () async {
      final repository = DemoJeepneyRepository();
      final c = JeepneyController(
        repository,
        routeRepository: TestRouteRepository(),
      );
      await flush();
      expect(c.filteredVehicles, isEmpty);
      selectForward(c);
      expect(c.journeyVehicles.map((v) => v.id), ['DEMO-01', 'DEMO-02']);
      c.setQuery('DEMO-03');
      expect(c.filteredVehicles, isEmpty);
      c.swapJourney();
      expect(c.filteredVehicles, isEmpty);
      expect(c.query, isEmpty);
      c.findJeepneys();
      expect(c.filteredVehicles.single.id, 'DEMO-03');
      c.setDestination(Municipality.gasan);
      c.findJeepneys();
      expect(c.validJourney, isFalse);
      expect(c.selectedRoute, isNull);
      c.setDestination(Municipality.torrijos);
      c.findJeepneys();
      expect(c.matchingRoutes, isEmpty);
      expect(c.filteredVehicles, isEmpty);
      c.dispose();
      await repository.dispose();
    },
  );

  test(
    'route refresh removes revoked assignments and fails closed then recovers',
    () async {
      final routes = TestRouteRepository();
      final repository = DemoJeepneyRepository();
      final c = JeepneyController(repository, routeRepository: routes);
      await flush();
      selectForward(c);
      routes.catalog = RouteCatalog(routes: routes.catalog.routes);
      await c.refresh();
      expect(c.filteredVehicles, isEmpty);
      routes.fail = true;
      await c.refresh();
      expect(c.routesError, isNotNull);
      expect(c.selectedRoute, isNull);
      routes.fail = false;
      routes.catalog = testRouteCatalog();
      await c.refresh();
      expect(c.routesError, isNull);
      expect(c.filteredVehicles, isEmpty);
      c.findJeepneys();
      expect(c.filteredVehicles, hasLength(2));
      routes.catalog = RouteCatalog();
      await c.refresh();
      expect(c.selectedRoute, isNull);
      expect(c.filteredVehicles, isEmpty);
      c.dispose();
      await repository.dispose();
    },
  );

  test(
    'multiple registered routes in one direction require explicit route choice',
    () async {
      final routes = TestRouteRepository();
      routes.catalog = RouteCatalog(
        routes: [
          ...routes.catalog.routes,
          PassengerRoute(
            id: 'TEST-OTHER',
            origin: Municipality.boac,
            destination: Municipality.gasan,
          ),
        ],
        assignments: routes.catalog.assignments,
      );
      final repository = DemoJeepneyRepository();
      final c = JeepneyController(repository, routeRepository: routes);
      await flush();
      selectForward(c);
      expect(c.matchingRoutes, hasLength(2));
      expect(c.filteredVehicles, isEmpty);
      c.selectRoute('TEST-REVERSE');
      expect(c.selectedRoute, isNull);
      c.selectRoute('TEST-FORWARD');
      expect(c.filteredVehicles, hasLength(2));
      c.dispose();
      await repository.dispose();
    },
  );

  test('late route response cannot replace a newer refresh', () async {
    final routes = _DelayedRoutes();
    final repository = DemoJeepneyRepository();
    final c = JeepneyController(repository, routeRepository: routes);
    final refresh = c.refresh();
    routes.calls[1].complete(RouteCatalog());
    await refresh;
    routes.calls[0].complete(testRouteCatalog());
    await flush();
    expect(c.routes, isEmpty);
    expect(c.routesLoading, isFalse);
    c.dispose();
    await repository.dispose();
  });

  test('catalog rejects duplicate IDs, invalid directions and dangling assignments', () {
    final route = testRouteCatalog().routes.first;
    expect(() => RouteCatalog(routes: [route, route]), throwsArgumentError);
    expect(
      () => PassengerRoute(
        id: 'bad',
        origin: Municipality.boac,
        destination: Municipality.boac,
      ),
      throwsArgumentError,
    );
    expect(
      () => RouteCatalog(
        assignments: const [
          RouteAssignment(jeepneyId: 'D', routeId: 'missing'),
        ],
      ),
      throwsArgumentError,
    );
  });

  testWidgets(
    'municipality preview never exposes unassigned demo markers or cards',
    (tester) async {
      await startApp(tester);
      await chooseJourney(tester);
      expect(find.text('No registered routes available yet.'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byKey(const ValueKey('vehicle-DEMO-01')), findsNothing);
      await tab(tester, 'Map');
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byKey(const ValueKey('marker-DEMO-01')), findsNothing);
      await tester.tap(find.byTooltip('Change journey'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Swap origin and destination'));
      await tester.tap(find.byTooltip('Swap origin and destination'));
      await tester.pumpAndSettle();
      final fields = tester
          .widgetList<DropdownButtonFormField<Municipality>>(
            find.byType(DropdownButtonFormField<Municipality>),
          )
          .toList();
      expect(fields[0].initialValue, Municipality.gasan);
      expect(fields[1].initialValue, Municipality.boac);
      expect(
        tester
            .widget<DropdownButton<Municipality>>(
              find.byType(DropdownButton<Municipality>).first,
            )
            .items!
            .map((i) => i.value),
        Municipality.values,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _DelayedRoutes implements RouteRepository {
  final calls = <Completer<RouteCatalog>>[];
  @override
  Future<RouteCatalog> loadCatalog() {
    final call = Completer<RouteCatalog>();
    calls.add(call);
    return call.future;
  }
}
