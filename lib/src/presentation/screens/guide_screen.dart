import 'package:flutter/material.dart';

import '../../config/data_config.dart';
import '../../theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key, required this.onMap});
  final VoidCallback onMap;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'A LITTLE GUIDANCE',
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 1.7,
          fontWeight: FontWeight.w800,
          color: JeepLinkColors.green,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'Travel informed.',
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 8),
      const Text(
        'Your guide to a clearer journey with AbangQue.',
        style: TextStyle(color: JeepLinkColors.muted),
      ),
      const SizedBox(height: 24),
      const DemoNotice(),
      const SizedBox(height: 22),
      const GlassPanel(
        child: Column(
          children: [
            _Step(
              number: '01',
              title: 'Find a jeepney',
              text: 'Explore the list or tap a map marker. Locations are last reported positions and may be outdated.',
            ),
            Divider(height: 32),
            _Step(
              number: '02',
              title: 'Check the driver report',
              text: 'FULL and AVAILABLE are manually selected by the driver. UNKNOWN or STALE means a current status is not available.',
            ),
            Divider(height: 32),
            _Step(
              number: '03',
              title: 'Look at the report time',
              text: 'Check the last communication before making travel decisions. ETA is unavailable in every mode.',
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),
      Text('Good to know', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 14),
      GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: [
            const _Question(
              title: 'Is the status automatically detected?',
              answer: 'No. The driver selects FULL or AVAILABLE using a toggle. AbangQue does not count passengers. The report is general information, not a boarding guarantee.',
            ),
            _Question(
              title: 'Is AbangQue tracking real jeepneys?',
              answer: modeText(
                context,
                'This offline DEMO uses fictional locations and simulated manual reports. It is not real GPS tracking.',
                'API mode reads backend records. Historical DEMO records are fixtures, and accepted data does not by itself verify physical GPS hardware.',
              ),
            ),
            const _Question(
              title: 'Are these official routes or stops?',
              answer: 'No verified routes, stops or schedules are supplied. Operations can vary, including terminal-based departures. Confirm your journey with the operator.',
            ),
            const _Question(
              title: 'Why is ETA unavailable?',
              answer: 'An arrival calculation has not been implemented or verified. AbangQue does not show invented estimates in API or DEMO mode.',
            ),
            const _Question(
              title: 'What happens without a connection?',
              answer: 'API mode shows an error and a retry action; it never silently switches to simulation. Offline DEMO is separately selected. OpenStreetMap tiles still need network access.',
            ),
            const _Question(
              title: 'Does the app use my location?',
              answer: 'No location permission is requested. The map opens around Boac, Marinduque. Its markers are jeepney records, not your position.',
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      PassengerButton(
        onPressed: onMap,
        icon: const Icon(Icons.map_outlined),
        label: const Text('Explore the map'),
      ),
    ],
  );
}

class _Question extends StatelessWidget {
  const _Question({required this.title, required this.answer});
  final String title;
  final String answer;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: Text(
      title,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        child: Text(
          answer,
          style: const TextStyle(height: 1.6, color: JeepLinkColors.muted),
        ),
      ),
    ],
  );
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.text});
  final String number;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: JeepLinkColors.paleGreen,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          number,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: JeepLinkColors.green,
          ),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(text, style: const TextStyle(height: 1.55)),
          ],
        ),
      ),
    ],
  );
}
