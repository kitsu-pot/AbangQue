import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeeplink/src/app.dart';
import 'package:jeeplink/src/auth/auth_controller.dart';
import 'package:jeeplink/src/data/demo_jeepney_repository.dart';

import 'auth_test.dart' show MemorySessionStore, api;
import 'fakes.dart';

void main() {
  testWidgets('welcome and registration explain optional accounts on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const capture = bool.fromEnvironment('CAPTURE_AUTH');
    const fontDirectory = String.fromEnvironment('DESIGN_FONT_DIR');
    if (capture && fontDirectory.isNotEmpty) {
      await tester.runAsync(() async {
        for (final font in {
          'Roboto': 'Roboto-Regular.ttf',
          'MaterialIcons': 'MaterialIcons-Regular.otf',
        }.entries) {
          final loader = FontLoader(font.key);
          loader.addFont(
            File('$fontDirectory/${font.value}')
                .readAsBytes()
                .then((b) => ByteData.sublistView(b)),
          );
          await loader.load();
        }
      });
    }
    const boundaryKey = ValueKey('auth-preview');
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: JeepLinkApp(
          repository: DemoJeepneyRepository(),
          tileProviderFactory: MemoryTileProvider.new,
          authController: AuthController(
            repository: api(
              (_) async => throw StateError('No account submitted'),
            ),
            store: MemorySessionStore(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> snapshot(String name) async {
      expect(tester.takeException(), isNull);
      if (!capture) return;
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = await Directory('build/design-preview')
            .create(recursive: true);
        await File('${directory.path}/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    expect(find.text('Welcome aboard'), findsOneWidget);
    expect(find.text('Continue as Guest'), findsOneWidget);
    expect(
      find.text(
        'An account is optional. Transport information is available to everyone.',
      ),
      findsOneWidget,
    );
    await snapshot('sign-in');
    await tester.ensureVisible(find.text('New to AbangQue? Register'));
    await tester.tap(find.text('New to AbangQue? Register'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(4));
    await snapshot('register');
    await tester.ensureVisible(find.text('Continue as Guest'));
    await tester.pumpAndSettle();
    await snapshot('register-actions');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
