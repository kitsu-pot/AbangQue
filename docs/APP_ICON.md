# Official AbangQue launcher icon

Updated 2026-11-16. Checkpoint: `checkpoint/app-icon-2026-11-16` at `4edf9b9`.
This changes launcher resources only, preserving the app ID, screens, API settings,
backend and admin web. Existing local thesis/diagram edits are outside this change.

## Source and fitting

`assets/branding/abangque-logo-original.jpg` is a byte-for-byte copy of the supplied
`26962.png`: the supplied file actually contains a 1536×1536 JPEG. The original is
kept unchanged. No logo elements were redrawn, recolored or cropped.

The Dart helper removes only near-black pixels connected to the exterior border
(the JPEG's black corner matte), using an RGB maximum of 32. Interior dark pixels
remain intact. A 15% removal guard stops unexpectedly different artwork; review
this fitting step when changing the source. The supplied file removes about 10.2%.
It then scales proportionally and centers the badge, with `#004D40` emerald behind it:

- `app-icon.png`: opaque 1024×1024, artwork 940×940, for standard/Apple/Windows icons.
- `app-icon-foreground.png`: transparent 1080×1080, artwork 640×640, for Android.
  This represents 64 dp of artwork inside a 108 dp layer, with 22 dp padding per side.
  The generator's extra adaptive inset is zero to avoid applying padding twice.
- `app-icon-maskable.png`: opaque 1024×1024, artwork 780×780, for maskable Web icons.

The supplied artwork's light details were checked inside Android's central 66 dp
safe circle; circular and rounded-square simulations were visually reviewed.
Outer decorative background can be masked, while the jeepney, Morion mask and
Marinduque outline remain visible. These simulations are not phone screenshots.
No separate monochrome redesign is supplied; launcher theme settings may tint icons.
Turn off themed icons when checking the original green color on the phone.

Sources: [Android adaptive-icon guidance](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)
and [flutter_launcher_icons configuration](https://pub.dev/packages/flutter_launcher_icons).

## Configuration and generated files

`pubspec.yaml` adds **development-only** `flutter_launcher_icons: 0.14.4` and the
`image` utility used by the fitting helper; `pubspec.lock` locks resolved versions.
No runtime Dart code or packaged Flutter asset declaration is changed.

`flutter_launcher_icons.yaml` configures Android/iOS/Web/Windows. Android keeps its
existing `@mipmap/ic_launcher` manifest reference:

- `android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png`
  contains 48, 72, 96, 144 and 192 px standard icons.
- `drawable-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher_foreground.png` contains
  108, 162, 216, 324 and 432 px adaptive foregrounds.
- `mipmap-anydpi-v26/ic_launcher.xml` references the foreground and solid background
  from `values/colors.xml`; Android 8+ selects this resource automatically.
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/` contains opaque RGB icons and its
  generated catalog. The helper preserves the original Xcode project bytes because
  generator 0.14.4 can rewrite an unrelated ASSETCATALOG build setting. AppIcon was
  already correctly configured; no signing/package settings are changed.
- `web/favicon.png` and `web/icons/` replace the existing Flutter Web icons. The
  helper adds separate safe padding to the two maskable resources and preserves
  existing manifest metadata. This does not change the separate admin-web favicon.
- `windows/runner/resources/app_icon.ico` includes 16/24/32/48/64/128/256 px images
  for the existing Runner resource reference. Rebuild Windows to embed the new ICO.

The original and prepared sources are committed with the native icon resources.
Only build artifacts/previews remain ignored. macOS/Linux launcher setup is unchanged.

## Regenerate

From the project root, with the installed Flutter/Dart SDK on PATH:

```powershell
flutter pub get
dart run tool/generate_app_icons.dart
```

The helper prepares PNG sources, invokes `dart run flutter_launcher_icons`, preserves
Xcode settings, fits Web maskable icons, creates the multi-size Windows ICO and
writes `build/design-preview/app-icon-masks.png`. Use the helper for a full rebuild;
running the underlying package alone omits these safeguards/final fitting steps.
For future branding, replace the square original, review the matte/padding assumptions,
rerun the helper and inspect the mask preview before committing.

Validation commands used:

```powershell
flutter analyze --no-pub
flutter test --no-pub
New-Item -ItemType Directory -Force build/jvm-tmp | Out-Null
$env:JAVA_TOOL_OPTIONS='-Djdk.net.unixdomain.tmpdir=C:/Users/Administrator/Projects/jeeplink/build/jvm-tmp'
flutter build apk --debug --no-pub --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

The Java option is the existing Windows host workaround. No network-security
exception, app ID, release signing or minSdk configuration is changed.

Observed results on 2026-11-16:

- Dependency resolution and the complete icon-generation helper passed.
- Flutter analysis reported no issues; Flutter tests passed 106 cases, with the
  existing opt-in GPS integration test skipped (no test-server URL supplied).
- Android debug APK built successfully at `build/app/outputs/flutter-apk/app-debug.apk`.
- APK inspection confirmed the AbangQue label, unchanged `com.example.jeeplink`
  package, adaptive XML wiring and `#004D40` background. All ten packaged Android
  PNGs matched the generated images pixel-for-pixel at their expected sizes.
- The original matched the supplied image bytes. iOS catalog sizes/opaque pixels,
  seven Windows ICO sizes and normal/maskable Web dimensions were verified.
- No Android device was attached; the launcher has not been physically verified.

## Infinix installation and launcher check

1. Connect the phone, enable USB debugging and accept its authorization prompt.
2. From `C:\Users\Administrator\Projects\jeeplink`, install the built debug APK
   over the existing app without clearing its data:

```powershell
adb devices -l
$phoneId = Read-Host 'Enter the Infinix device ID'
adb -s $phoneId install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s $phoneId reverse tcp:3000 tcp:3000
adb -s $phoneId shell am start -n com.example.jeeplink/.MainActivity
```

3. Return to the launcher. Check AbangQue in the app drawer, home-screen shortcut
   and Android App info. Check the crest, jeepney and island at normal launcher size,
   and any available circle/rounded-square icon-shape settings. Turn off themed
   icons/icon packs when checking the supplied green branding.
4. If a pinned shortcut still shows the previous icon, remove only that shortcut
   and add it again from the app drawer; restart the launcher/phone if needed.
   Do not clear app data or uninstall just to refresh the icon cache. If installation
   reports a signing mismatch, use the original development signing setup.
5. Start your existing backend (`npm start` from `backend`) for API behavior checks.
   Installing and inspecting the icon itself does not require a running backend.

The optional equivalent development launch is:

```powershell
flutter run -d $phoneId --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

No phone was attached during implementation. Windows/Web/iOS resources were updated
and inspected; those platforms were not built or launched for this task. iOS build
and launcher acceptance require macOS/Xcode. Browser favicons may need a hard refresh;
a previously installed PWA may retain an older icon until refreshed/reinstalled.
