import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeeplink/src/app.dart';
import 'package:jeeplink/src/auth/auth_controller.dart';
import 'package:jeeplink/src/data/demo_jeepney_repository.dart';
import 'package:jeeplink/src/domain/jeepney.dart';
import 'package:jeeplink/src/location/device_location_service.dart';
import 'package:jeeplink/src/location/waiting_location.dart';
import 'package:jeeplink/src/location/waiting_location_panel.dart';
import 'package:jeeplink/src/location/waiting_location_picker.dart';

import 'auth_test.dart' show MemorySessionStore, api, data, session;
import 'fakes.dart';
import 'widget_test.dart' show chooseJourney, tab;

class FakeDeviceLocation implements DeviceLocationService {
  int calls = 0, cancels = 0, settings = 0;
  LocationProblem? failure;
  Completer<DeviceFix>? pending;
  double accuracy = 15;
  @override
  Future<DeviceFix> locate() async {
    calls++;
    if (failure != null) throw LocationFailure(failure!);
    return pending?.future ??
        DeviceFix(
          point: const GeoPoint(13.449, 121.842),
          measuredAt: DateTime.now().toUtc(),
          accuracyMeters: accuracy,
        );
  }

  @override
  void cancel() {
    cancels++;
  }

  @override
  Future<bool> openAppSettings() async {
    settings++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    settings++;
    return true;
  }
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> tapMap(WidgetTester tester, {Offset offset = Offset.zero}) async {
  final map = find.byType(FlutterMap);
  await tester.ensureVisible(map);
  await tester.tapAt(tester.getCenter(map) + offset);
  // flutter_map distinguishes single taps from double-tap zoom.
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

Future<void> startWaitingApp(
  WidgetTester tester,
  FakeDeviceLocation service, {
  double scale = 1,
  bool guest = false,
  AuthController? auth,
}) async {
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  if (const bool.fromEnvironment('CAPTURE_WAITING')) {
    const fonts = String.fromEnvironment('DESIGN_FONT_DIR');
    await tester.runAsync(() async {
      for (final font in {
        'Roboto': 'Roboto-Regular.ttf',
        'MaterialIcons': 'MaterialIcons-Regular.otf',
      }.entries) {
        await (FontLoader(font.key)..addFont(
              File('$fonts/${font.value}')
                  .readAsBytes()
                  .then(ByteData.sublistView),
            ))
            .load();
      }
    });
  }
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('waiting-preview'),
      child: JeepLinkApp(
        repository: DemoJeepneyRepository(),
        routeRepository: TestRouteRepository(),
        locationService: service,
        authController:
            auth ??
            (guest
                ? AuthController(repository: null, store: MemorySessionStore())
                : null),
        tileProviderFactory: MemoryTileProvider.new,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (guest) await tapText(tester, 'Continue as Guest');
  expect(service.calls, 0);
}

Future<void> snapshotWaiting(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_WAITING')) return;
  final render = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('waiting-preview')),
  );
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = await Directory('build/design-preview')
        .create(recursive: true);
    await File('${directory.path}/waiting-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

WaitingLocation? selected(WidgetTester tester) => tester
    .widget<WaitingLocationPanel>(find.byType(WaitingLocationPanel))
    .selected;

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'guest manual waiting selection, cancel, change and clear at scale $scale',
      (tester) async {
        final service = FakeDeviceLocation();
        await startWaitingApp(tester, service, scale: scale, guest: true);
        await chooseJourney(tester);
        await tapText(tester, 'Choose on Map');
        expect(service.calls, 0);
        expect(
          find.byKey(const ValueKey('passenger-waiting-marker')),
          findsNothing,
        );
        await tapMap(tester);
        await snapshotWaiting(tester, 'picker-$scale');
        expect(
          find.byKey(const ValueKey('passenger-waiting-marker')),
          findsOneWidget,
        );
        expect(
          find.text('Map-selected point · GPS accuracy does not apply'),
          findsOneWidget,
        );
        await tapText(tester, 'Confirm Location');
        final first = selected(tester)!;
        await tester.pump(const Duration(seconds: 5));
        await tester.ensureVisible(find.text('Waiting location selected'));
        await tester.pumpAndSettle();
        await snapshotWaiting(tester, 'confirmed-$scale');
        expect(first.source, WaitingLocationSource.manualMap);
        expect(find.text('Boac → Gasan'), findsWidgets);
        await tab(tester, 'Map');
        expect(
          find.byKey(const ValueKey('passenger-waiting-marker')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('marker-DEMO-01')), findsOneWidget);
        await tapText(tester, 'Change Location');
        await tapMap(tester, offset: const Offset(-35, 25));
        await tapText(tester, 'Cancel');
        expect(selected(tester), same(first));
        await tapText(tester, 'Change Location');
        await tapMap(tester, offset: const Offset(-35, 25));
        await tapText(tester, 'Confirm Location');
        expect(selected(tester)!.point.latitude, isNot(first.point.latitude));
        await tapText(tester, 'Clear Location');
        expect(selected(tester), isNull);
        expect(
          find.byKey(const ValueKey('passenger-waiting-marker')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('marker-DEMO-01')), findsOneWidget);
        expect(service.calls, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'account changes clear waiting state without storing or uploading it',
    (tester) async {
      final store = MemorySessionStore();
      final payloads = <Object>[];
      final auth = AuthController(
        repository: api((request) async {
          if (request.body.isNotEmpty) payloads.add(jsonDecode(request.body));
          return request.url.path.endsWith('logout')
              ? data({}, 204)
              : data(session());
        }),
        store: store,
      )..continueAsGuest();
      await startWaitingApp(tester, FakeDeviceLocation(), auth: auth);
      await tapText(tester, 'Choose on Map');
      await tapMap(tester);
      await tapText(tester, 'Confirm Location');
      expect(selected(tester), isNotNull);
      expect(store.value, isNull);
      expect(payloads, isEmpty);
      await auth.authenticate(
        email: 'passenger@example.test',
        password: 'a long unique passphrase',
      );
      await tester.pumpAndSettle();
      expect(auth.user, isNotNull);
      expect(selected(tester), isNull);
      expect(payloads.single, {
        'email': 'passenger@example.test',
        'password': 'a long unique passphrase',
      });
      await tapText(tester, 'Choose on Map');
      await tapMap(tester);
      await tapText(tester, 'Confirm Location');
      expect(selected(tester), isNotNull);
      await auth.logout();
      await tester.pumpAndSettle();
      expect(auth.user, isNull);
      await tapText(tester, 'Continue as Guest');
      expect(selected(tester), isNull);
      expect(store.value, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'device location requires explicit confirmation and preserves low accuracy warning',
    (tester) async {
      final service = FakeDeviceLocation()..accuracy = 650;
      await startWaitingApp(tester, service);
      await tapText(tester, 'Use My Location');
      expect(service.calls, 1);
      expect(find.textContaining('Low accuracy'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('passenger-waiting-marker')),
        findsOneWidget,
      );
      await tapText(tester, 'Cancel');
      expect(selected(tester), isNull);
      await tapText(tester, 'Use My Location');
      await tapText(tester, 'Confirm Location');
      expect(selected(tester)!.accuracyMeters, 650);
      expect(selected(tester)!.source, WaitingLocationSource.deviceGps);
      await tab(tester, 'Guide');
      await tab(tester, 'Home');
      expect(selected(tester), isNotNull);
      expect(service.calls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  for (final failure in [
    LocationProblem.denied,
    LocationProblem.deniedForever,
    LocationProblem.disabled,
    LocationProblem.timeout,
    LocationProblem.unavailable,
  ]) {
    testWidgets(
      '$failure keeps manual selection usable, supports retry and settings',
      (tester) async {
        final service = FakeDeviceLocation()..failure = failure;
        await startWaitingApp(tester, service);
        await tapText(tester, 'Use My Location');
        expect(find.byKey(const ValueKey('location-error')), findsOneWidget);
        if (failure == LocationProblem.deniedForever) {
          await tapText(tester, 'Open app settings');
        }
        if (failure == LocationProblem.disabled) {
          await tapText(tester, 'Open location settings');
        }
        service.failure = null;
        await tapText(tester, 'Retry location');
        expect(service.calls, 2);
        await tapMap(tester);
        await tapText(tester, 'Confirm Location');
        expect(selected(tester)!.source, WaitingLocationSource.manualMap);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'leaving foreground cancels acquisition and ignores a late location',
    (tester) async {
      final service = FakeDeviceLocation()..pending = Completer<DeviceFix>();
      await startWaitingApp(tester, service);
      await tester.ensureVisible(find.text('Use My Location'));
      await tester.tap(find.text('Use My Location'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(WaitingLocationPicker), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      service.pending!.complete(
        DeviceFix(
          point: const GeoPoint(13.45, 121.84),
          measuredAt: DateTime.now(),
        ),
      );
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('passenger-waiting-marker')),
        findsNothing,
      );
      expect(service.calls, 1);
      expect(service.cancels, greaterThan(0));
      await tapText(tester, 'Cancel');
      expect(selected(tester), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
