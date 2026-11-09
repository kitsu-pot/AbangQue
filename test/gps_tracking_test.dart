import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jeeplink/src/config/data_config.dart';
import 'package:jeeplink/src/data/api_jeepney_repository.dart';
import 'package:jeeplink/src/data/api_route_repository.dart';
import 'package:jeeplink/src/domain/jeepney.dart';
import 'package:jeeplink/src/domain/passenger_route.dart';
import 'package:jeeplink/src/presentation/jeepney_controller.dart';

import 'fakes.dart';

Map<String, Object?> simulated(DateTime now) => {
  'id': 'SIM-GPS-001',
  'name': 'SIMULATED GPS test',
  'source': 'simulated',
  'isDemo': true,
  'isSimulated': true,
  'isStale': false,
  'connectionStatus': 'ONLINE',
  'status': 'AVAILABLE',
  'timestamp': now.toIso8601String(),
  'lastSeenAt': now.toIso8601String(),
  'eta': null,
  'position': {'latitude': 13.446, 'longitude': 121.84},
};
void main() {
  test(
    'local simulator flag is forbidden in release, remote API and offline DEMO',
    () {
      for (final options in [
        (false, 'api', 'https://127.0.0.1'),
        (true, 'api', 'https://example.com'),
        (true, 'demo', 'http://127.0.0.1'),
      ]) {
        expect(
          () => DataConfig.parse(
            mode: options.$2,
            url: options.$3,
            platform: TargetPlatform.android,
            debug: options.$1,
            enableGpsSimulation: true,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test('fresh simulated status is labeled; historical data cannot become availability', () {
    final record = simulated(DateTime.now().toUtc());
    final vehicle = parseApiJeepney(record);
    expect(vehicle.status, OccupancyStatus.available);
    expect(vehicle.sourceLabel, contains('SIMULATED / DEMO'));
    expect(vehicle.hasFreshReport, false);
    expect(vehicle.eta, isNull);
    expect(vehicle.asStale().status, OccupancyStatus.unknown);
    expect(
      parseApiJeepney({
        ...record,
        'source': 'demo',
        'isSimulated': false,
        'connectionStatus': 'DEMO',
      }).status,
      OccupancyStatus.unknown,
    );
    expect(
      () => parseApiJeepney({...record, 'isSimulated': false}),
      throwsFormatException,
    );
  });
  test('backend catalog is opt-in, directed, validated and does not infer assignments', () async {
    final data = {
      'data': {
        'routes': [
          {
            'id': 'SIM-ROUTE',
            'origin': 'Boac',
            'destination': 'Mogpog',
            'isDemo': true,
          },
        ],
        'assignments': [
          {'routeId': 'SIM-ROUTE', 'jeepneyId': 'SIM-GPS-001'},
        ],
      },
    };
    ApiRouteRepository repo({bool allow = false, int status = 200}) =>
        ApiRouteRepository(
          baseUrl: Uri.parse('http://127.0.0.1'),
          allowSimulation: allow,
          clientFactory: () => MockClient((request) async {
            expect(request.url.path, '/api/routes');
            expect(request.followRedirects, false);
            expect(request.headers.containsKey('authorization'), false);
            return http.Response(jsonEncode(data), status);
          }),
        );
    expect((await repo().loadCatalog()).routes, isEmpty);
    final catalog = await repo(allow: true).loadCatalog();
    expect(catalog.routes.single.origin, Municipality.boac);
    expect(catalog.routes.single.destination, Municipality.mogpog);
    expect(catalog.routes.single.label, contains('DEMO'));
    await expectLater(repo(status: 404).loadCatalog(), throwsFormatException);
    await expectLater(repo(status: 503).loadCatalog(), throwsFormatException);
  });
  test(
    'route filtering never mixes simulated and registered vehicle assignments',
    () async {
      final routes = TestRouteRepository()
        ..catalog = RouteCatalog(
          routes: [
            PassengerRoute(
              id: 'SIM-ROUTE',
              origin: Municipality.boac,
              destination: Municipality.mogpog,
              isDemo: true,
            ),
            PassengerRoute(
              id: 'REAL-TEST',
              origin: Municipality.mogpog,
              destination: Municipality.boac,
            ),
          ],
          assignments: [
            for (final route in ['SIM-ROUTE', 'REAL-TEST'])
              for (final id in ['SIM-GPS-001', 'REAL-TEST'])
                RouteAssignment(jeepneyId: id, routeId: route),
          ],
        );
      final repository = TestRepository();
      final controller = JeepneyController(
        repository,
        routeRepository: routes,
        apiMode: true,
      );
      repository.updates.add([
        parseApiJeepney(simulated(DateTime.now().toUtc())),
        parseApiJeepney({
          ...simulated(DateTime.now().toUtc()),
          'id': 'REAL-TEST',
          'source': 'device',
          'isDemo': false,
          'isSimulated': false,
        }),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.journeyVehicles, isEmpty);
      controller.setOrigin(Municipality.boac);
      controller.setDestination(Municipality.mogpog);
      controller.findJeepneys();
      expect(controller.journeyVehicles.single.id, 'SIM-GPS-001');
      controller.swapJourney();
      controller.findJeepneys();
      expect(controller.journeyVehicles.single.id, 'REAL-TEST');
      controller.dispose();
      await repository.dispose();
    },
  );
  test(
    'status expires between polls and resumes only after a fresh API response',
    () async {
      var record = simulated(DateTime.now().toUtc());
      final fresh = Completer<Jeepney>();
      final expired = Completer<Jeepney>();
      final snapshots = <List<Jeepney>>[];
      final repo = ApiJeepneyRepository(
        baseUrl: Uri.parse('http://127.0.0.1'),
        allowSimulation: true,
        pollInterval: null,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': [record],
              'meta': {'staleAfterSeconds': 2},
            }),
            200,
          ),
        ),
      );
      final sub = repo.watchJeepneys().listen((rows) {
        snapshots.add(rows);
        if (rows.single.isStale && !expired.isCompleted) {
          expired.complete(rows.single);
        }
        if (!rows.single.isStale && !fresh.isCompleted) {
          fresh.complete(rows.single);
        }
      });
      try {
        expect(
          (await fresh.future.timeout(const Duration(seconds: 3))).status,
          OccupancyStatus.available,
        );
        expect(
          (await expired.future.timeout(const Duration(seconds: 4))).status,
          OccupancyStatus.unknown,
        );
        record = simulated(DateTime.now().toUtc())..['status'] = 'FULL';
        await repo.refresh();
        await Future<void>.delayed(Duration.zero);
        expect(snapshots.last.single.status, OccupancyStatus.full);
      } finally {
        await sub.cancel();
        await repo.dispose();
      }
    },
  );
}
