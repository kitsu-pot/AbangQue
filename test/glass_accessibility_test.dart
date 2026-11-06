import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeeplink/src/app.dart';
import 'package:jeeplink/src/data/demo_jeepney_repository.dart';
import 'package:jeeplink/src/presentation/widgets/glass.dart';

import 'fakes.dart';
import 'widget_test.dart' show startApp, tab, chooseJourney;

void main() {
  testWidgets('large text details, keyboard, insets and reduced motion', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    tester.view.padding = const FakeViewPadding(top: 32, bottom: 24);
    addTearDown(() {
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      tester.view.resetPadding();
      tester.view.resetViewInsets();
    });
    await startApp(
      tester,
      size: const Size(320, 800),
      textScale: 2,
      withRoutes: true,
    );
    expect(find.byType(BackdropFilter), findsNothing);
    final hero = tester.renderObject<RenderParagraph>(
      find.byKey(const ValueKey('hero-title')),
    );
    expect(hero.didExceedMaxLines, isFalse);
    await chooseJourney(tester);
    await tester.ensureVisible(find.byType(TextFormField));
    await tester.tap(find.byType(TextFormField));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.enterText(find.byType(TextFormField), 'DEMO-02');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final cardTitle = find.descendant(
      of: find.byKey(const ValueKey('vehicle-DEMO-02')),
      matching: find.text('DEMO-02'),
    );
    await tester.ensureVisible(cardTitle);
    await tester.tap(cardTitle);
    await tester.pumpAndSettle();
    expect(find.text('MANUALLY REPORTED STATUS'), findsOneWidget);
    await tester.ensureVisible(find.text('View last location on map'));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('View last location on map'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selected-jeepney')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone screens keep honest labels and bounded glass effects', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const capture = bool.fromEnvironment('CAPTURE_DESIGN');
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
    const boundaryKey = ValueKey('design-capture');
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: JeepLinkApp(
          locationService: NoDeviceLocation(),
          repository: DemoJeepneyRepository(
            clock: () => DateTime.utc(2026, 10, 31),
          ),
          tileProviderFactory: MemoryTileProvider.new,
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final name in ['Home', 'Map', 'Jeepneys', 'Guide']) {
      await tab(tester, name);
      expect(find.byType(GlassPanel), findsWidgets);
      expect(find.byType(BackdropFilter), findsOneWidget);
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');
      expect(
        texts,
        isNot(
          matches(
            RegExp(r'JeepLink|\d+\s+(seats?|min\b)', caseSensitive: false),
          ),
        ),
      );
      expect(texts.toLowerCase(), isNot(contains('seat count')));
      expect(tester.takeException(), isNull, reason: name);
      if (capture) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundaryKey),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = await Directory('build/design-preview')
              .create(recursive: true);
          await File('${directory.path}/${name.toLowerCase()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
  });
}
