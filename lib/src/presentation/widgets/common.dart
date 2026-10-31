import 'package:flutter/material.dart';

import '../../config/data_config.dart';
import '../../domain/jeepney.dart';
import '../../theme.dart';
import 'glass.dart';

/// Keeps action text in normal flow even at large accessibility font sizes.
class PassengerButton extends StatelessWidget {
  const PassengerButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.style,
  });
  final VoidCallback? onPressed;
  final Widget icon;
  final Widget label;
  final ButtonStyle? style;
  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: style,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 10),
          Flexible(child: label),
        ],
      ),
    ),
  );
}

class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key, this.dark = false, this.label});
  final bool dark;
  final String? label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: dark ? const Color(0xFFD5F4DF) : JeepLinkColors.paleGreen,
      borderRadius: BorderRadius.circular(30),
      border: Border.all(
        color: dark ? Colors.white38 : const Color(0xFFD0E4DA),
      ),
    ),
    child: Text(
      label ?? modeText(context, 'DEMO', 'API'),
      style: const TextStyle(
        fontSize: 10,
        height: 1.2,
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
        color: JeepLinkColors.green,
      ),
    ),
  );
}

class DemoNotice extends StatelessWidget {
  const DemoNotice({super.key});
  @override
  Widget build(BuildContext context) => GlassPanel(
    radius: 20,
    padding: const EdgeInsets.all(14),
    tint: const Color(0xFFF2F5E8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 19,
          color: JeepLinkColors.green,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            modeText(
              context,
              'DEMO mode · Fictional locations and manual-status examples. No verified GPS tracking.',
              'Last reported data · Historical DEMO records are not current reports. Check freshness before travelling.',
            ),
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: JeepLinkColors.ink,
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
  Widget build(BuildContext context) =>
      GlassPanel(padding: padding, child: child);
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.label});
  final OccupancyStatus status;
  final String? label;
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      OccupancyStatus.available => JeepLinkColors.green,
      OccupancyStatus.full => JeepLinkColors.amber,
      OccupancyStatus.unknown => JeepLinkColors.muted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        border: Border.all(color: color.withValues(alpha: .16)),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            switch (status) {
              OccupancyStatus.available => Icons.check_circle_outline_rounded,
              OccupancyStatus.full => Icons.do_not_disturb_on_outlined,
              OccupancyStatus.unknown => Icons.help_outline_rounded,
            },
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label ?? status.name.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String etaText(Jeepney jeepney) => 'ETA unavailable';
String reportTime(DateTime? date) {
  if (date == null) return 'Not reported';
  final utc = date.toUtc();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${utc.day} ${months[utc.month - 1]} ${utc.year} · ${pad(utc.hour)}:${pad(utc.minute)} UTC';
}

class JeepneyCard extends StatelessWidget {
  const JeepneyCard({super.key, required this.jeepney, required this.onTap});
  final Jeepney jeepney;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Details for ${jeepney.name}',
    child: GlassPanel(
      key: ValueKey('vehicle-${jeepney.id}'),
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(17),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFD4EFDF), Color(0xFFEFF8EC)],
                  ),
                  border: Border.all(color: Colors.white),
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
                    const SizedBox(height: 3),
                    Text(
                      jeepney.sourceLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.north_east_rounded,
                size: 18,
                color: JeepLinkColors.muted,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusBadge(status: jeepney.status, label: jeepney.statusLabel),
              Text(
                jeepney.freshnessLabel,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            jeepney.fromApi
                ? 'Status is manually reported by the driver.'
                : 'DEMO example of a driver-selected status.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Divider(height: 28),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 16,
                color: JeepLinkColors.muted,
              ),
              Text(
                etaText(jeepney),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
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
  Widget build(BuildContext context) => GlassPanel(
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: JeepLinkColors.paleGreen,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.travel_explore_rounded,
            size: 32,
            color: JeepLinkColors.green,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (action != null)
          Padding(padding: const EdgeInsets.only(top: 16), child: action!),
      ],
    ),
  );
}
