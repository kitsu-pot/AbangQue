import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class DataConfig {
  const DataConfig({required this.apiMode, required this.baseUrl});
  final bool apiMode;
  final Uri baseUrl;
  factory DataConfig.fromEnvironment() => DataConfig.parse(
    mode: const String.fromEnvironment('DATA_MODE', defaultValue: 'api'),
    url: const String.fromEnvironment('API_BASE_URL'),
    platform: defaultTargetPlatform,
    debug: kDebugMode,
  );
  static DataConfig parse({
    required String mode,
    required String url,
    required TargetPlatform platform,
    required bool debug,
  }) {
    if (mode != 'api' && mode != 'demo') {
      throw const FormatException('DATA_MODE must be api or demo.');
    }
    final uri = Uri.tryParse(
      url.isEmpty
          ? (platform == TargetPlatform.android
                ? 'http://10.0.2.2:3000'
                : 'http://127.0.0.1:3000')
          : url,
    );
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        !['http', 'https'].contains(uri.scheme)) {
      throw const FormatException(
        'API_BASE_URL must be an HTTP(S) origin without credentials, path, query, or fragment.',
      );
    }
    if (mode == 'api' &&
        uri.scheme == 'http' &&
        (!debug ||
            !['127.0.0.1', '10.0.2.2', 'localhost'].contains(uri.host))) {
      throw const FormatException(
        'API mode requires HTTPS outside local debug builds. Set API_BASE_URL.',
      );
    }
    return DataConfig(apiMode: mode == 'api', baseUrl: uri);
  }
}

class DataModeScope extends InheritedWidget {
  const DataModeScope({super.key, required this.apiMode, required super.child});
  final bool apiMode;
  static bool isApi(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DataModeScope>()?.apiMode ??
      false;
  @override
  bool updateShouldNotify(DataModeScope oldWidget) =>
      apiMode != oldWidget.apiMode;
}

String modeText(BuildContext context, String demo, String api) =>
    DataModeScope.isApi(context) ? api : demo;
