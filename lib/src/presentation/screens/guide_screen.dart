import '../../config/data_config.dart';

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../widgets/common.dart';

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key, required this.onMap});
  final VoidCallback onMap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'A hand for your journey.',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 8),
      const Text(
        'Get to know your JeepLink passenger companion.',
        style: TextStyle(color: JeepLinkColors.muted),
      ),
      const SizedBox(height: 24),
      const DemoNotice(),
      const SizedBox(height: 24),
      SurfaceCard(
        child: Column(
          children: [
            _Step(
              number: '01',
              title: 'Explore the map',
              text: modeText(
                context,
                'Tap a sample jeepney to open its details. The pickup marker is fictional and is not your location.',
                'Tap a jeepney for its last reported position and timestamps. Historical positions may be outdated; no passenger location or pickup point is inferred.',
              ),
            ),
            Divider(height: 32),
            _Step(
              number: '02',
              title: 'Check the seat status',
              text: modeText(
                context,
                'AVAILABLE means this sample has open seats. FULL means its simulated capacity has been reached.',
                'API mode shows FULL or AVAILABLE only for fresh device records. STALE / UNKNOWN is not availability. Historical DEMO records never count as available.',
              ),
            ),
            Divider(height: 32),
            _Step(
              number: '03',
              title: 'Try a demo estimate',
              text: modeText(
                context,
                'ETAs illustrate arrival at the sample pickup point. They are not actual predictions or schedules.',
                'API ETA is unavailable. The backend does not calculate arrivals. No official schedules or routes are supplied.',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Text('Good to know', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      SurfaceCard(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: [
            ExpansionTile(
              title: Text('Is JeepLink tracking real jeepneys?'),
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    modeText(
                      context,
                      'No. This first version uses simulated vehicles. Real GPS hardware and a backend are not connected. Refresh demo changes only the sample data.',
                      'API mode reads the backend, but this does not verify live GPS hardware. Records labeled Historical DEMO are fixtures. Offline demo mode is a separate simulator.',
                    ),
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: Text('Are these official routes or stops?'),
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    'No official routes, stops, fares, or schedules are provided. Confirm your actual destination and fare with the driver or operator before boarding.',
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: Text('Why does the map need internet?'),
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    modeText(
                      context,
                      'The geographic map comes from OpenStreetMap. Map tiles need an internet connection; the sample fleet, search, and details can still be explored without it.',
                      'OpenStreetMap tiles and API reads need network access. API failures show an error and retry; they never silently switch to simulated vehicles.',
                    ),
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: Text('Does the app use my location?'),
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    'No location permission is requested. The map starts at a preset demo area around Boac, Marinduque.',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: onMap,
        icon: const Icon(Icons.map_outlined),
        label: Text(modeText(context, 'Try the demo map', 'Explore map')),
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
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          number,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: JeepLinkColors.green,
          ),
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 5),
            Text(text),
          ],
        ),
      ),
    ],
  );
}
