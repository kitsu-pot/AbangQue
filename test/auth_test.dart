import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jeeplink/src/app.dart';
import 'package:jeeplink/src/auth/auth_controller.dart';
import 'package:jeeplink/src/auth/auth_screens.dart';
import 'package:jeeplink/src/auth/passenger_auth.dart';
import 'package:jeeplink/src/auth/session_store.dart';
import 'package:jeeplink/src/data/demo_jeepney_repository.dart';

import 'fakes.dart';

// HTTP fixtures only; production always calls the real API.
final testToken = 'aqp_${'t' * 43}';
Map<String, Object> profile([String name = 'Test Passenger']) => {
  'id': 'test-passenger',
  'fullName': name,
  'email': 'passenger@example.test',
  'role': 'PASSENGER',
};
Map<String, Object> session({bool withToken = true}) => {
  'user': profile(),
  'expiresAt': DateTime.now()
      .toUtc()
      .add(const Duration(days: 1))
      .toIso8601String(),
  if (withToken) 'token': testToken,
};
http.Response data(Map<String, Object> value, [int status = 200]) =>
    http.Response(jsonEncode({'data': value}), status);

class MemorySessionStore implements SessionStore {
  StoredSession? value;
  bool failWrite = false;
  @override
  Future<StoredSession?> read() async => value;
  @override
  Future<void> write(StoredSession session) async {
    if (failWrite) throw StateError('Secure storage failure');
    value = session;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

ApiPassengerAuthRepository api(
  Future<http.Response> Function(http.Request) handler, {
  Duration timeout = const Duration(seconds: 10),
}) => ApiPassengerAuthRepository(
  baseUrl: Uri.parse('http://127.0.0.1:3000'),
  client: MockClient(handler),
  timeout: timeout,
);

void main() {
  test('auth adapter uses scoped bearer tokens, refuses redirects and exposes only passenger profiles', () async {
    final paths = <String>[];
    final repo = api((req) async {
      paths.add(req.url.path);
      expect(req.followRedirects, isFalse);
      if (req.url.path.endsWith('register') || req.url.path.endsWith('login')) {
        expect(req.headers.containsKey('authorization'), isFalse);
        expect(jsonDecode(req.body), isNot(contains('role')));
        return data(session(), req.url.path.endsWith('register') ? 201 : 200);
      }
      expect(req.headers['authorization'], 'Bearer $testToken');
      if (req.url.path.endsWith('logout')) return http.Response('', 204);
      if (req.method == 'PATCH') return data({'user': profile('Edited')});
      return data(session(withToken: false));
    });
    expect(
      (await repo.register(
        ' Test ',
        ' passenger@example.test ',
        'a long unique passphrase',
      )).user.fullName,
      'Test Passenger',
    );
    expect(
      (await repo.login(
        'passenger@example.test',
        'a long unique passphrase',
      )).token,
      testToken,
    );
    expect(
      (await repo.restore(testToken)).user.email,
      'passenger@example.test',
    );
    expect((await repo.updateName(testToken, 'Edited')).fullName, 'Edited');
    await repo.logout(testToken);
    expect(paths, everyElement(startsWith('/api/auth/')));
    repo.dispose();
  });
  test('bad credentials, rate limits, redirects, invalid role and timeout fail without fake login', () async {
    for (final response in [
      http.Response('{}', 401),
      http.Response('{}', 429),
      http.Response('', 302, headers: {'location': 'https://elsewhere.test'}),
      data({
        ...session(),
        'user': {...profile(), 'role': 'ADMIN'},
      }),
      http.Response('invalid', 200),
    ]) {
      final repo = api((_) async => response);
      await expectLater(
        repo.login('x@example.test', 'secret'),
        throwsA(isA<AuthFailure>()),
      );
      repo.dispose();
    }
    final repo = api(
      (_) => Completer<http.Response>().future,
      timeout: const Duration(milliseconds: 5),
    );
    await expectLater(
      repo.login('x@example.test', 'secret'),
      throwsA(isA<AuthFailure>()),
    );
    repo.dispose();
    expect(
      () => ApiPassengerAuthRepository(
        baseUrl: Uri.parse('http://remote.example.test'),
      ),
      throwsArgumentError,
    );
  });
  test('login persists, new controller restores, profile saves and logout removes credentials', () async {
    final store = MemorySessionStore();
    var revoked = false;
    Future<http.Response> handler(http.Request req) async {
      if (req.url.path.endsWith('logout')) {
        revoked = true;
        return http.Response('', 204);
      }
      if (req.method == 'PATCH') return data({'user': profile('Updated')});
      return data(session(withToken: req.method == 'POST'));
    }

    final first = AuthController(repository: api(handler), store: store);
    await first.authenticate(
      email: 'passenger@example.test',
      password: 'a long unique passphrase',
    );
    expect(first.user, isNotNull);
    expect(store.value!.token, testToken);
    first.dispose();
    final restored = AuthController(repository: api(handler), store: store);
    await restored.restore();
    expect(restored.user!.fullName, 'Test Passenger');
    await restored.updateName('Updated');
    expect(restored.user!.fullName, 'Updated');
    await restored.logout();
    expect(revoked, isTrue);
    expect(store.value, isNull);
    expect(restored.user, isNull);
    restored.dispose();
  });
  test(
    'expired, revoked and unverifiable sessions never authenticate locally',
    () async {
      final store = MemorySessionStore()
        ..value = StoredSession(
          testToken,
          DateTime.now().add(const Duration(hours: 1)),
        );
      var status = 503;
      final c = AuthController(
        repository: api((_) async => http.Response('{}', status)),
        store: store,
      );
      await c.restore();
      expect(c.user, isNull);
      expect(store.value, isNotNull);
      c.continueAsGuest();
      expect(c.entered, isTrue);
      status = 401;
      await c.restore();
      expect(store.value, isNull);
      store.value = StoredSession(
        testToken,
        DateTime.now().subtract(const Duration(seconds: 1)),
      );
      await c.restore();
      expect(store.value, isNull);
      expect(c.user, isNull);
      c.dispose();
    },
  );
  test('offline logout leaves durable revocation marker and cannot restore identity', () async {
    final store = MemorySessionStore();
    var online = true;
    final calls = <String>[];
    Future<http.Response> handler(http.Request req) async {
      calls.add(req.url.path);
      if (!online) return http.Response('', 503);
      return req.url.path.endsWith('logout')
          ? http.Response('', 204)
          : data(session());
    }

    final c = AuthController(repository: api(handler), store: store);
    await c.authenticate(
      email: 'x@example.test',
      password: 'a long unique passphrase',
    );
    online = false;
    await c.logout();
    expect(c.user, isNull);
    expect(store.value!.pendingLogout, isTrue);
    c.dispose();
    calls.clear();
    final next = AuthController(repository: api(handler), store: store);
    await next.restore();
    expect(next.user, isNull);
    expect(calls, ['/api/auth/logout']);
    online = true;
    await next.restore();
    expect(store.value, isNull);
    expect(next.user, isNull);
    next.dispose();
  });
  test(
    'secure storage failure revokes new session instead of entering account',
    () async {
      final store = MemorySessionStore()..failWrite = true;
      var revoked = false;
      final c = AuthController(
        repository: api((req) async {
          if (req.url.path.endsWith('logout')) {
            revoked = true;
            return http.Response('', 204);
          }
          return data(session());
        }),
        store: store,
      );
      await c.authenticate(
        email: 'x@example.test',
        password: 'a long unique passphrase',
      );
      expect(c.user, isNull);
      expect(c.error, contains('Secure session storage'));
      expect(revoked, isTrue);
      c.dispose();
    },
  );
  test(
    'device backup exclusions and strict release network policy remain present',
    () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:usesCleartextTraffic="false"'));
      final backup = File(
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      ).readAsStringSync();
      expect(backup, contains('<device-transfer>'));
      expect(backup, contains('domain="sharedpref" path="."'));
      expect(nameError('  '), isNotNull);
      expect(emailError('bad'), isNotNull);
      expect(passwordError('short'), isNotNull);
      expect(passwordError('a long unique passphrase'), isNull);
    },
  );
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'login/register validation, visibility and guest journey at 320px/$scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          tester.view.resetViewInsets();
        });
        var calls = 0;
        final c = AuthController(
          repository: api((_) async {
            calls++;
            return data(session());
          }),
          store: MemorySessionStore(),
        );
        await tester.pumpWidget(
          JeepLinkApp(
            locationService: NoDeviceLocation(),
            repository: DemoJeepneyRepository(),
            authController: c,
            tileProviderFactory: MemoryTileProvider.new,
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('New to AbangQue? Register'));
        await tester.tap(find.text('New to AbangQue? Register'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('auth-name')),
          'Passenger',
        );
        await tester.enterText(
          find.byKey(const ValueKey('auth-email')),
          'invalid',
        );
        await tester.enterText(
          find.byKey(const ValueKey('auth-password')),
          'short',
        );
        await tester.enterText(
          find.byKey(const ValueKey('auth-confirm')),
          'different',
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.ensureVisible(find.byTooltip('Show password'));
        await tester.tap(find.byTooltip('Show password'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: find.byKey(const ValueKey('auth-password')),
                  matching: find.byType(TextField),
                ),
              )
              .obscureText,
          isFalse,
        );
        await tester.ensureVisible(find.text('Create account'));
        await tester.tap(find.text('Create account'));
        await tester.pumpAndSettle();
        expect(find.text('Passwords do not match.'), findsOneWidget);
        expect(calls, 0);
        tester.view.resetViewInsets();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Continue as Guest'));
        await tester.tap(find.text('Continue as Guest'));
        await tester.pumpAndSettle();
        expect(find.text('Where are you headed?'), findsOneWidget);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(calls, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'registration enters profile, saves name and signs out through API',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final store = MemorySessionStore();
      final calls = <String>[];
      final c = AuthController(
        repository: api((req) async {
          calls.add('${req.method} ${req.url.path}');
          if (req.url.path.endsWith('logout')) return http.Response('', 204);
          if (req.method == 'PATCH') {
            return data({'user': profile('Edited Passenger')});
          }
          return data(
            session(withToken: req.method == 'POST'),
            req.url.path.endsWith('register') ? 201 : 200,
          );
        }),
        store: store,
      );
      await tester.pumpWidget(
        JeepLinkApp(
          locationService: NoDeviceLocation(),
          repository: DemoJeepneyRepository(),
          authController: c,
          tileProviderFactory: MemoryTileProvider.new,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('New to AbangQue? Register'));
      await tester.tap(find.text('New to AbangQue? Register'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('auth-name')),
        'Test Passenger',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-email')),
        'passenger@example.test',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        'a long unique passphrase',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-confirm')),
        'a long unique passphrase',
      );
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(find.byTooltip('Passenger profile'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('profile-name')),
        'Edited Passenger',
      );
      await tester.ensureVisible(find.text('Save profile'));
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();
      expect(find.text('Profile updated.'), findsOneWidget);
      await tester.ensureVisible(find.text('Sign out'));
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome aboard'), findsOneWidget);
      expect(store.value, isNull);
      expect(
        calls,
        containsAll([
          'POST /api/auth/register',
          'GET /api/auth/me',
          'PATCH /api/auth/me',
          'POST /api/auth/logout',
        ]),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
