import '../../config/data_config.dart';

import 'package:flutter/material.dart';

import '../../domain/jeepney.dart';
import '../../theme.dart';

class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key, this.dark = false, this.label});
  final bool dark;
  final String? label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: dark ? JeepLinkColors.lime : JeepLinkColors.paleAmber,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      label ?? modeText(context, 'DEMO', 'API'),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: dark ? JeepLinkColors.ink : JeepLinkColors.amber,
      ),
    ),
  );
}

class DemoNotice extends StatelessWidget {
  const DemoNotice({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: JeepLinkColors.paleAmber,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.science_outlined, size: 20, color: JeepLinkColors.amber),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            modeText(
              context,
              'DEMO only. Locations, seats, and ETAs are simulated. No live tracking or official routes.',
              'API data. Historical DEMO records are not current availability. Stale or unknown status is not a seat guarantee. ETA unavailable.',
            ),
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: JeepLinkColors.amber,
            ),
          ),
        ),
      ],
    ),
  );
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: JeepLinkColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.label});
  final OccupancyStatus status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final full = status == OccupancyStatus.full;
    final unknown = status == OccupancyStatus.unknown;
    final color = unknown
        ? JeepLinkColors.muted
        : full
        ? JeepLinkColors.amber
        : JeepLinkColors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: unknown
            ? JeepLinkColors.line
            : full
            ? JeepLinkColors.paleAmber
            : JeepLinkColors.paleGreen,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            unknown
                ? Icons.help_outline
                : full
                ? Icons.do_not_disturb_on_rounded
                : Icons.check_circle_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            label ?? status.name.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: .4,
            ),
          ),
        ],
      ),
    );
  }
}

String etaText(Jeepney jeepney) => jeepney.eta == null || jeepney.isStale
    ? 'Unavailable'
    : '${jeepney.eta!.inMinutes} min';

class JeepneyCard extends StatelessWidget {
  const JeepneyCard({super.key, required this.jeepney, required this.onTap});
  final Jeepney jeepney;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Details for ${jeepney.name}',
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: JeepLinkColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('vehicle-${jeepney.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: JeepLinkColors.paleGreen,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.airport_shuttle_rounded,
                      color: JeepLinkColors.green,
                      size: 27,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          jeepney.id,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          jeepney.sourceLabel,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: JeepLinkColors.muted,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusBadge(
                    status: jeepney.status,
                    label: jeepney.statusLabel,
                  ),
                  Text(
                    jeepney.availableSeats == null
                        ? 'Seat count unknown'
                        : '${jeepney.availableSeats} seats open',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
              Row(
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    size: 16,
                    color: JeepLinkColors.green,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      jeepney.fromApi ? 'ETA' : 'DEMO ETA',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    etaText(jeepney),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: JeepLinkColors.green,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    this.action,
    this.onAction,
  });
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
    ],
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.action,
  });
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Center(
      child: Column(
        children: [
          const Icon(
            Icons.travel_explore_rounded,
            size: 38,
            color: JeepLinkColors.muted,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          if (action != null)
            Padding(padding: const EdgeInsets.only(top: 12), child: action!),
        ],
      ),
    ),
  );
}
