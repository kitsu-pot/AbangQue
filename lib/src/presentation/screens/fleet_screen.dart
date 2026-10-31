import '../../config/data_config.dart';

import 'package:flutter/material.dart';

import '../../config/map_config.dart';
import '../../domain/jeepney.dart';
import '../../theme.dart';
import '../jeepney_controller.dart';
import '../widgets/common.dart';
import '../widgets/jeepney_map.dart';

class FleetScreen extends StatelessWidget {
  const FleetScreen({
    super.key,
    required this.controller,
    required this.onSelect,
    required this.showMap,
    required this.mapConfig,
    this.focus,
    this.tileProviderFactory,
  });
  final JeepneyController controller;
  final ValueChanged<Jeepney> onSelect;
  final bool showMap;
  final Jeepney? focus;
  final MapConfig mapConfig;
  final TileProviderFactory? tileProviderFactory;

  @override
  Widget build(BuildContext context) {
    final vehicles = controller.filteredVehicles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          showMap ? 'Find your bearings.' : 'A seat for your journey.',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 7),
        Text(
          modeText(
            context,
            showMap
                ? 'Boac, Marinduque · Explore the demo area'
                : 'Browse the simulated JeepLink fleet.',
            'API records · Check status and freshness',
          ),
          style: const TextStyle(color: JeepLinkColors.muted),
        ),
        const SizedBox(height: 20),
        const DemoNotice(),
        const SizedBox(height: 18),
        TextFormField(
          key: ValueKey('fleet-search-$showMap'),
          initialValue: controller.query,
          onChanged: controller.setQuery,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: modeText(
              context,
              'Search demo jeepney ID',
              'Search jeepney ID',
            ),
            labelText: 'Search jeepneys',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text('All jeepneys (${controller.vehicles.length})'),
              selected: !controller.availableOnly,
              onSelected: (_) => controller.setAvailableOnly(false),
            ),
            ChoiceChip(
              label: Text('Available (${controller.availableCount})'),
              selected: controller.availableOnly,
              onSelected: (_) => controller.setAvailableOnly(true),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (showMap) ...[
          SizedBox(
            height: 410,
            child: JeepneyMap(
              jeepneys: vehicles,
              onSelect: onSelect,
              focus: focus,
              config: mapConfig,
              tileProviderFactory: tileProviderFactory,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            modeText(
              context,
              'Tap a jeepney for details. The person pin is a sample pickup point, not your location or an official stop.',
              'Markers show last reported positions, not guaranteed current locations. Vehicles without coordinates appear only in the list.',
            ),
            style: TextStyle(fontSize: 12, color: JeepLinkColors.muted),
          ),
          const SizedBox(height: 22),
        ],
        Text(
          '${vehicles.length} ${DataModeScope.isApi(context) ? 'API' : 'demo'} ${vehicles.length == 1 ? 'jeepney' : 'jeepneys'}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (vehicles.isEmpty)
          const EmptyState(
            title: 'No matching jeepneys',
            message: 'Try another demo ID or choose All jeepneys.',
          )
        else
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final vehicle in vehicles)
                  SizedBox(
                    width: constraints.maxWidth > 760
                        ? (constraints.maxWidth - 24) / 3
                        : constraints.maxWidth,
                    child: JeepneyCard(
                      jeepney: vehicle,
                      onTap: () => onSelect(vehicle),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
