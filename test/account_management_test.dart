import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jeeplink/src/auth/auth_controller.dart';
import 'package:jeeplink/src/auth/auth_screens.dart';
import 'package:jeeplink/src/auth/account_management.dart';
import 'package:jeeplink/src/auth/passenger_auth.dart';
import 'package:jeeplink/src/favorites/favorite_controller.dart';
import 'package:jeeplink/src/favorites/favorite_repository.dart';
import 'package:jeeplink/src/theme.dart';

import 'auth_test.dart'
    show api, data, profile, session, testToken, MemorySessionStore;
import 'favorites_test.dart' show FavoriteFixture, forward;

const oldPassword = 'a unique old test passphrase';
const newPassword = 'a unique new test passphrase';
Future<void> login(AuthController auth) =>
    auth.authenticate(email: 'passenger@example.test', password: oldPassword);
Future<void> tick() => Future<void>.delayed(Duration.zero);

class UnclearableStore extends MemorySessionStore {
  @override
  Future<void> clear() async => throw StateError('Storage unavailable');
}

void main() {
  test('account adapter scopes mutations to bearer identity and sends only supported fields', () async {
    final requests = <http.Request>[];
    final repo = api((req) async {
      requests.add(req);
      expect(req.followRedirects, isFalse);
      expect(req.headers['authorization'], 'Bearer $testToken');
      expect(req.url.query, isEmpty);
      return req.method == 'PATCH'
          ? data({'user': profile('Edited')})
          : http.Response('', 204);
    });
    expect((await repo.updateName(testToken, ' Edited ')).fullName, 'Edited');
    await repo.changePassword(testToken, oldPassword, newPassword, newPassword);
    await repo.deleteAccount(testToken, oldPassword);
    expect(requests.map((r) => '${r.method} ${r.url.path}'), [
      'PATCH /api/auth/me',
      'POST /api/auth/me/password',
      'DELETE /api/auth/me',
    ]);
    expect(jsonDecode(requests[1].body), {
      'currentPassword': oldPassword,
      'newPassword': newPassword,
      'confirmPassword': newPassword,
    });
    expect(jsonDecode(requests[2].body), {'currentPassword': oldPassword});
    repo.dispose();
  });

  test('wrong current password, offline writes, malformed success and rate limit keep verified identity without queuing', () async {
    var status = 403, mutationCalls = 0;
    final store = MemorySessionStore();
    final auth = AuthController(
      store: store,
      repository: api((req) async {
        if (req.url.path.endsWith('/login')) return data(session());
        mutationCalls++;
        return http.Response(
          jsonEncode({'error': 'CURRENT_PASSWORD_INCORRECT'}),
          status,
        );
      }),
    );
    await login(auth);
    for (final code in [403, 503, 429, 200]) {
      status = code;
      expect(
        await auth.changePassword(oldPassword, newPassword, newPassword),
        isFalse,
      );
      expect(auth.error, isNotNull);
      expect(auth.user?.id, 'test-passenger');
      expect(store.value?.token, testToken);
    }
    status = 503;
    expect(await auth.deleteAccount(oldPassword), isFalse);
    expect(await auth.updateName('Edited'), isFalse);
    await tick();
    expect(mutationCalls, 6);
    status = 401;
    expect(
      await auth.changePassword(oldPassword, newPassword, newPassword),
      isFalse,
    );
    expect(auth.user, isNull);
    expect(auth.guest, isTrue);
    expect(store.value, isNull);
    auth.dispose();
  });

  test('timeout is unconfirmed, never automatic success or retry', () async {
    var calls = 0;
    final pending = Completer<http.Response>();
    final repo = api((_) {
      calls++;
      return pending.future;
    }, timeout: const Duration(milliseconds: 10));
    await expectLater(
      repo.deleteAccount(testToken, oldPassword),
      throwsA(
        isA<AuthFailure>().having(
          (e) => e.message,
          'message',
          contains('could not be confirmed'),
        ),
      ),
    );
    pending.complete(http.Response('', 204));
    await tick();
    expect(calls, 1);
    repo.dispose();
  });

  for (final failClear in [false, true]) {
    test(
      'confirmed deletion clears private identity/favorites; secure-store failure=$failClear',
      () async {
        final store = failClear ? UnclearableStore() : MemorySessionStore();
        var accountId = 'test-passenger';
        final auth = AuthController(
          store: store,
          repository: api((req) async {
            if (req.method == 'DELETE') return http.Response('', 204);
            return data({
              ...session(),
              'user': {...profile(), 'id': accountId},
            });
          }),
        );
        final fixture = FavoriteFixture()
          ..rows = [FavoriteRoute(route: forward, available: true)];
        final favorites = FavoriteController(auth: auth, repository: fixture);
        await login(auth);
        await tick();
        expect(favorites.items, hasLength(1));
        expect(await auth.deleteAccount(oldPassword), isTrue);
        expect(auth.user, isNull);
        expect(auth.guest, isTrue);
        expect(favorites.items, isEmpty);
        if (failClear) {
          expect(auth.error, contains('Account deleted.'));
        } else {
          expect(store.value, isNull);
        }
        fixture.rows = [];
        accountId = 'different-passenger';
        await login(auth);
        await tick();
        expect(auth.user?.id, 'different-passenger');
        expect(favorites.items, isEmpty);
        favorites.dispose();
        auth.dispose();
      },
    );
  }

  test('logout clears private memory and attempts server revocation even if secure marker write fails', () async {
    final store = MemorySessionStore();
    var revocations = 0;
    final auth = AuthController(
      store: store,
      repository: api((req) async {
        if (req.url.path.endsWith('/logout')) {
          revocations++;
          return http.Response('', 204);
        }
        return data(session());
      }),
    );
    final fixture = FavoriteFixture()
      ..rows = [FavoriteRoute(route: forward, available: true)];
    final favorites = FavoriteController(auth: auth, repository: fixture);
    await login(auth);
    await tick();
    store.failWrite = true;
    await auth.logout();
    expect(revocations, 1);
    expect(auth.user, isNull);
    expect(favorites.items, isEmpty);
    expect(store.value, isNull);
    favorites.dispose();
    auth.dispose();
  });

  test('late profile response cannot restore an account cleared by session revocation', () async {
    final pending = Completer<http.Response>();
    final auth = AuthController(
      store: MemorySessionStore(),
      repository: api((req) async {
        if (req.method == 'PATCH') return pending.future;
        return data(session());
      }),
    );
    await login(auth);
    final save = auth.updateName('Edited');
    await tick();
    await expectLater(
      auth.authenticated<void>(
        (_) async => throw const AuthFailure('Expired', unauthorized: true),
      ),
      throwsA(isA<AuthFailure>()),
    );
    pending.complete(data({'user': profile('Edited')}));
    expect(await save, isFalse);
    expect(auth.user, isNull);
    auth.dispose();
  });

  test('confirmed deletion remains successful when another request detects its revoked session first', () async {
    final pending = Completer<http.Response>();
    final auth = AuthController(
      store: MemorySessionStore(),
      repository: api((req) async {
        if (req.method == 'DELETE') return pending.future;
        if (req.method == 'PATCH') {
          return data({
            'user': {...profile(), 'id': 'wrong-account'},
          });
        }
        return data(session());
      }),
    );
    await login(auth);
    expect(await auth.updateName('Edited'), isFalse);
    expect(auth.user?.id, 'test-passenger');
    expect(auth.error, contains('did not match'));
    final removal = auth.deleteAccount(oldPassword);
    await tick();
    await expectLater(
      auth.authenticated<void>(
        (_) async => throw const AuthFailure('Expired', unauthorized: true),
      ),
      throwsA(isA<AuthFailure>()),
    );
    pending.complete(http.Response('', 204));
    expect(await removal, isTrue);
    expect(auth.user, isNull);
    expect(auth.guest, isTrue);
    auth.dispose();
  });

  test(
    'successful password change retains current session expiry and identity',
    () async {
      final store = MemorySessionStore();
      final auth = AuthController(
        store: store,
        repository: api(
          (req) async => req.url.path.endsWith('/password')
              ? http.Response('', 204)
              : data(session()),
        ),
      );
      await login(auth);
      final before = store.value;
      expect(
        await auth.changePassword(oldPassword, newPassword, newPassword),
        isTrue,
      );
      expect(identical(store.value, before), isTrue);
      expect(auth.user?.id, 'test-passenger');
      auth.dispose();
    },
  );

  Future<void> screen(
    WidgetTester tester,
    AuthController auth,
    double scale,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: JeepLinkColors.theme,
        home: PassengerProfileScreen(controller: auth),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'offline sign-out leaves its pending-revocation message visible on guest Profile',
    (tester) async {
      final auth = AuthController(
        store: MemorySessionStore(),
        repository: api(
          (req) async => req.url.path.endsWith('/logout')
              ? http.Response('', 503)
              : data(session()),
        ),
      );
      await login(auth);
      await screen(tester, auth, 1);
      await tap(tester, find.text('Sign out'));
      expect(auth.user, isNull);
      expect(find.text('Travelling as a guest'), findsOneWidget);
      expect(find.textContaining('Server logout is pending'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'guest profile and truthful privacy stay readable at 320px/$scale',
      (tester) async {
        final auth = AuthController(
          store: MemorySessionStore(),
          repository: api((_) async => data(session())),
        )..continueAsGuest();
        await screen(tester, auth, scale);
        expect(find.text('Travelling as a guest'), findsOneWidget);
        expect(find.text('Log In'), findsOneWidget);
        expect(find.text('Create Account'), findsOneWidget);
        expect(find.text('Delete account'), findsNothing);
        expect(find.text('Change password'), findsNothing);
        await tap(tester, find.text('Log In'));
        expect(find.text('Welcome aboard'), findsOneWidget);
        await tap(tester, find.text('Continue as Guest'));
        await tap(tester, find.text('Create Account'));
        expect(find.text('Create your account'), findsOneWidget);
        await tap(tester, find.text('Continue as Guest'));
        await tap(tester, find.text('Privacy & Data'));
        expect(find.byType(PrivacyDataScreen), findsOneWidget);
        expect(
          find.textContaining('not a formal privacy policy'),
          findsOneWidget,
        );
        await tester.drag(
          find.byType(SingleChildScrollView).last,
          const Offset(0, -1800),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        auth.dispose();
      },
    );

    testWidgets(
      'password form validates policy/confirmation and confirms real API result at $scale',
      (tester) async {
        var changes = 0;
        final auth = AuthController(
          store: MemorySessionStore(),
          repository: api((req) async {
            if (req.url.path.endsWith('/password')) {
              changes++;
              return http.Response('', 204);
            }
            return data(session());
          }),
        );
        await login(auth);
        await screen(tester, auth, scale);
        await tap(tester, find.text('Change password'));
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('account-current-password')),
          oldPassword,
        );
        await tester.enterText(
          find.byKey(const ValueKey('account-new-password')),
          'short',
        );
        await tester.enterText(
          find.byKey(const ValueKey('account-confirm-password')),
          'different',
        );
        await tap(tester, find.byKey(const ValueKey('submit-account-change')));
        expect(changes, 0);
        expect(find.text('Passwords do not match.'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('account-new-password')),
          newPassword,
        );
        await tester.enterText(
          find.byKey(const ValueKey('account-confirm-password')),
          newPassword,
        );
        await tap(tester, find.byTooltip('Show new password'));
        expect(
          tester.widget<TextFormField>(
            find.byKey(const ValueKey('account-new-password')),
          ),
          isNotNull,
        );
        await tap(tester, find.byKey(const ValueKey('submit-account-change')));
        expect(changes, 1);
        expect(find.byType(AccountSecurityDialog), findsNothing);
        expect(find.textContaining('Password changed.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        auth.dispose();
      },
    );

    testWidgets(
      'deletion requires deliberate confirmation/password and cancel never sends at $scale',
      (tester) async {
        var deletes = 0, response = 403;
        final auth = AuthController(
          store: MemorySessionStore(),
          repository: api((req) async {
            if (req.method == 'DELETE') {
              deletes++;
              return http.Response(
                response == 204 ? '' : '{"error":"CURRENT_PASSWORD_INCORRECT"}',
                response,
              );
            }
            return data(session());
          }),
        );
        await login(auth);
        await screen(tester, auth, scale);
        await tap(tester, find.byKey(const ValueKey('delete-account')));
        expect(deletes, 0);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('submit-account-change')),
              )
              .onPressed,
          isNull,
        );
        await tap(tester, find.text('Cancel'));
        expect(deletes, 0);
        await tap(tester, find.byKey(const ValueKey('delete-account')));
        await tap(
          tester,
          find.byKey(const ValueKey('confirm-account-deletion')),
        );
        await tap(tester, find.byKey(const ValueKey('submit-account-change')));
        expect(deletes, 0);
        await tester.enterText(
          find.byKey(const ValueKey('account-current-password')),
          'wrong',
        );
        await tap(tester, find.byKey(const ValueKey('submit-account-change')));
        expect(deletes, 1);
        expect(auth.user, isNotNull);
        expect(
          find.textContaining('Current password is incorrect.'),
          findsWidgets,
        );
        response = 204;
        await tester.enterText(
          find.byKey(const ValueKey('account-current-password')),
          oldPassword,
        );
        await tap(tester, find.byKey(const ValueKey('submit-account-change')));
        expect(deletes, 2);
        expect(auth.user, isNull);
        expect(find.text('Travelling as a guest'), findsOneWidget);
        expect(
          find.textContaining(
            'Your account and saved favorites have been deleted.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        auth.dispose();
      },
    );
  }
}
