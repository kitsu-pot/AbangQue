import '../jeepney_controller.dart';

import 'package:flutter/material.dart';

import '../../data/demo_jeepney_repository.dart';
import '../../domain/jeepney.dart';
import '../../theme.dart';
import 'common.dart';

Future<void> showJeepneyDetails(
  BuildContext context,
  Jeepney jeepney,
  ValueChanged<Jeepney> onViewMap,
  JeepneyController controller,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: JeepLinkColors.background,
  constraints: const BoxConstraints(maxWidth: 600),
  builder: (context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final current = controller.vehicles
          .where((v) => v.id == jeepney.id)
          .firstOrNull;
      if (current == null) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: EmptyState(
            title: 'Vehicle data unavailable',
            message:
                controller.error ??
                'This vehicle is no longer in the latest snapshot.',
            action: FilledButton(
              onPressed: controller.refreshing ? null : controller.refresh,
              child: const Text('Try again'),
            ),
          ),
        );
      }
      return _detailsContent(context, current, onViewMap);
    },
  ),
);

Widget _detailsContent(
  BuildContext context,
  Jeepney jeepney,
  ValueChanged<Jeepney> onViewMap,
) => SingleChildScrollView(
  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          DemoBadge(label: jeepney.source == DataSource.demo ? 'DEMO' : 'API'),
          const Spacer(),
          IconButton(
            tooltip: 'Close details',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      Text(jeepney.name, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 5),
      Text(
        '${jeepney.id} · ${jeepney.sourceLabel}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 18),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          StatusBadge(status: jeepney.status, label: jeepney.statusLabel),
          Text(
            jeepney.availableSeats == null
                ? 'Seat count unknown'
                : '${jeepney.availableSeats} of ${jeepney.capacity} seats open',
          ),
        ],
      ),
      const SizedBox(height: 18),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              jeepney.fromApi ? 'ETA' : 'DEMO ETA',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              etaText(jeepney),
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            if (!jeepney.fromApi)
              const Text('To ${DemoScenario.referenceLabel}'),
            const SizedBox(height: 6),
            Text(
              jeepney.fromApi
                  ? 'ETA unavailable. The backend does not calculate arrivals yet.'
                  : 'An illustrative estimate, not a prediction of an actual arrival.',
              style: TextStyle(fontSize: 12, color: JeepLinkColors.muted),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      if (!jeepney.fromApi) ...[
        Text(
          'Simulated passenger occupancy',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: jeepney.passengerCount! / jeepney.capacity!,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
          color: jeepney.status == OccupancyStatus.full
              ? JeepLinkColors.amber
              : JeepLinkColors.green,
          backgroundColor: JeepLinkColors.line,
          semanticsLabel:
              'Simulated occupancy, ${jeepney.passengerCount} of ${jeepney.capacity} seats occupied',
        ),
        const SizedBox(height: 8),
        Text('${jeepney.passengerCount} / ${jeepney.capacity} seats occupied'),
        if (jeepney.status == OccupancyStatus.full)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'This sample jeepney is full. Explore an AVAILABLE jeepney.',
              style: TextStyle(color: JeepLinkColors.amber),
            ),
          ),
        const SizedBox(height: 18),
      ],
      const Divider(),
      const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.alt_route_rounded),
        title: Text('No official route assigned'),
        subtitle: Text('Routes and stops have not been verified.'),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.location_on_outlined),
        title: Text(
          jeepney.fromApi
              ? 'Last reported coordinates'
              : 'Simulated coordinates',
        ),
        subtitle: Text(
          jeepney.position == null
              ? 'Location unavailable'
              : '${jeepney.position!.latitude.toStringAsFixed(5)}, ${jeepney.position!.longitude.toStringAsFixed(5)}',
        ),
      ),
      if (jeepney.fromApi)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Connection: ${jeepney.connectionStatus}'),
          subtitle: Text(
            'Measured: ${jeepney.recordedAt?.toUtc().toIso8601String() ?? 'Unknown'}\nLast seen: ${jeepney.lastSeenAt?.toUtc().toIso8601String() ?? 'Unknown'}',
          ),
        ),
      const DemoNotice(),
      const SizedBox(height: 18),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: jeepney.position == null
              ? null
              : () {
                  Navigator.pop(context);
                  onViewMap(jeepney);
                },
          icon: const Icon(Icons.map_outlined),
          label: Text(
            jeepney.fromApi ? 'View last location on map' : 'View on demo map',
          ),
        ),
      ),
      SizedBox(height: MediaQuery.paddingOf(context).bottom),
    ],
  ),
);
