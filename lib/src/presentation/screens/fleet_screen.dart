import '../../config/data_config.dart';

import 'package:flutter/material.dart';

import '../../domain/jeepney.dart';
import '../../theme.dart';
import '../jeepney_controller.dart';
import '../widgets/common.dart';
import '../widgets/journey_selector.dart';

class FleetScreen extends StatelessWidget {
  const FleetScreen({
    super.key,
    required this.controller,
    required this.onSelect,
    this.waitingPanel,
    this.onFind,
  });
  final JeepneyController controller;
  final ValueChanged<Jeepney> onSelect;
  final Widget? waitingPanel;
  final VoidCallback? onFind;

  @override
  Widget build(BuildContext context) {
    final vehicles = controller.filteredVehicles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Jeepneys for your journey.',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 7),
        Text(
          modeText(
            context,
            'DEMO route-selection preview · No assigned jeepneys.',
            'Choose a registered direction to view assigned jeepneys.',
          ),
          style: const TextStyle(color: JeepLinkColors.muted),
        ),
        const SizedBox(height: 20),
        const DemoNotice(),
        const SizedBox(height: 18),
        if (!controller.journeySubmitted)
          JourneySelector(controller: controller, onFind: onFind)
        else ...[
          Text(
            '${controller.origin!.label} → ${controller.destination!.label}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: controller.editJourney,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Change journey'),
          ),
        ],
        const SizedBox(height: 18),
        JourneyState(controller: controller),
        if (waitingPanel != null) ...[
          const SizedBox(height: 18),
          waitingPanel!,
        ],
        const SizedBox(height: 18),
        if (controller.selectedRoute != null) ...[
          TextFormField(
            key: ValueKey('fleet-search-${controller.selectedRoute!.id}'),
            initialValue: controller.query,
            onChanged: controller.setQuery,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Search this route',
              hintText: 'Jeepney ID or name',
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (controller.selectedRoute != null) ...[
          Text(
            '${vehicles.length} jeepneys on this route',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (vehicles.isEmpty)
            EmptyState(
              title: controller.query.trim().isEmpty
                  ? 'No jeepney reports for this route yet'
                  : 'No matching jeepneys',
              message: controller.query.trim().isEmpty
                  ? 'No assigned jeepney reports are available. Try refreshing later.'
                  : 'Try another ID or name within your selected route.',
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
                        routeLabel: controller.selectedRoute!.label,
                        onTap: () => onSelect(vehicle),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
