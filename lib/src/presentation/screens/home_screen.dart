import 'package:flutter/material.dart';

import '../../theme.dart';
import '../jeepney_controller.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/journey_selector.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller, required this.onFind});
  final JeepneyController controller;
  final VoidCallback onFind;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Align(alignment: Alignment.centerLeft, child: DemoBadge()),
      const SizedBox(height: 18),
      const Text(
        'YOUR MARINDUQUE JOURNEY',
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 1.6,
          color: JeepLinkColors.green,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'Where are you headed?',
        key: const ValueKey('hero-title'),
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 10),
      const Text(
        'Start with your destination. Travel with clearer information.',
        style: TextStyle(color: JeepLinkColors.muted),
      ),
      const SizedBox(height: 24),
      JourneySelector(controller: controller, onFind: onFind),
      const SizedBox(height: 20),
      JourneyState(controller: controller),
      const SizedBox(height: 20),
      const GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A little clarity before you go',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 10),
            Text(
              'FULL and AVAILABLE are driver reports, not boarding guarantees. Check freshness and the last reported location.',
            ),
            SizedBox(height: 10),
            Text('ETA unavailable'),
          ],
        ),
      ),
      const SizedBox(height: 24),
      const DemoNotice(),
    ],
  );
}
