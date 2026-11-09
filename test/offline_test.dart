import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jeeplink/src/app.dart';
import 'package:jeeplink/src/auth/auth_controller.dart';
import 'package:jeeplink/src/auth/passenger_auth.dart';
import 'package:jeeplink/src/data/api_jeepney_repository.dart';
import 'package:jeeplink/src/data/api_route_repository.dart';
import 'package:jeeplink/src/data/public_cache/public_cache.dart';
import 'package:jeeplink/src/data/public_cache/cache_factory_io.dart';
import 'package:jeeplink/src/domain/jeepney.dart';
import 'package:jeeplink/src/domain/passenger_route.dart';
import 'package:jeeplink/src/favorites/favorite_controller.dart';
import 'package:jeeplink/src/presentation/jeepney_controller.dart';
import 'package:jeeplink/src/presentation/screens/route_map_screen.dart';

import 'api_repository_test.dart' show record;
import 'auth_test.dart' show MemorySessionStore, api, data, session;
import 'favorites_test.dart' show FavoriteFixture, forward;
import 'fakes.dart';
import 'widget_test.dart' show chooseJourney, tab;

final origin = Uri.parse('http://127.0.0.1:3000');
// Explicit test-only catalog/assignments, never production route seeds.
Map<String, Object> catalog() => {
  'routes': [
    {
      'id': forward.id,
      'origin': 'Boac',
      'destination': 'Gasan',
      'isDemo': false,
    },
    {
      'id': 'TEST-REVERSE',
      'origin': 'Gasan',
      'destination': 'Boac',
      'isDemo': false,
    },
  ],
  'assignments': [
    {'jeepneyId': 'CACHE-01', 'routeId': forward.id},
    {'jeepneyId': 'CACHE-02', 'routeId': 'TEST-REVERSE'},
  ],
};
Map<String, dynamic> vehicle(DateTime time, [String id = 'CACHE-01']) => {
  ...record(id),
  'source': 'device',
  'isDemo': false,
  'isStale': false,
  'connectionStatus': 'ONLINE',
  'status': 'AVAILABLE',
  'timestamp': time.toUtc().toIso8601String(),
  'lastSeenAt': time.toUtc().toIso8601String(),
  'password': 'must-not-cache',
  'passengerWaitingPoint': {'latitude': 1, 'longitude': 2},
};
http.Response fleetResponse(DateTime now) => http.Response(
  jsonEncode({
    'data': [vehicle(now), vehicle(now, 'CACHE-02')],
    'meta': {'staleAfterSeconds': 120},
  }),
  200,
);
http.Response routeResponse() =>
    http.Response(jsonEncode({'data': catalog()}), 200);
Future<void> tick() => Future<void>.delayed(Duration.zero);

class AbortClient extends http.BaseClient {
  int calls = 0, active = 0, maxActive = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    active++;
    if (active > maxActive) maxActive = active;
    try {
      await (request as http.AbortableRequest).abortTrigger;
      throw http.ClientException('aborted');
    } finally {
      active--;
    }
  }
}

void main() {
  testWidgets(
    'public polling pauses in background even while the login screen is open',
    (tester) async {
      var calls = 0;
      final fleet = ApiJeepneyRepository(
        baseUrl: origin,
        pollInterval: null,
        client: MockClient((_) async {
          calls++;
          return fleetResponse(DateTime.now());
        }),
      );
      final routes = ApiRouteRepository(
        baseUrl: origin,
        clientFactory: () => MockClient((_) async => routeResponse()),
      );
      final auth = AuthController(
        store: MemorySessionStore(),
        repository: api((_) async => data(session())),
      );
      await tester.pumpWidget(
        JeepLinkApp(
          repository: fleet,
          routeRepository: routes,
          apiMode: true,
          pollInterval: const Duration(seconds: 10),
          authController: auth,
          locationService: NoDeviceLocation(),
          tileProviderFactory: MemoryTileProvider.new,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Welcome aboard'), findsOneWidget);
      expect(calls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 35));
      expect(calls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Welcome aboard'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'cached routes are usable before a slow startup API request completes',
    () async {
      final now = DateTime.now().toUtc();
      final cache = MemoryPublicCache()
        ..entries['routes'] = CacheEntry(catalog(), now);
      final pending = Completer<http.Response>();
      var calls = 0;
      final routes = ApiRouteRepository(
        baseUrl: origin,
        cache: cache,
        clientFactory: () => MockClient((_) {
          calls++;
          return pending.future;
        }),
      );
      final fleet = ApiJeepneyRepository(
        baseUrl: origin,
        pollInterval: null,
        client: MockClient((_) async => http.Response('', 503)),
      );
      final c = JeepneyController(
        fleet,
        routeRepository: routes,
        apiMode: true,
      );
      await tick();
      expect(c.routes, hasLength(2));
      expect(c.routesLoading, isFalse);
      c.setOrigin(Municipality.boac);
      c.setDestination(Municipality.gasan);
      c.findJeepneys();
      expect(c.selectedRoute?.id, forward.id);
      final retry = c.refresh();
      expect(calls, 1);
      pending.complete(http.Response('', 404));
      await retry;
      expect(c.selectedRoute?.id, forward.id);
      expect(c.offline, isTrue);
      c.dispose();
      await fleet.dispose();
    },
  );

  testWidgets(
    'offline cold start without cache shows honest empty state and no simulated fleet',
    (tester) async {
      final fleet = ApiJeepneyRepository(
        baseUrl: origin,
        cache: MemoryPublicCache(),
        pollInterval: null,
        client: MockClient((_) async => http.Response('', 503)),
      );
      final routes = ApiRouteRepository(
        baseUrl: origin,
        cache: MemoryPublicCache(),
        clientFactory: () => MockClient((_) async => http.Response('', 503)),
      );
      await tester.pumpWidget(
        JeepLinkApp(
          repository: fleet,
          routeRepository: routes,
          apiMode: true,
          locationService: NoDeviceLocation(),
          tileProviderFactory: MemoryTileProvider.new,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('API unreachable · No saved information'),
        findsOneWidget,
      );
      expect(
        find.textContaining('There is no saved information to show yet.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('vehicle-DEMO-01')), findsNothing);
      expect(find.byKey(const ValueKey('guest-favorites')), findsOneWidget);
      await tab(tester, 'Map');
      expect(find.byKey(const ValueKey('marker-DEMO-01')), findsNothing);
      expect(find.byTooltip('Retry connection'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('sanitized public snapshots persist; offline restart retains original clocks and unknown availability', () async {
    final cache = MemoryPublicCache();
    final now = DateTime.now().toUtc();
    final first = ApiJeepneyRepository(
      baseUrl: origin,
      cache: cache,
      pollInterval: null,
      client: MockClient((_) async => fleetResponse(now)),
    );
    final routes = ApiRouteRepository(
      baseUrl: origin,
      cache: cache,
      clientFactory: () => MockClient((_) async => routeResponse()),
    );
    await first.refresh();
    await routes.loadCatalog();
    final saved = cache.entries['jeepneys']!;
    final serialized = jsonEncode(saved.data);
    expect(serialized, isNot(contains('must-not-cache')));
    expect(serialized, isNot(contains('passengerWaitingPoint')));
    expect(serialized, isNot(contains('password')));
    expect(serialized, isNot(contains('eta')));
    await first.dispose();
    final second = ApiJeepneyRepository(
      baseUrl: origin,
      cache: cache,
      pollInterval: null,
      client: MockClient((_) async => http.Response('', 503)),
    );
    final cachedRoutes = ApiRouteRepository(
      baseUrl: origin,
      cache: cache,
      clientFactory: () => MockClient((_) async => http.Response('', 503)),
    );
    final controller = JeepneyController(
      second,
      routeRepository: cachedRoutes,
      apiMode: true,
    );
    await tick();
    await controller.refresh();
    await tick();
    expect(controller.offline, isTrue);
    expect(controller.routes.length, 2);
    controller.setOrigin(Municipality.boac);
    controller.setDestination(Municipality.gasan);
    controller.findJeepneys();
    final last = controller.journeyVehicles.single;
    expect(last.isCached, isTrue);
    expect(last.recordedAt, now);
    expect(last.lastSeenAt, now);
    expect(last.retrievedAt, saved.receivedAt);
    expect(last.status, OccupancyStatus.unknown);
    expect(last.eta, isNull);
    expect(last.lastReportedStatus, OccupancyStatus.available);
    controller.swapJourney();
    controller.findJeepneys();
    expect(controller.journeyVehicles.single.id, 'CACHE-02');
    controller.setDestination(Municipality.torrijos);
    controller.findJeepneys();
    expect(controller.journeyVehicles, isEmpty);
    controller.dispose();
    await second.dispose();
  });

  test('disk cache enforces retention, size, API/simulator isolation, throttled writes and corrupt-file recovery', () async {
    final directory = await Directory.systemTemp.createTemp(
      'abangque-public-cache-test-',
    );
    var now = DateTime.utc(2026, 11, 9);
    final cache = FilePublicCache(
      scope: 'api-a|simulation=false',
      directory: () async => directory,
      clock: () => now,
    );
    try {
      await cache.write('routes', CacheEntry(catalog(), now));
      final first = await File('${directory.path}/routes.json').readAsString();
      now = now.add(const Duration(seconds: 20));
      await cache.write(
        'routes',
        CacheEntry({'routes': [], 'assignments': []}, now),
      );
      expect(await File('${directory.path}/routes.json').readAsString(), first);
      final other = FilePublicCache(
        scope: 'api-b|simulation=false',
        directory: () async => directory,
        clock: () => now,
      );
      expect(await other.read('routes'), isNull);
      final simulation = FilePublicCache(
        scope: 'api-a|simulation=true',
        directory: () async => directory,
        clock: () => now,
      );
      expect(await simulation.read('routes'), isNull);
      now = now.add(const Duration(minutes: 1));
      await expectLater(
        cache.write('jeepneys', CacheEntry('x' * publicCacheMaxBytes, now)),
        throwsFormatException,
      );
      expect(await cache.read('jeepneys'), isNull);
      now = now.add(const Duration(hours: 24));
      expect(await cache.read('routes'), isNull);
      await File('${directory.path}/routes.json').writeAsString('{bad');
      expect(await cache.read('routes'), isNull);
      await cache.write('routes', CacheEntry(catalog(), now));
      expect(await cache.read('routes'), isNotNull);
      await expectLater(
        cache.write('../private', CacheEntry({}, now)),
        throwsArgumentError,
      );
    } finally {
      // Only this test's newly created random temporary directory.
      final resolved = await directory.resolveSymbolicLinks();
      final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
      if (!resolved.startsWith(
        '$tempRoot${Platform.pathSeparator}abangque-public-cache-test-',
      )) {
        throw StateError('Unexpected test cleanup path');
      }
      await directory.delete(recursive: true);
    }
  });

  test('expired, future-dated and malformed caches do not invent records or switch to DEMO', () async {
    final now = DateTime.now().toUtc();
    for (final entry in [
      CacheEntry([vehicle(now)], now.subtract(const Duration(hours: 24))),
      CacheEntry([vehicle(now)], now.add(const Duration(hours: 1))),
      CacheEntry([
        {'bad': true},
      ], now),
    ]) {
      final cache = MemoryPublicCache()..entries['jeepneys'] = entry;
      final repo = ApiJeepneyRepository(
        baseUrl: origin,
        cache: cache,
        pollInterval: null,
        client: MockClient((_) async => http.Response('', 503)),
      );
      await expectLater(
        repo.watchJeepneys().first,
        throwsA(isA<ApiLoadException>()),
      );
      expect(repo.state.hasSnapshot, isFalse);
      await repo.dispose();
    }
  });

  test(
    'timeouts abort native HTTP work and duplicate refreshes share one request',
    () async {
      final client = AbortClient();
      final repo = ApiJeepneyRepository(
        baseUrl: origin,
        client: client,
        timeout: const Duration(milliseconds: 10),
        pollInterval: null,
      );
      final errors = <Object>[];
      final subscription = repo.watchJeepneys().listen(
        (_) {},
        onError: errors.add,
      );
      await tick();
      await Future.wait([repo.refresh(), repo.refresh()]);
      await tick();
      expect(client.calls, 1);
      expect(client.active, 0);
      await repo.refresh();
      await tick();
      expect(client.calls, 2);
      expect(client.maxActive, 1);
      expect(repo.state.offline, isTrue);
      expect(errors, hasLength(2));
      await subscription.cancel();
      await repo.dispose();
    },
  );

  test('intermittent API failures preserve selection; recovery replaces cache only with valid responses', () async {
    final cache = MemoryPublicCache();
    var now = DateTime.now().toUtc();
    var status = 200, routesStatus = 200;
    final fleet = ApiJeepneyRepository(
      baseUrl: origin,
      pollInterval: null,
      cache: cache,
      clock: () => now,
      client: MockClient(
        (_) async =>
            status == 200 ? fleetResponse(now) : http.Response('bad', status),
      ),
    );
    final routes = ApiRouteRepository(
      baseUrl: origin,
      cache: cache,
      clock: () => now,
      clientFactory: () => MockClient(
        (_) async => routesStatus == 200
            ? routeResponse()
            : http.Response('bad', routesStatus),
      ),
    );
    final c = JeepneyController(fleet, apiMode: true, routeRepository: routes);
    await tick();
    await c.refresh();
    await tick();
    c.setOrigin(Municipality.boac);
    c.setDestination(Municipality.gasan);
    c.findJeepneys();
    c.selectJeepney(c.journeyVehicles.single);
    final time = c.selectedJeepney!.recordedAt;
    for (var i = 0; i < 2; i++) {
      status = routesStatus = 503;
      now = now.add(const Duration(seconds: 10));
      await c.refresh();
      await tick();
      expect(c.selectedRoute?.id, forward.id);
      expect(c.selectedJeepney?.id, 'CACHE-01');
      expect(c.selectedJeepney?.recordedAt, time);
      expect(c.selectedJeepney?.status, OccupancyStatus.unknown);
    }
    status = 200;
    await c.refresh();
    await tick();
    expect(
      c.offline,
      isTrue,
    ); // A fleet success does not validate a failed route catalog.
    expect(c.selectedJeepney?.status, OccupancyStatus.unknown);
    routesStatus = 200;
    await c.refresh();
    await tick();
    expect(c.offline, isFalse);
    expect(c.selectedJeepney?.isCached, isFalse);
    expect(c.selectedJeepney?.recordedAt, now);
    expect(c.selectedJeepney?.status, OccupancyStatus.available);
    now = now.add(const Duration(hours: 25));
    status = routesStatus = 503;
    await c.refresh();
    await tick();
    expect(c.vehicles, isEmpty);
    expect(c.routes, isEmpty);
    c.dispose();
    await fleet.dispose();
  });

  testWidgets(
    'coordinated retries back off, pause in background, and resume both datasets once',
    (tester) async {
      var fleetCalls = 0, routeCalls = 0;
      var online = true;
      final fleet = ApiJeepneyRepository(
        baseUrl: origin,
        pollInterval: null,
        client: MockClient((_) async {
          fleetCalls++;
          return online
              ? fleetResponse(DateTime.now())
              : http.Response('', 503);
        }),
      );
      final routes = ApiRouteRepository(
        baseUrl: origin,
        clientFactory: () => MockClient((_) async {
          routeCalls++;
          return online ? routeResponse() : http.Response('', 503);
        }),
      );
      final c = JeepneyController(
        fleet,
        apiMode: true,
        routeRepository: routes,
        pollInterval: const Duration(seconds: 10),
      );
      await tester.pump();
      expect(fleetCalls, 1);
      expect(routeCalls, 1);
      online = false;
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(fleetCalls, 2);
      expect(routeCalls, 2);
      await tester.pump(const Duration(seconds: 29));
      expect(fleetCalls, 2);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(fleetCalls, 3);
      await tester.pump(const Duration(seconds: 59));
      expect(fleetCalls, 3);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(fleetCalls, 4);
      c.setActive(false);
      await tester.pump(const Duration(minutes: 5));
      expect(fleetCalls, 4);
      online = true;
      c.setActive(true);
      await tester.pump();
      expect(fleetCalls, 5);
      expect(routeCalls, 5);
      expect(c.offline, isFalse);
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(fleetCalls, 6);
      c.dispose();
      await fleet.dispose();
    },
  );

  test('temporary session check failure keeps verified identity and private memory favorites; logout still clears them', () async {
    var online = true;
    final store = MemorySessionStore();
    final auth = AuthController(
      store: store,
      repository: api((req) async {
        if (!online) return http.Response('', 503);
        return req.url.path.endsWith('/logout')
            ? http.Response('', 204)
            : data(session());
      }),
    );
    await auth.authenticate(
      email: 'test@example.test',
      password: 'test password',
    );
    final repo = FavoriteFixture();
    final favorites = FavoriteController(auth: auth, repository: repo);
    await tick();
    await favorites.toggle(forward);
    final userId = auth.user!.id;
    online = false;
    repo.failure = const AuthFailure('Favorite API unavailable');
    await auth.restore();
    await favorites.refresh();
    expect(auth.user?.id, userId);
    expect(favorites.items, hasLength(1));
    await favorites.toggle(forward);
    expect(favorites.items, hasLength(1));
    expect(favorites.error, isNotNull);
    final restart = AuthController(
      store: store,
      repository: api((_) async => http.Response('', 503)),
    );
    await restart.restore();
    expect(restart.user, isNull);
    restart.dispose();
    await auth.logout();
    expect(auth.user, isNull);
    expect(favorites.items, isEmpty);
    favorites.dispose();
    auth.dispose();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'offline map keeps markers and direction without overflow at text scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        var online = true;
        final now = DateTime.now().toUtc();
        final fleet = ApiJeepneyRepository(
          baseUrl: origin,
          pollInterval: null,
          client: MockClient(
            (_) async => online ? fleetResponse(now) : http.Response('', 503),
          ),
        );
        final routes = ApiRouteRepository(
          baseUrl: origin,
          clientFactory: () => MockClient(
            (_) async => online ? routeResponse() : http.Response('', 503),
          ),
        );
        await tester.pumpWidget(
          JeepLinkApp(
            repository: fleet,
            routeRepository: routes,
            apiMode: true,
            locationService: NoDeviceLocation(),
            tileProviderFactory: MemoryTileProvider.new,
          ),
        );
        await tester.pumpAndSettle();
        await chooseJourney(tester, stayOnMap: true);
        final mapState = tester.state(find.byType(RouteMapScreen));
        online = false;
        await tester.tap(find.byTooltip('Refresh API'));
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(RouteMapScreen)), same(mapState));
        expect(find.byKey(const ValueKey('marker-CACHE-01')), findsOneWidget);
        expect(find.byKey(const ValueKey('marker-CACHE-02')), findsNothing);
        expect(find.text('Offline · Saved information'), findsOneWidget);
        expect(find.text('Boac → Gasan'), findsWidgets);
        expect(find.textContaining('CACHED / UNKNOWN'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('connection-label')));
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            'Jeepney locations and availability may have changed.',
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Close'));
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        online = true;
        await tester.tap(find.byTooltip('Retry connection'));
        await tester.pumpAndSettle();
        expect(find.text('Offline · Saved information'), findsNothing);
        await tab(tester, 'Home');
        expect(find.byKey(const ValueKey('guest-favorites')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
