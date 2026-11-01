import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'src/auth/auth_controller.dart';
import 'src/auth/passenger_auth.dart';
import 'src/auth/session_store.dart';

import 'src/app.dart';
import 'src/config/data_config.dart';
import 'src/data/api_jeepney_repository.dart';
import 'src/data/demo_jeepney_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final config = DataConfig.fromEnvironment();
    runApp(
      JeepLinkApp(
        repository: config.apiMode
            ? ApiJeepneyRepository(baseUrl: config.baseUrl)
            : DemoJeepneyRepository(),
        apiMode: config.apiMode,
        authController: AuthController(
          repository: config.apiMode && !kIsWeb
              ? ApiPassengerAuthRepository(baseUrl: config.baseUrl)
              : null,
          store: SecureSessionStore(config.baseUrl),
        ),
      ),
    );
  } on FormatException catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('AbangQue configuration error: ${error.message}'),
            ),
          ),
        ),
      ),
    );
  }
}
