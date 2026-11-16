import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const branding = 'assets/branding';
final emerald = img.ColorRgba8(0, 77, 64, 255);

/// Technical fitting only: preserve interior pixels, remove the edge-connected
/// near-black JPEG matte, resize proportionally and center on emerald/alpha.
img.Image removeExteriorMatte(img.Image original) {
  final logo = original.convert(numChannels: 4);
  final visited = Uint8List(logo.width * logo.height);
  final queue = <int>[];
  void add(int x, int y) {
    if (x < 0 || y < 0 || x >= logo.width || y >= logo.height) return;
    final index = y * logo.width + x;
    if (visited[index] != 0) return;
    visited[index] = 1;
    final p = logo.getPixel(x, y);
    if (math.max(p.r, math.max(p.g, p.b)) <= 32 || p.a == 0) queue.add(index);
  }

  for (var x = 0; x < logo.width; x++) {
    add(x, 0);
    add(x, logo.height - 1);
  }
  for (var y = 0; y < logo.height; y++) {
    add(0, y);
    add(logo.width - 1, y);
  }
  for (var i = 0; i < queue.length; i++) {
    final x = queue[i] % logo.width, y = queue[i] ~/ logo.width;
    logo.getPixel(x, y).a = 0;
    add(x - 1, y);
    add(x + 1, y);
    add(x, y - 1);
    add(x, y + 1);
  }
  if (queue.length > logo.width * logo.height * .15) {
    throw StateError(
      'Exterior matte exceeds 15%; review a changed source before fitting.',
    );
  }
  stdout.writeln('Removed only exterior matte: ${queue.length} pixels.');
  return logo;
}

img.Image fit(
  img.Image logo,
  int canvasSize,
  int artworkSize, {
  bool transparent = false,
}) {
  final canvas = img.Image(
    width: canvasSize,
    height: canvasSize,
    numChannels: 4,
  );
  if (!transparent) img.fill(canvas, color: emerald);
  final resized = img.copyResize(
    logo,
    width: artworkSize,
    height: artworkSize,
    interpolation: img.Interpolation.average,
  );
  return img.compositeImage(
    canvas,
    resized,
    dstX: (canvasSize - artworkSize) ~/ 2,
    dstY: (canvasSize - artworkSize) ~/ 2,
  );
}

void png(String path, img.Image value) =>
    File(path).writeAsBytesSync(img.encodePng(value));

void preview(img.Image legacy, img.Image foreground) {
  final adaptive = img.Image(width: 1080, height: 1080, numChannels: 4);
  img.fill(adaptive, color: emerald);
  img.compositeImage(adaptive, foreground);
  final viewport = img.copyCrop(
    adaptive,
    x: 180,
    y: 180,
    width: 720,
    height: 720,
  );
  final sheet = img.Image(width: 960, height: 380, numChannels: 4);
  img.fill(sheet, color: img.ColorRgb8(245, 247, 242));
  final labels = [
    'Legacy / iOS',
    'Android circle',
    'Android squircle',
    '48px / 32px',
  ];
  for (var i = 0; i < 4; i++) {
    img.drawString(
      sheet,
      labels[i],
      font: img.arial14,
      x: i * 240 + 16,
      y: 18,
      color: img.ColorRgb8(23, 47, 40),
    );
    if (i == 3) {
      for (final size in [48, 32]) {
        final small = img.copyResize(
          viewport,
          width: size,
          height: size,
          interpolation: img.Interpolation.average,
        );
        img.compositeImage(
          sheet,
          small,
          dstX: 750,
          dstY: size == 48 ? 95 : 180,
        );
      }
      continue;
    }
    final icon = img.copyResize(
      i == 0 ? legacy : viewport,
      width: 208,
      height: 208,
      interpolation: img.Interpolation.average,
    );
    if (i > 0) {
      for (final p in icon) {
        final x = (p.x + .5 - 104) / 104, y = (p.y + .5 - 104) / 104;
        final outside = i == 1
            ? x * x + y * y > 1
            : math.pow(x, 4) + math.pow(y, 4) > 1;
        if (outside) p.a = 0;
      }
    }
    img.compositeImage(sheet, icon, dstX: i * 240 + 16, dstY: 65);
  }
  img.drawString(
    sheet,
    'Mask simulations only - confirm on the actual Android launcher.',
    font: img.arial14,
    x: 16,
    y: 330,
    color: img.ColorRgb8(23, 47, 40),
  );
  Directory('build/design-preview').createSync(recursive: true);
  png('build/design-preview/app-icon-masks.png', sheet);
}

Future<void> main() async {
  final source = img.decodeImage(
    File('$branding/abangque-logo-original.jpg').readAsBytesSync(),
  );
  if (source == null || source.width != source.height || source.width < 512) {
    throw StateError(
      'Provide a square source at least 512 pixels wide; no cropping is performed.',
    );
  }
  final logo = removeExteriorMatte(source);
  final legacy = fit(logo, 1024, 940);
  // 64 dp artwork in a 108 dp layer, with critical artwork inside the 66 dp safe area.
  final foreground = fit(logo, 1080, 640, transparent: true);
  final maskable = fit(logo, 1024, 780);
  png('$branding/app-icon.png', legacy);
  png('$branding/app-icon-foreground.png', foreground);
  png('$branding/app-icon-maskable.png', maskable);
  stdout.writeln('Running dart run flutter_launcher_icons');
  // AppIcon is already wired up. Version 0.14.4 can mistakenly rewrite other
  // ASSETCATALOG build settings, so preserve the existing native project bytes.
  final iosProject = File('ios/Runner.xcodeproj/project.pbxproj');
  final iosSettings = iosProject.readAsBytesSync();
  if (!utf8
      .decode(iosSettings)
      .contains('ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;')) {
    throw StateError('Review the iOS AppIcon configuration before generating.');
  }
  late ProcessResult generated;
  try {
    generated = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'flutter_launcher_icons'],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  } finally {
    iosProject.writeAsBytesSync(iosSettings);
  }
  stdout.write(generated.stdout);
  stderr.write(generated.stderr);
  if (generated.exitCode != 0) {
    exitCode = generated.exitCode;
    return;
  }
  // Preserve the existing Web manifest's trailing newline after generation.
  final manifest = File('web/manifest.json');
  manifest.writeAsStringSync('${manifest.readAsStringSync().trimRight()}\n');
  final catalog = File(
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json',
  );
  catalog.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(jsonDecode(catalog.readAsStringSync()))}\n',
  );
  // The generator uses one Web image for both normal and maskable icons. Give
  // maskable resources their own additional padding without changing the manifest.
  for (final size in [192, 512]) {
    png(
      'web/icons/Icon-maskable-$size.png',
      img.copyResize(
        maskable,
        width: size,
        height: size,
        interpolation: img.Interpolation.average,
      ),
    );
  }
  // Include native small sizes as well as the generator's 256px Windows icon.
  File('windows/runner/resources/app_icon.ico').writeAsBytesSync(
    img.IcoEncoder().encodeImages([
      for (final size in [16, 24, 32, 48, 64, 128, 256])
        img.copyResize(
          legacy,
          width: size,
          height: size,
          interpolation: img.Interpolation.average,
        ),
    ]),
  );
  preview(legacy, foreground);
  stdout.writeln(
    'Android/iOS/Web/Windows icons generated; preview: build/design-preview/app-icon-masks.png',
  );
}
