import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jeeplink/src/app.dart';
import 'package:jeeplink/src/config/data_config.dart';
import 'package:jeeplink/src/data/api_jeepney_repository.dart';
import 'package:jeeplink/src/domain/jeepney.dart';
import 'package:jeeplink/src/presentation/jeepney_controller.dart';

import 'fakes.dart';
import 'widget_test.dart' show chooseJourney;

Map<String, dynamic> record(String id) => {
  'id': id,
  'name': 'Historical DEMO $id',
  'source': 'demo',
  'isDemo': true,
  'isStale': true,
  'connectionStatus': 'DEMO',
  'status': null,
  'lastReportedStatus': 'AVAILABLE',
  'eta': null,
  'timestamp': '2026-01-01T00:00:00.000Z',
  'lastSeenAt': '2026-01-01T00:00:00.000Z',
  'position': {'latitude': 13.449, 'longitude': 121.8374},
};
String payload() => jsonEncode({
  'data': [record('DEMO-01'), record('DEMO-02')],
});
ApiJeepneyRepository repository(
  http.Client client, {
  Duration timeout = const Duration(seconds: 10),
}) => ApiJeepneyRepository(
  baseUrl: Uri.parse('http://127.0.0.1:3000'),
  client: client,
  pollInterval: null,
  timeout: timeout,
);

void main() {
  testWidgets(
    'current API records stay hidden without registered assignments',
    (tester) async {
      var calls = 0;
      final repo = repository(
        MockClient((request) async {
          calls++;
          expect(request.url.path, '/api/jeepneys');
          return http.Response(payload(), 200);
        }),
      );
      await tester.pumpWidget(
        JeepLinkApp(
          locationService: NoDeviceLocation(),
          repository: repo,
          apiMode: true,
          tileProviderFactory: MemoryTileProvider.new,
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('No registered routes available yet.'), findsOneWidget);
      await chooseJourney(tester);
      expect(find.byKey(const ValueKey('vehicle-DEMO-01')), findsNothing);
      expect(find.byKey(const ValueKey('vehicle-DEMO-02')), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Map'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('marker-DEMO-01')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  test('configuration selects platform URL, explicit mode and release TLS', () {
    DataConfig config(
      TargetPlatform platform, {
      String mode = 'api',
      String url = '',
      bool debug = true,
    }) => DataConfig.parse(
      mode: mode,
      url: url,
      platform: platform,
      debug: debug,
    );
    expect(config(TargetPlatform.windows).baseUrl.host, '127.0.0.1');
    expect(config(TargetPlatform.android).baseUrl.host, '10.0.2.2');
    expect(config(TargetPlatform.windows, mode: 'demo').apiMode, isFalse);
    expect(
      () => config(TargetPlatform.windows, debug: false),
      throwsFormatException,
    );
    expect(
      () => config(TargetPlatform.android, url: 'http://example.com'),
      throwsFormatException,
    );
    expect(
      () => config(TargetPlatform.windows, url: 'https://secret@host'),
      throwsFormatException,
    );
    expect(
      () => config(TargetPlatform.windows, mode: 'typo'),
      throwsFormatException,
    );
    expect(
      config(
        TargetPlatform.windows,
        url: 'https://api.example.org',
        debug: false,
      ).apiMode,
      isTrue,
    );
  });

  test(
    'historical status never becomes current availability or fake seats/ETA',
    () {
      final v = parseApiJeepney(record('DEMO-01'));
      expect(v.status, OccupancyStatus.unknown);
      expect(v.statusLabel, 'STALE / UNKNOWN');
      expect(v.hasFreshReport, isFalse);
      expect(v.eta, isNull);
      expect(v.fromApi, isTrue);
      expect(
        parseApiJeepney({
          ...record('D'),
          'isStale': false,
          'status': 'AVAILABLE',
        }).status,
        OccupancyStatus.unknown,
      );
      final hardware = {
        ...record('LAB'),
        'source': 'device',
        'isDemo': false,
        'connectionStatus': 'ONLINE',
        'isStale': false,
        'status': 'FULL',
      };
      expect(parseApiJeepney(hardware).status, OccupancyStatus.full);
      expect(parseApiJeepney(hardware).hasFreshReport, isTrue);
      expect(parseApiJeepney({...hardware, 'eta': 240}).eta, isNull);
      expect(
        parseApiJeepney({...hardware, 'isStale': true}).hasFreshReport,
        isFalse,
      );
      expect(
        parseApiJeepney({...hardware, 'status': null}).status,
        OccupancyStatus.unknown,
      );
      expect(
        parseApiJeepney({...hardware, 'isStale': true}).status,
        OccupancyStatus.unknown,
      );
      expect(
        parseApiJeepney({
          ...hardware,
          'position': null,
          'timestamp': null,
          'lastSeenAt': null,
        }).position,
        isNull,
      );
      expect(
        () => parseApiJeepney({
          ...hardware,
          'position': {'latitude': 91, 'longitude': 0},
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'API sends only passenger GET, refreshes, and never sends authorization',
    () async {
      var requests = 0;
      final repo = repository(
        MockClient((req) async {
          requests++;
          expect(req.method, 'GET');
          expect(req.url.toString(), 'http://127.0.0.1:3000/api/jeepneys');
          expect(req.headers.containsKey('authorization'), isFalse);
          return http.Response(payload(), 200);
        }),
      );
      final queue = StreamIterator(repo.watchJeepneys());
      await queue.moveNext();
      expect(queue.current.length, 2);
      final next = queue.moveNext();
      await repo.refresh();
      await next;
      expect(requests, 2);
      await queue.cancel();
      await repo.dispose();
    },
  );

  test('HTTP errors, malformed payloads and timeout emit errors without demo fallback', () async {
    for (final response in [
      http.Response('unavailable', 503),
      http.Response('not json', 200),
      http.Response('{}', 200),
      http.Response(
        jsonEncode({
          'data': [record('D'), record('D')],
        }),
        200,
      ),
    ]) {
      final repo = repository(MockClient((_) async => response));
      await expectLater(
        repo.watchJeepneys().first,
        throwsA(isA<ApiLoadException>()),
      );
      await repo.dispose();
    }
    final repo = repository(
      MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 5),
    );
    await expectLater(
      repo.watchJeepneys().first,
      throwsA(isA<ApiLoadException>()),
    );
    await repo.dispose();
  });

  test(
    'controller removes old API availability after failed refresh and recovers',
    () async {
      var fail = false;
      final repo = repository(
        MockClient(
          (_) async =>
              fail ? http.Response('', 503) : http.Response(payload(), 200),
        ),
      );
      final controller = JeepneyController(repo, apiMode: true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.vehicles.length, 2);
      expect(controller.filteredVehicles, isEmpty);
      fail = true;
      await controller.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(controller.vehicles, isEmpty);
      expect(controller.error, isNotNull);
      fail = false;
      await controller.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(controller.error, isNull);
      expect(controller.vehicles.length, 2);
      controller.dispose();
      await repo.dispose();
    },
  );

  test(
    'debug Android exception is isolated; main manifest forbids cleartext',
    () {
      final main = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(main, contains('android:usesCleartextTraffic="false"'));
      expect(main, isNot(contains('dev_network_security_config')));
      final debug = File(
        'android/app/src/debug/res/xml/dev_network_security_config.xml',
      ).readAsStringSync();
      expect(debug, contains('<base-config cleartextTrafficPermitted="false"'));
      expect(debug, contains('<domain>10.0.2.2</domain>'));
      expect(
        File('android/app/src/release/res/xml/dev_network_security_config.xml')
            .existsSync(),
        isFalse,
      );
    },
  );

  testWidgets(
    'API mode displays two historical rows, unknown status, unavailable ETA, and retry',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final first = Completer<http.Response>();
      var calls = 0;
      var fail = false;
      final repo = repository(
        MockClient((_) async {
          calls++;
          if (calls == 1) return first.future;
          return fail ? http.Response('', 503) : http.Response(payload(), 200);
        }),
      );
      await tester.pumpWidget(
        JeepLinkApp(
          locationService: NoDeviceLocation(),
          repository: repo,
          routeRepository: TestRouteRepository(),
          apiMode: true,
          tileProviderFactory: MemoryTileProvider.new,
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      first.complete(http.Response(payload(), 200));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vehicle-DEMO-01')), findsNothing);
      await chooseJourney(tester);
      expect(find.text('4 min'), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Jeepneys'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 jeepneys on this route'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('STALE / UNKNOWN'), findsNWidgets(2));
      expect(find.text('ETA unavailable'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('vehicle-DEMO-03')), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('vehicle-DEMO-01')));
      await tester.tap(find.byKey(const ValueKey('vehicle-DEMO-01')));
      await tester.pumpAndSettle();
      expect(find.text('MANUALLY REPORTED STATUS'), findsOneWidget);
      expect(
        find.textContaining('Arrival estimates are not implemented.'),
        findsOneWidget,
      );
      expect(find.textContaining('1 Jan 2026'), findsWidgets);
      await tester.tap(find.byTooltip('Close details'));
      await tester.pumpAndSettle();
      fail = true;
      await tester.tap(find.byTooltip('Refresh API'));
      await tester.pumpAndSettle();
      expect(find.text('Unable to update the fleet'), findsOneWidget);
      expect(find.byKey(const ValueKey('vehicle-DEMO-01')), findsNothing);
      fail = false;
      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('2 jeepneys on this route'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
