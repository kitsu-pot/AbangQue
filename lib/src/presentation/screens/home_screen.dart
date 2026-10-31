import '../../config/data_config.dart';

import 'package:flutter/material.dart';

import '../../config/map_config.dart';
import '../../domain/jeepney.dart';
import '../../theme.dart';
import '../jeepney_controller.dart';
import '../widgets/common.dart';
import '../widgets/jeepney_art.dart';
import '../widgets/jeepney_map.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.onMap,
    required this.onJeepneys,
    required this.onSelect,
    required this.mapConfig,
    this.tileProviderFactory,
  });
  final JeepneyController controller;
  final VoidCallback onMap;
  final VoidCallback onJeepneys;
  final ValueChanged<Jeepney> onSelect;
  final MapConfig mapConfig;
  final TileProviderFactory? tileProviderFactory;

  @override
  Widget build(BuildContext context) {
    final estimates =
        controller.vehicles
            .where(
              (v) => v.status == OccupancyStatus.available && v.eta != null,
            )
            .map((v) => v.eta!.inMinutes)
            .toList()
          ..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'YOUR EVERYDAY TRAVEL COMPANION',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: JeepLinkColors.muted,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tara, sakay na.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 5),
        const Text(
          'A little less waiting. A better way to go.',
          style: TextStyle(color: JeepLinkColors.muted),
        ),
        const SizedBox(height: 24),
        _WelcomeCard(onMap: onMap),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final stats = [
              _Stat(
                value: '${controller.vehicles.length}',
                label: modeText(context, 'Demo jeepneys', 'API jeepneys'),
                icon: Icons.airport_shuttle_rounded,
              ),
              _Stat(
                value: '${controller.availableCount}',
                label: 'With open seats*',
                icon: Icons.event_seat_outlined,
              ),
              _Stat(
                value: estimates.isEmpty ? '—' : '${estimates.first} min',
                label: modeText(
                  context,
                  'Earliest demo ETA',
                  'ETA unavailable',
                ),
                icon: Icons.schedule_rounded,
              ),
            ];
            if (constraints.maxWidth < 350 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.4) {
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final stat in stats)
                    SizedBox(width: constraints.maxWidth, child: stat),
                ],
              );
            }
            return Row(
              children: [
                for (var i = 0; i < stats.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: stats[i]),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          modeText(
            context,
            '* Sample seat availability. All values are simulated.',
            '* Only fresh device reports count as available. Historical DEMO records do not.',
          ),
          style: TextStyle(fontSize: 11, color: JeepLinkColors.muted),
        ),
        const SizedBox(height: 24),
        SectionHeading(
          title: modeText(
            context,
            'Around the demo area',
            'Last reported locations',
          ),
          action: 'Open map ↗',
          onAction: onMap,
        ),
        Text(
          modeText(
            context,
            'Boac, Marinduque · Sample locations',
            'Marinduque · Historical positions may be outdated',
          ),
          style: TextStyle(fontSize: 12, color: JeepLinkColors.muted),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 250,
          child: JeepneyMap(
            jeepneys: controller.vehicles,
            onSelect: onSelect,
            interactive: false,
            config: mapConfig,
            tileProviderFactory: tileProviderFactory,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            _Legend(color: JeepLinkColors.green, label: 'Available'),
            _Legend(color: JeepLinkColors.amber, label: 'Full'),
            if (!DataModeScope.isApi(context))
              Text(
                '◎ Sample pickup',
                style: TextStyle(fontSize: 11, color: JeepLinkColors.muted),
              ),
            if (DataModeScope.isApi(context))
              const _Legend(
                color: JeepLinkColors.muted,
                label: 'Stale / unknown',
              ),
          ],
        ),
        const SizedBox(height: 24),
        SectionHeading(
          title: modeText(context, 'Meet the demo fleet', 'Fleet from API'),
          action: 'View all',
          onAction: onJeepneys,
        ),
        const SizedBox(height: 12),
        if (controller.vehicles.isEmpty)
          EmptyState(
            title: 'No jeepneys to show',
            message: modeText(
              context,
              'Refresh the demo to try loading the sample fleet.',
              'No API records to display. Refresh to check again.',
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final jeepney in controller.vehicles)
                  SizedBox(
                    width: constraints.maxWidth >= 760
                        ? (constraints.maxWidth - 24) / 3
                        : constraints.maxWidth,
                    child: JeepneyCard(
                      jeepney: jeepney,
                      onTap: () => onSelect(jeepney),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 22),
        const DemoNotice(),
        const SizedBox(height: 20),
        Center(
          child: Text(
            'Made for the journeys of Marinduque.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.onMap});
  final VoidCallback onMap;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: JeepLinkColors.green,
      borderRadius: BorderRadius.circular(24),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 580;
        final copy = Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DemoBadge(dark: true),
                  Text(
                    'A FIRST LOOK AT JEEPLINK',
                    style: TextStyle(
                      fontSize: 9,
                      color: Color(0xFFE0EFCF),
                      letterSpacing: .8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Your next ride,\na little clearer.',
                style: TextStyle(
                  fontSize: 29,
                  height: 1.12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.8,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                modeText(
                  context,
                  'Explore sample jeepneys,\ncheck seats, and try the map.',
                  'Browse backend records.\nCheck freshness before travel.',
                ),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Color(0xFFD7E7DD),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onMap,
                style: FilledButton.styleFrom(
                  backgroundColor: JeepLinkColors.lime,
                  foregroundColor: JeepLinkColors.ink,
                ),
                icon: const Icon(Icons.map_outlined, size: 19),
                label: Text(
                  modeText(context, 'Explore demo map', 'Explore map'),
                ),
              ),
            ],
          ),
        );
        if (wide) {
          return Row(
            children: [
              Expanded(child: copy),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: AspectRatio(aspectRatio: 1.5, child: JeepneyArt()),
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            copy,
            const SizedBox(height: 155, child: JeepneyArt()),
          ],
        );
      },
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.icon});
  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(13),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: JeepLinkColors.green),
        const SizedBox(height: 12),
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: JeepLinkColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: JeepLinkColors.muted),
        ),
      ],
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.circle, size: 8, color: color),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: JeepLinkColors.muted),
      ),
    ],
  );
}
