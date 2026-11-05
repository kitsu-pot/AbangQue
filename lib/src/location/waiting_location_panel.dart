import 'package:flutter/material.dart';

import '../presentation/widgets/common.dart';
import '../presentation/widgets/glass.dart';
import '../theme.dart';
import 'waiting_location.dart';

class WaitingLocationPanel extends StatelessWidget {
  const WaitingLocationPanel({
    super.key,
    required this.selected,
    required this.onDevice,
    required this.onMap,
    required this.onClear,
    this.onViewMap,
  });
  final WaitingLocation? selected;
  final VoidCallback onDevice, onMap, onClear;
  final VoidCallback? onViewMap;
  @override
  Widget build(BuildContext context) => GlassPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.person_pin_circle_outlined,
              color: JeepLinkColors.green,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Your waiting location',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (selected == null)
          const Text(
            'Optional · Browse routes and jeepneys without choosing a waiting point.',
          )
        else ...[
          const Text(
            'Waiting location selected',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            '${selected!.point.latitude.toStringAsFixed(6)}, ${selected!.point.longitude.toStringAsFixed(6)}',
          ),
          Text(selected!.sourceLabel),
          Text(selected!.accuracyLabel),
          Text('Selected: ${reportTime(selected!.selectedAt)}'),
          const SizedBox(height: 10),
          const Text(boardingLocationNotice),
        ],
        const SizedBox(height: 16),
        PassengerButton(
          onPressed: onDevice,
          icon: const Icon(Icons.my_location_rounded),
          label: const Text('Use My Location'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: onMap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(selected == null ? 'Choose on Map' : 'Change Location'),
          ),
        ),
        if (selected != null) ...[
          if (onViewMap != null)
            TextButton(
              onPressed: onViewMap,
              child: const Text('View waiting point on map'),
            ),
          TextButton(onPressed: onClear, child: const Text('Clear Location')),
        ],
        const SizedBox(height: 8),
        const Text(
          'This app session only · Not saved to your account. ETA unavailable.',
          style: TextStyle(fontSize: 12, color: JeepLinkColors.muted),
        ),
      ],
    ),
  );
}
