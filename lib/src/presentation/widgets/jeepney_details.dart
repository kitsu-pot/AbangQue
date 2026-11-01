import 'package:flutter/material.dart';

import '../../domain/jeepney.dart';
import '../../theme.dart';
import '../jeepney_controller.dart';
import 'common.dart';
import 'glass.dart';

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
  backgroundColor: const Color(0xFFF1F7F1),
  constraints: const BoxConstraints(maxWidth: 600),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
  ),
  builder: (context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final current = controller.journeyVehicles
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
      return _Details(
        jeepney: current,
        onViewMap: onViewMap,
        routeLabel: controller.selectedRoute!.label,
      );
    },
  ),
);

class _Details extends StatelessWidget {
  const _Details({
    required this.jeepney,
    required this.onViewMap,
    required this.routeLabel,
  });
  final Jeepney jeepney;
  final String routeLabel;
  final ValueChanged<Jeepney> onViewMap;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      22,
      0,
      22,
      24 + MediaQuery.paddingOf(context).bottom,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            DemoBadge(
              label: jeepney.source == DataSource.demo
                  ? 'DEMO'
                  : 'DRIVER REPORT',
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Close details',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(jeepney.name, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(jeepney.sourceLabel, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 24),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MANUALLY REPORTED STATUS',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                  color: JeepLinkColors.muted,
                ),
              ),
              const SizedBox(height: 14),
              StatusBadge(status: jeepney.status, label: jeepney.statusLabel),
              const SizedBox(height: 14),
              Text(
                jeepney.fromApi
                    ? 'FULL or AVAILABLE is selected by the driver. An old or missing report remains unknown.'
                    : 'DEMO only. This example represents a driver-selected status.',
              ),
              const SizedBox(height: 12),
              Text(
                jeepney.freshnessLabel,
                style: const TextStyle(
                  color: JeepLinkColors.green,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const GlassPanel(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.schedule_rounded, color: JeepLinkColors.green),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ETA unavailable',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Arrival estimates are not implemented. No arrival time is guaranteed.',
                      style: TextStyle(
                        fontSize: 12,
                        color: JeepLinkColors.muted,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _Info(
          icon: Icons.update_rounded,
          title: jeepney.fromApi ? 'Last communication' : 'DEMO snapshot time',
          value: reportTime(
            jeepney.fromApi ? jeepney.lastSeenAt : jeepney.recordedAt,
          ),
        ),
        _Info(
          icon: Icons.history_rounded,
          title: 'Measurement time',
          value: reportTime(jeepney.recordedAt),
        ),
        _Info(
          icon: Icons.location_on_outlined,
          title: 'Last reported coordinates',
          value: jeepney.position == null
              ? 'Location unavailable'
              : '${jeepney.position!.latitude.toStringAsFixed(5)}, ${jeepney.position!.longitude.toStringAsFixed(5)}',
        ),
        _Info(
          icon: Icons.alt_route_rounded,
          title: 'Registered route',
          value: routeLabel,
        ),
        const Text('Stops and schedules are not supplied.'),
        const SizedBox(height: 12),
        const DemoNotice(),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: PassengerButton(
            onPressed: jeepney.position == null
                ? null
                : () {
                    Navigator.pop(context);
                    onViewMap(jeepney);
                  },
            icon: const Icon(Icons.map_outlined),
            label: const Text('View last location on map'),
          ),
        ),
      ],
    ),
  );
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.title, required this.value});
  final IconData icon;
  final String title;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: JeepLinkColors.muted, size: 21),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}
