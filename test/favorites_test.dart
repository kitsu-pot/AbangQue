import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jeeplink/src/app.dart';
import 'package:jeeplink/src/auth/auth_controller.dart';
import 'package:jeeplink/src/auth/passenger_auth.dart';
import 'package:jeeplink/src/data/demo_jeepney_repository.dart';
import 'package:jeeplink/src/domain/passenger_route.dart';
import 'package:jeeplink/src/favorites/favorite_controller.dart';
import 'package:jeeplink/src/favorites/favorite_repository.dart';
import 'package:jeeplink/src/presentation/jeepney_controller.dart';
import 'package:jeeplink/src/presentation/screens/route_map_screen.dart';

import 'auth_test.dart' show MemorySessionStore, api, data, session, testToken;
import 'fakes.dart';
import 'widget_test.dart' show chooseJourney, tab;

// Test fixtures only: no such registered directions are shipped or seeded.
final forward = PassengerRoute(
  id: '11111111-1111-4111-8111-111111111111',
  origin: Municipality.boac,
  destination: Municipality.gasan,
);
final reverse = PassengerRoute(
  id: '22222222-2222-4222-8222-222222222222',
  origin: Municipality.gasan,
  destination: Municipality.boac,
);

class FavoriteFixture implements FavoriteRepository {
  List<FavoriteRoute> rows = [];
  AuthFailure? failure;
  Completer<void>? pending;
  int reads = 0, saves = 0, removes = 0;
  @override
  Future<List<FavoriteRoute>> list(String token) async {
    reads++;
    if (failure != null) throw failure!;
    return List.of(rows);
  }

  @override
  Future<void> save(String token, String id) async {
    saves++;
    await pending?.future;
    if (failure != null) throw failure!;
    rows = [
      ...rows.where((f) => f.route.id != id),
      FavoriteRoute(
        route: id == forward.id ? forward : reverse,
        available: true,
      ),
    ];
  }

  @override
  Future<void> remove(String token, String id) async {
    removes++;
    if (failure != null) throw failure!;
    rows = rows.where((f) => f.route.id != id).toList();
  }

  @override
  void dispose() {}
}

AuthController account([MemorySessionStore? store]) => AuthController(
  repository: api(
    (req) async => req.url.path.endsWith('/logout')
        ? http.Response('', 204)
        : data(session()),
  ),
  store: store ?? MemorySessionStore(),
);
Future<void> login(AuthController auth) => auth.authenticate(
  email: 'passenger@example.test',
  password: 'test unique password',
);
Future<void> tick() => Future<void>.delayed(Duration.zero);

Future<
  ({AuthController auth, FavoriteFixture favorites, TestRouteRepository routes})
>
start(
  WidgetTester tester, {
  bool signedIn = false,
  double scale = 1,
  FavoriteFixture? favorites,
}) async {
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  final auth = account();
  if (signedIn) {
    await login(auth);
  } else {
    auth.continueAsGuest();
  }
  final repo = favorites ?? FavoriteFixture();
  final routes = TestRouteRepository()
    ..catalog = RouteCatalog(routes: [forward, reverse]);
  await tester.pumpWidget(
    JeepLinkApp(
      repository: DemoJeepneyRepository(),
      routeRepository: routes,
      apiMode: true,
      authController: auth,
      favoriteRepository: repo,
      tileProviderFactory: MemoryTileProvider.new,
      locationService: NoDeviceLocation(),
    ),
  );
  await tester.pumpAndSettle();
  return (auth: auth, favorites: repo, routes: routes);
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('API adapter scopes bearer credentials, rejects redirects, sends no passenger ID', () async {
    final calls = <String>[];
    final repo = ApiFavoriteRepository(
      baseUrl: Uri.parse('http://127.0.0.1:3000'),
      client: MockClient((req) async {
        expect(req.followRedirects, isFalse);
        expect(req.headers['authorization'], 'Bearer $testToken');
        expect(req.body, isEmpty);
        expect(req.url.query, isEmpty);
        calls.add('${req.method} ${req.url.path}');
        return req.method == 'GET'
            ? http.Response(
                jsonEncode({
                  'data': [
                    {
                      'routeId': forward.id,
                      'origin': 'Boac',
                      'destination': 'Gasan',
                      'available': true,
                    },
                    {
                      'routeId': reverse.id,
                      'origin': 'Gasan',
                      'destination': 'Boac',
                      'available': false,
                    },
                  ],
                }),
                200,
              )
            : http.Response('', 204);
      }),
    );
    final result = await repo.list(testToken);
    expect(result.last.available, isFalse);
    expect(result.first.route.direction, 'Boac → Gasan');
    await repo.save(testToken, forward.id);
    await repo.remove(testToken, forward.id);
    expect(calls, [
      'GET /api/favorites',
      'PUT /api/favorites/${forward.id}',
      'DELETE /api/favorites/${forward.id}',
    ]);
    await expectLater(
      repo.save(testToken, 'DEMO-PATH-BOAC-MOGPOG'),
      throwsA(isA<AuthFailure>()),
    );
    repo.dispose();
    expect(
      () =>
          ApiFavoriteRepository(baseUrl: Uri.parse('http://untrusted.example')),
      throwsArgumentError,
    );
  });
  test('adapter fails honestly on expired sessions, unavailable routes and malformed responses', () async {
    for (final status in [401, 409, 503, 302, 200]) {
      final repo = ApiFavoriteRepository(
        baseUrl: Uri.parse('https://example.test'),
        client: MockClient((_) async => http.Response('{}', status)),
      );
      await expectLater(
        repo.list(testToken),
        throwsA(
          isA<AuthFailure>().having(
            (e) => e.unauthorized,
            'invalid session',
            status == 401,
          ),
        ),
      );
      if (status != 200) {
        await expectLater(
          repo.save(testToken, forward.id),
          throwsA(isA<AuthFailure>()),
        );
      }
      repo.dispose();
    }
  });
  test('guests and DEMO cannot save; duplicates wait for server; failures keep honest state', () async {
    final auth = account();
    final repo = FavoriteFixture();
    final c = FavoriteController(auth: auth, repository: repo);
    await c.toggle(forward);
    expect(repo.saves, 0);
    expect(repo.reads, 0);
    await login(auth);
    await tick();
    await c.toggle(
      PassengerRoute(
        id: 'DEMO',
        origin: Municipality.boac,
        destination: Municipality.mogpog,
        isDemo: true,
      ),
    );
    expect(repo.saves, 0);
    repo.pending = Completer<void>();
    final saving = c.toggle(forward);
    await c.toggle(forward);
    expect(repo.saves, 1);
    expect(c.contains(forward.id), isFalse);
    repo.pending!.complete();
    await saving;
    expect(c.contains(forward.id), isTrue);
    repo.failure = const AuthFailure('Connection failed');
    await c.toggle(forward);
    expect(c.contains(forward.id), isTrue);
    expect(c.error, 'Connection failed');
    repo.failure = null;
    await c.toggle(reverse);
    expect(c.items.length, 2);
    await c.toggle(forward);
    expect(c.items.single.route.id, reverse.id);
    c.dispose();
    auth.dispose();
  });
  test(
    'secure session restoration reloads favorites and logout clears them',
    () async {
      final store = MemorySessionStore();
      final repo = FavoriteFixture();
      final first = account(store);
      await login(first);
      final c = FavoriteController(auth: first, repository: repo);
      await tick();
      await c.toggle(forward);
      c.dispose();
      first.dispose();
      final restored = account(store);
      final second = FavoriteController(auth: restored, repository: repo);
      await restored.restore();
      await tick();
      expect(second.contains(forward.id), isTrue);
      await restored.logout();
      expect(second.items, isEmpty);
      await login(restored);
      await tick();
      expect(second.contains(forward.id), isTrue);
      repo.failure = const AuthFailure('Session expired', unauthorized: true);
      await second.refresh();
      expect(restored.user, isNull);
      expect(restored.guest, isTrue);
      expect(second.items, isEmpty);
      expect(store.value, isNull);
      second.dispose();
      restored.dispose();
    },
  );
  test(
    'late mutation response after logout cannot repopulate favorites',
    () async {
      final auth = account();
      await login(auth);
      final repo = FavoriteFixture();
      final c = FavoriteController(auth: auth, repository: repo);
      await tick();
      repo.pending = Completer<void>();
      final saving = c.toggle(forward);
      await auth.logout();
      repo.pending!.complete();
      await saving;
      expect(c.items, isEmpty);
      expect(c.pending, isEmpty);
      c.dispose();
      auth.dispose();
    },
  );
  test('opening rechecks the catalog, rejects unavailable directions and never infers assignments', () async {
    final routes = TestRouteRepository()
      ..catalog = RouteCatalog(routes: [forward, reverse]);
    final c = JeepneyController(TestRepository(), routeRepository: routes);
    expect(await c.openFavorite(reverse.id), isTrue);
    expect(c.origin, Municipality.gasan);
    expect(c.destination, Municipality.boac);
    expect(c.journeyVehicles, isEmpty);
    routes.catalog = RouteCatalog();
    expect(await c.openFavorite(forward.id), isFalse);
    expect(c.selectedRoute, isNull);
    routes.fail = true;
    expect(await c.openFavorite(reverse.id), isFalse);
    expect(c.routesError, isNotNull);
    c.dispose();
  });

  testWidgets(
    'guest heart prompts; Not Now preserves journey and makes no favorite requests',
    (tester) async {
      final app = await start(tester);
      await chooseJourney(tester, stayOnMap: true);
      await tap(tester, find.byKey(const ValueKey('route-favorite')));
      expect(
        find.text(
          'Log in or create an account to save your favorite routes and access them anytime.',
        ),
        findsOneWidget,
      );
      await tap(tester, find.text('Not Now'));
      expect(find.byType(RouteMapScreen), findsOneWidget);
      expect(find.text('Boac → Gasan'), findsWidgets);
      expect(app.favorites.reads, 0);
      expect(app.favorites.saves, 0);
      await tab(tester, 'Home');
      await tap(tester, find.byKey(const ValueKey('guest-favorites')));
      expect(find.text('Log In'), findsOneWidget);
      await tap(tester, find.text('Not Now'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'map refresh recovers a failed favorites load before enabling save',
    (tester) async {
      final repo = FavoriteFixture()
        ..failure = const AuthFailure('Favorites unavailable');
      await start(tester, signedIn: true, favorites: repo);
      await chooseJourney(tester, stayOnMap: true);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('route-favorite')))
            .onPressed,
        isNull,
      );
      repo.failure = null;
      await tap(tester, find.byTooltip('Refresh API'));
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('route-favorite')))
            .onPressed,
        isNotNull,
      );
      await tap(tester, find.byKey(const ValueKey('route-favorite')));
      expect(repo.saves, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final register in [false, true]) {
    testWidgets(
      '${register ? 'registration' : 'login'} returns to selected route, without silently saving',
      (tester) async {
        final app = await start(tester);
        await chooseJourney(tester, stayOnMap: true);
        await tap(tester, find.byKey(const ValueKey('route-favorite')));
        await tap(tester, find.text(register ? 'Create Account' : 'Log In'));
        if (register) {
          await tester.enterText(
            find.byKey(const ValueKey('auth-name')),
            'Test Passenger',
          );
        }
        await tester.enterText(
          find.byKey(const ValueKey('auth-email')),
          'passenger@example.test',
        );
        await tester.enterText(
          find.byKey(const ValueKey('auth-password')),
          'test unique password',
        );
        if (register) {
          await tester.enterText(
            find.byKey(const ValueKey('auth-confirm')),
            'test unique password',
          );
        }
        await tap(tester, find.text(register ? 'Create account' : 'Sign in'));
        expect(app.auth.user, isNotNull);
        expect(find.byType(RouteMapScreen), findsOneWidget);
        expect(find.text('Boac → Gasan'), findsWidgets);
        expect(app.favorites.saves, 0);
        await tap(tester, find.byKey(const ValueKey('route-favorite')));
        expect(app.favorites.saves, 1);
        expect(find.byTooltip('Remove favorite route'), findsOneWidget);
        await tab(tester, 'Home');
        await tap(tester, find.byKey(ValueKey('open-favorite-${forward.id}')));
        expect(find.byType(RouteMapScreen), findsOneWidget);
        await tap(tester, find.byKey(const ValueKey('route-favorite')));
        expect(app.favorites.removes, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'loading failure can retry; inactive favorites cannot open; 320px large text fits',
    (tester) async {
      final repo = FavoriteFixture()
        ..failure = const AuthFailure('Network unavailable');
      await start(tester, signedIn: true, scale: 2, favorites: repo);
      expect(find.text('Network unavailable'), findsOneWidget);
      repo.failure = null;
      repo.rows = [
        FavoriteRoute(route: reverse, available: false),
        FavoriteRoute(route: forward, available: true),
      ];
      await tap(tester, find.text('Retry favorites'));
      expect(find.text('Route unavailable'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(ValueKey('open-favorite-${reverse.id}')),
            )
            .onPressed,
        isNull,
      );
      await tap(tester, find.byKey(ValueKey('remove-favorite-${reverse.id}')));
      expect(repo.rows.length, 1);
      await tap(tester, find.byKey(ValueKey('open-favorite-${forward.id}')));
      expect(find.byType(RouteMapScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
