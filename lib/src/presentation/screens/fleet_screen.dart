import '../../config/data_config.dart';

import 'package:flutter/material.dart';

import '../../config/map_config.dart';
import '../../domain/jeepney.dart';
import '../../theme.dart';
import '../jeepney_controller.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/jeepney_map.dart';

class FleetScreen extends StatefulWidget {
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
  State<FleetScreen> createState() => _FleetScreenState();
}

class _FleetScreenState extends State<FleetScreen> {
  String? _selectedId;
  JeepneyController get controller => widget.controller;
  ValueChanged<Jeepney> get onSelect => widget.onSelect;
  bool get showMap => widget.showMap;
  Jeepney? get focus => widget.focus;
  MapConfig get mapConfig => widget.mapConfig;
  TileProviderFactory? get tileProviderFactory => widget.tileProviderFactory;

  @override
  Widget build(BuildContext context) {
    final vehicles = controller.filteredVehicles;
    final selected = vehicles
        .where((v) => v.id == (_selectedId ?? focus?.id))
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          showMap ? 'Find your bearings.' : 'Your next journey.',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 7),
        Text(
          modeText(
            context,
            showMap
                ? 'Boac, Marinduque · Explore the demo area'
                : 'Browse the simulated AbangQue fleet.',
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
          GlassPanel(
            padding: const EdgeInsets.all(6),
            child: SizedBox(
              height: 380,
              child: JeepneyMap(
                jeepneys: vehicles,
                onSelect: (v) => setState(() => _selectedId = v.id),
                focus: focus,
                config: mapConfig,
                tileProviderFactory: tileProviderFactory,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            modeText(
              context,
              'Tap a jeepney to inspect its fictional report. These are simulated locations, not official stops.',
              'Markers show last reported positions, not guaranteed current locations. Vehicles without coordinates appear only in the list.',
            ),
            style: TextStyle(fontSize: 12, color: JeepLinkColors.muted),
          ),
          if (selected != null) ...[
            const SizedBox(height: 14),
            GlassPanel(
              key: const ValueKey('selected-jeepney'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'SELECTED JEEPNEY',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Dismiss selection',
                        onPressed: () => setState(() => _selectedId = ''),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  Text(
                    selected.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  StatusBadge(
                    status: selected.status,
                    label: selected.statusLabel,
                  ),
                  const SizedBox(height: 10),
                  Text('${selected.freshnessLabel} · ETA unavailable'),
                  const SizedBox(height: 12),
                  PassengerButton(
                    onPressed: () => onSelect(selected),
                    icon: const Icon(Icons.info_outline_rounded),
                    label: const Text('View report details'),
                  ),
                ],
              ),
            ),
          ],
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
            message: 'Try another ID or choose All jeepneys.',
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
