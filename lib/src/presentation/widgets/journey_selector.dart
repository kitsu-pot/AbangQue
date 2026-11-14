import 'package:flutter/material.dart';

import '../../config/data_config.dart';
import '../../domain/passenger_route.dart';
import '../../theme.dart';
import '../jeepney_controller.dart';
import 'common.dart';
import 'glass.dart';

class JourneySelector extends StatelessWidget {
  const JourneySelector({super.key, required this.controller, this.onFind});
  final JeepneyController controller;
  final VoidCallback? onFind;
  Widget _field({required bool from}) {
    final value = from ? controller.origin : controller.destination;
    return DropdownButtonFormField<Municipality>(
      key: ValueKey('${from ? 'from' : 'to'}-${value?.name}'),
      initialValue: value,
      isExpanded: true,
      menuMaxHeight: 360,
      decoration: InputDecoration(
        labelText: from ? 'From municipality' : 'To municipality',
      ),
      hint: const Text('Choose municipality'),
      items: [
        for (final municipality in Municipality.values)
          DropdownMenuItem(
            value: municipality,
            child: Text(municipality.label),
          ),
      ],
      onChanged: from ? controller.setOrigin : controller.setDestination,
    );
  }

  @override
  Widget build(BuildContext context) => GlassPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.alt_route_rounded, color: JeepLinkColors.green),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Choose your journey',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (controller.hasSimulationRoutes)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'SIMULATED / DEMO test catalog · Not an operating route or real traffic.',
            ),
          ),
        Text(
          modeText(
            context,
            'DEMO UI preview · Municipality choices are not registered operating routes. No demo jeepneys are assigned.',
            'Choose a direction to look for administrator-registered routes. Municipality choices do not confirm service.',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final swap = GlassIconButton(
              icon: Icons.swap_vert_rounded,
              label: 'Swap origin and destination',
              onPressed:
                  controller.origin == null && controller.destination == null
                  ? null
                  : controller.swapJourney,
            );
            if (constraints.maxWidth >= 600 &&
                MediaQuery.textScalerOf(context).scale(1) < 1.5) {
              return Row(
                children: [
                  Expanded(child: _field(from: true)),
                  Padding(padding: const EdgeInsets.all(12), child: swap),
                  Expanded(child: _field(from: false)),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field(from: true),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Align(alignment: Alignment.centerRight, child: swap),
                ),
                _field(from: false),
              ],
            );
          },
        ),
        if (controller.origin != null &&
            controller.origin == controller.destination)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Choose two different municipalities.',
              style: TextStyle(color: JeepLinkColors.amber),
            ),
          ),
        const SizedBox(height: 20),
        PassengerButton(
          onPressed:
              controller.validJourney &&
                  (!controller.routesLoading || controller.routes.isNotEmpty) &&
                  controller.routesError == null
              ? () {
                  controller.findJeepneys();
                  onFind?.call();
                }
              : null,
          icon: const Icon(Icons.search_rounded),
          label: const Text('Find Jeepneys'),
        ),
      ],
    ),
  );
}

/// Never substitute all vehicles for an empty journey.
class JourneyState extends StatelessWidget {
  const JourneyState({super.key, required this.controller});
  final JeepneyController controller;
  @override
  Widget build(BuildContext context) {
    if (controller.routesLoading && controller.routes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: CircularProgressIndicator(
            semanticsLabel: 'Loading registered routes',
          ),
        ),
      );
    }
    if (controller.routesError != null) {
      return EmptyState(
        title: 'Routes unavailable',
        message: controller.routesError!,
        action: FilledButton(
          onPressed: controller.refreshing ? null : controller.refresh,
          child: const Text('Retry routes'),
        ),
      );
    }
    if (controller.routes.isEmpty) {
      return const EmptyState(
        title: 'No registered routes available yet.',
        message: 'Route records are not supplied by the current backend. Choose municipalities to plan a journey; jeepneys will appear only after routes and assignments are registered.',
      );
    }
    if (!controller.journeySubmitted) {
      return const EmptyState(
        title: 'Start with your journey',
        message: 'Choose your origin and destination, then tap Find Jeepneys.',
      );
    }
    if (controller.matchingRoutes.isEmpty) {
      return const EmptyState(
        title: 'No registered route for this direction',
        message: 'The reverse direction may be registered separately. No service is assumed.',
      );
    }
    if (controller.selectedRoute == null) {
      return GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose a registered route',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final route in controller.matchingRoutes)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: OutlinedButton(
                  onPressed: () => controller.selectRoute(route.id),
                  child: Text('${route.label} · ${route.id}'),
                ),
              ),
          ],
        ),
      );
    }
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            controller.selectedRoute!.isDemo
                ? 'SIMULATED / DEMO TEST DIRECTION'
                : controller.offline
                ? 'SAVED ROUTE · AVAILABILITY UNVERIFIED'
                : 'REGISTERED ROUTE',
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 1.2,
              color: JeepLinkColors.green,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            controller.selectedRoute!.label,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (!controller.offline && !controller.selectedRoute!.isDemo) ...[
            if (controller.selectedRoute!.originTerminal != null)
              Text(
                'Verified origin terminal: ${controller.selectedRoute!.originTerminal}',
              ),
            if (controller.selectedRoute!.destinationTerminal != null)
              Text(
                'Verified destination terminal: ${controller.selectedRoute!.destinationTerminal}',
              ),
            if (controller.selectedRoute!.boardingNotes != null)
              Text(
                'Verified boarding information: ${controller.selectedRoute!.boardingNotes}',
              ),
          ],
          Text(
            'Route ID: ${controller.selectedRoute!.id}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
