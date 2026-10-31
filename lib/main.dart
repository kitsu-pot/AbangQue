import 'package:flutter/material.dart';

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
