import 'package:flutter/material.dart';

import '../../config/data_config.dart';
import '../../config/map_config.dart';
import '../../domain/jeepney.dart';
import '../../theme.dart';
import '../jeepney_controller.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
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
    final fresh = controller.vehicles.where((v) => v.hasFreshReport).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'YOUR MARINDUQUE COMPANION',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.8,
            color: JeepLinkColors.green,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Good journeys\nstart with clarity.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 10),
        const Text(
          'A calmer way to check before you travel.',
          style: TextStyle(color: JeepLinkColors.muted),
        ),
        const SizedBox(height: 24),
        _WelcomeCard(onMap: onMap),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns =
                width >= 350 && MediaQuery.textScalerOf(context).scale(1) < 1.6
                ? 2
                : 1;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: (width - (columns - 1) * 12) / columns,
                  child: _Stat(
                    value: '${controller.vehicles.length}',
                    label: modeText(context, 'Demo jeepneys', 'API jeepneys'),
                    icon: Icons.airport_shuttle_rounded,
                  ),
                ),
                SizedBox(
                  width: (width - (columns - 1) * 12) / columns,
                  child: _Stat(
                    value: '$fresh',
                    label: 'Jeepneys with fresh reports',
                    icon: Icons.sensors_rounded,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        const Text(
          'Fresh reports count device records only. DEMO records are excluded.',
          style: TextStyle(
            fontSize: 11,
            color: JeepLinkColors.muted,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 26),
        SectionHeading(
          title: 'A look around',
          action: 'Open map',
          onAction: onMap,
        ),
        const Text(
          'Marinduque · Last reported positions',
          style: TextStyle(fontSize: 12, color: JeepLinkColors.muted),
        ),
        const SizedBox(height: 14),
        GlassPanel(
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            height: 240,
            child: JeepneyMap(
              jeepneys: controller.vehicles,
              onSelect: onSelect,
              interactive: false,
              config: mapConfig,
              tileProviderFactory: tileProviderFactory,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            _Legend(color: JeepLinkColors.green, label: 'Available'),
            _Legend(color: JeepLinkColors.amber, label: 'Full'),
            _Legend(color: JeepLinkColors.muted, label: 'Stale / unknown'),
          ],
        ),
        const SizedBox(height: 26),
        SectionHeading(
          title: modeText(
            context,
            'Explore demo jeepneys',
            'Your jeepney overview',
          ),
          action: 'View all',
          onAction: onJeepneys,
        ),
        const SizedBox(height: 12),
        if (controller.vehicles.isEmpty)
          const EmptyState(
            title: 'No jeepneys to show',
            message: 'Refresh to check for reports. No vehicles are added automatically.',
          )
        else
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final vehicle in controller.vehicles)
                  SizedBox(
                    width: constraints.maxWidth >= 760
                        ? (constraints.maxWidth - 28) / 3
                        : constraints.maxWidth,
                    child: JeepneyCard(
                      jeepney: vehicle,
                      onTap: () => onSelect(vehicle),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        const DemoNotice(),
        const SizedBox(height: 24),
        const Center(
          child: Text(
            'AbangQue · Made for Marinduque',
            style: TextStyle(
              fontSize: 11,
              color: JeepLinkColors.muted,
              letterSpacing: .4,
            ),
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
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(30),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF104E3D), Color(0xFF26795B)],
      ),
      border: Border.all(color: const Color(0xFF65AA87)),
      boxShadow: [
        BoxShadow(
          color: JeepLinkColors.green.withValues(alpha: .18),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    // Content stays in normal layout flow; never overlay text on artwork or
    // constrain the hero height. This remains readable at narrow/large-text sizes.
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DemoBadge(dark: true),
              const SizedBox(height: 18),
              const Text(
                'Know more.\nTravel with ease.',
                key: ValueKey('hero-title'),
                style: TextStyle(
                  fontSize: 27,
                  height: 1.16,
                  letterSpacing: -.8,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                modeText(
                  context,
                  'Explore fictional reports in a clearly marked demo.',
                  'Explore driver reports and last known locations.',
                ),
                style: const TextStyle(
                  color: Color(0xFFE3F4E9),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),
              PassengerButton(
                onPressed: onMap,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD4F2DB),
                  foregroundColor: JeepLinkColors.ink,
                ),
                icon: const Icon(Icons.map_outlined, size: 19),
                label: const Text('Explore the map'),
              ),
            ],
          );
          if (constraints.maxWidth >= 650 &&
              MediaQuery.textScalerOf(context).scale(1) < 1.5) {
            return Row(
              children: [
                Expanded(child: content),
                const SizedBox(width: 24),
                const Expanded(
                  child: AspectRatio(aspectRatio: 1.5, child: JeepneyArt()),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              content,
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerRight,
                child: SizedBox(width: 220, height: 125, child: JeepneyArt()),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.icon});
  final String value;
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => GlassPanel(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: JeepLinkColors.green),
        const SizedBox(height: 14),
        Text(value, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            height: 1.4,
            color: JeepLinkColors.muted,
          ),
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
      Icon(Icons.circle, size: 7, color: color),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, color: JeepLinkColors.muted),
        ),
      ),
    ],
  );
}
