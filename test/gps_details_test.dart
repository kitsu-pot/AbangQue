import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeeplink/src/app.dart';
import 'package:jeeplink/src/data/api_jeepney_repository.dart';
import 'package:jeeplink/src/domain/passenger_route.dart';

import 'fakes.dart';
import 'gps_tracking_test.dart' show simulated;
import 'widget_test.dart' show chooseJourney;

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'simulated details stay readable on a narrow phone at scale $scale',
      (tester) async {
        tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        const capture = bool.fromEnvironment('CAPTURE_GPS');
        const fontDirectory = String.fromEnvironment('DESIGN_FONT_DIR');
        if (capture && fontDirectory.isNotEmpty) {
          await tester.runAsync(() async {
            for (final font in {
              'Roboto': 'Roboto-Regular.ttf',
              'MaterialIcons': 'MaterialIcons-Regular.otf',
            }.entries) {
              final loader = FontLoader(font.key)
                ..addFont(
                  File('$fontDirectory/${font.value}')
                      .readAsBytes()
                      .then(ByteData.sublistView),
                );
              await loader.load();
            }
          });
        }
        final repo = TestRepository();
        final routes = TestRouteRepository()
          ..catalog = RouteCatalog(
            routes: [
              PassengerRoute(
                id: 'DEMO-PREVIEW',
                origin: Municipality.boac,
                destination: Municipality.gasan,
                isDemo: true,
              ),
            ],
            assignments: const [
              RouteAssignment(
                jeepneyId: 'SIM-GPS-001',
                routeId: 'DEMO-PREVIEW',
              ),
            ],
          );
        const boundary = ValueKey('gps-details-preview');
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: JeepLinkApp(
              locationService: NoDeviceLocation(),
              repository: repo,
              routeRepository: routes,
              apiMode: true,
              tileProviderFactory: MemoryTileProvider.new,
            ),
          ),
        );
        repo.updates.add([
          parseApiJeepney(simulated(DateTime.utc(2026, 11, 1))),
        ]);
        await tester.pumpAndSettle();
        await chooseJourney(tester);
        final card = find.byKey(const ValueKey('vehicle-SIM-GPS-001'));
        // Large cards can exceed the viewport; tap the visible identifier.
        final identifier = find.descendant(
          of: card,
          matching: find.text('SIM-GPS-001'),
        );
        await tester.ensureVisible(identifier);
        await tester.tap(identifier);
        await tester.pumpAndSettle();
        expect(find.text('SIMULATED / DEMO'), findsOneWidget);
        expect(find.text('Information unavailable'), findsOneWidget);
        expect(tester.takeException(), isNull);
        Future<void> snapshot(String suffix) async {
          if (!capture || scale != 1) return;
          final render = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(boundary),
          );
          await tester.runAsync(() async {
            final image = await render.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final directory = await Directory('build/design-preview')
                .create(recursive: true);
            await File('${directory.path}/gps-details-$suffix.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await snapshot('top');
        await tester.ensureVisible(find.text('Device connectivity'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await snapshot('report');
        await tester.ensureVisible(find.text('View last location on map'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('View last location on map'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('marker-SIM-GPS-001')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
