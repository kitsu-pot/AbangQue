import 'package:flutter/material.dart';

import '../../theme.dart';
import '../jeepney_controller.dart';
import 'common.dart';
import 'glass.dart';

/// The API proves reachability; network-interface status never does.
class ConnectionNotice extends StatelessWidget {
  const ConnectionNotice({
    super.key,
    required this.controller,
    required this.onRetry,
    this.compact = false,
  });
  final JeepneyController controller;
  final VoidCallback onRetry;
  final bool compact;
  String get times => [
    if (controller.routeState?.receivedAt != null)
      'Routes received: ${reportTime(controller.routeState!.receivedAt)}',
    if (controller.fleetState?.receivedAt != null)
      'Reports received: ${reportTime(controller.fleetState!.receivedAt)}',
  ].join('\n');
  String get explanation => controller.offline
      ? controller.hasPublicSnapshot
            ? 'Showing the last available information. Jeepney locations and availability may have changed. Current availability is UNKNOWN; ETA unavailable.'
            : 'We cannot reach the API. There is no saved information to show yet. You can choose municipalities and retry.'
      : 'The last API requests succeeded. Report freshness is checked separately; an old report does not become fresh when downloaded.';
  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              controller.offline
                  ? Icons.cloud_off_rounded
                  : Icons.cloud_done_outlined,
              color: JeepLinkColors.green,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  useSafeArea: true,
                  isScrollControlled: true,
                  builder: (context) => SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          controller.connectionLabel,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        Text(explanation),
                        const SizedBox(height: 12),
                        Text(times),
                        const SizedBox(height: 12),
                        const Text(
                          'Received time is when the app fetched a dataset. GPS measurement and device communication times are unchanged in report details. Saved routes may no longer be active. Map tiles may be missing without internet.',
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                ),
                child: Semantics(
                  button: true,
                  label: 'Connection details',
                  child: Text(
                    controller.connectionLabel,
                    key: const ValueKey('connection-label'),
                    maxLines: compact ? 2 : null,
                    overflow: compact ? TextOverflow.ellipsis : null,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Retry connection',
              onPressed: controller.refreshing ? null : onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
        if (times.isNotEmpty)
          Text(
            times,
            maxLines: compact ? 1 : null,
            overflow: compact ? TextOverflow.ellipsis : null,
            style: const TextStyle(fontSize: 11, color: JeepLinkColors.muted),
          ),
        if (!compact && controller.offline) ...[
          const SizedBox(height: 6),
          Text(explanation, style: const TextStyle(fontSize: 12)),
        ],
        if (controller.cacheWarning && !compact)
          const Text(
            'Device cache unavailable. These reports may not be available after restarting.',
            style: TextStyle(fontSize: 12),
          ),
      ],
    );
    return compact
        ? content
        : GlassPanel(
            padding: const EdgeInsets.all(14),
            radius: 20,
            child: content,
          );
  }
}
