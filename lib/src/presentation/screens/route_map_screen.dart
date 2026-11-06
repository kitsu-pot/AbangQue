import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../config/data_config.dart';
import '../../config/map_config.dart';
import '../../domain/jeepney.dart';
import '../../location/waiting_location_controller.dart';
import '../../theme.dart';
import '../jeepney_controller.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/jeepney_map.dart';
import '../widgets/journey_selector.dart';

/// Full viewport presentation of the existing route/controller/map contracts.
class RouteMapScreen extends StatefulWidget {
  const RouteMapScreen({
    super.key,
    required this.controller,
    required this.waiting,
    required this.onFind,
    required this.onLocate,
    required this.onWaitingOptions,
    required this.onDetails,
    required this.mapConfig,
    this.tileProviderFactory,
  });
  final JeepneyController controller;
  final WaitingLocationController waiting;
  final VoidCallback onFind, onLocate, onWaitingOptions;
  final ValueChanged<Jeepney> onDetails;
  final MapConfig mapConfig;
  final TileProviderFactory? tileProviderFactory;
  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  final _sheet = DraggableScrollableController();
  double? _extent;
  double _min = .18, _mid = .4, _max = .72;
  JeepneyController get c => widget.controller;
  String get direction => c.origin != null && c.destination != null
      ? '${c.origin!.label} → ${c.destination!.label}'
      : 'Choose your journey';

  Future<void> _changeRoute() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => AnimatedBuilder(
      animation: c,
      builder: (_, _) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          24,
          16,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            JourneySelector(
              controller: c,
              onFind: () {
                Navigator.pop(sheetContext);
                widget.onFind();
              },
            ),
            if (c.routesError != null || c.routesLoading)
              JourneyState(controller: c),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    ),
  );

  void _size(double value) {
    if (!_sheet.isAttached) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _sheet.jumpTo(value);
    } else {
      unawaited(
        _sheet.animateTo(
          value,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  void _select(Jeepney jeepney) {
    c.selectJeepney(jeepney);
    _size(_mid);
  }

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final large = MediaQuery.textScalerOf(context).scale(1) > 1.5;
        final top = large ? 184.0 : 128.0;
        final height = constraints.maxHeight;
        _min = ((large ? 148 : 110) / height).clamp(.14, .33);
        _max = (1 - (top + 116) / height).clamp(_min + .12, .76);
        _mid = (_min + .20).clamp(_min, _max);
        final extent = (_extent ?? (c.selectedJeepney != null ? _mid : _min))
            .clamp(_min, _max);
        final selected = c.selectedJeepney;
        final vehicles = c.filteredVehicles;
        final source = c.hasSimulationRoutes
            ? 'SIMULATED / DEMO · Not real traffic'
            : modeText(
                context,
                'OFFLINE DEMO · Fictional reports',
                'API · Last reported positions',
              );
        return Stack(
          key: const ValueKey('route-map-viewport'),
          children: [
            Positioned.fill(
              child: JeepneyMap(
                jeepneys: vehicles,
                onSelect: _select,
                focus: selected,
                waitingPoint: widget.waiting.selected?.point,
                fullScreen: true,
                overlayPadding: EdgeInsets.only(
                  top: top,
                  bottom: height * extent + 28,
                ),
                onLocate: widget.onLocate,
                config: widget.mapConfig,
                tileProviderFactory: widget.tileProviderFactory,
              ),
            ),
            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: GlassPanel(
                padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                radius: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (!large)
                          const Icon(
                            Icons.airport_shuttle_rounded,
                            color: JeepLinkColors.green,
                            size: 20,
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'AbangQue',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: large ? 14 : 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: modeText(
                            context,
                            'Refresh demo',
                            'Refresh API',
                          ),
                          onPressed: c.refreshing ? null : c.refresh,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                        IconButton(
                          tooltip: 'Waiting location options',
                          onPressed: widget.onWaitingOptions,
                          icon: const Icon(Icons.more_horiz_rounded),
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: _changeRoute,
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Row(
                          children: [
                            const Icon(Icons.alt_route_rounded, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                direction,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Change journey',
                              onPressed: _changeRoute,
                              icon: const Icon(Icons.expand_more_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // A small message never prevents map use or opens a blocking dialog.
            if (widget.waiting.locating ||
                widget.waiting.failure != null ||
                widget.waiting.selected?.lowAccuracy == true ||
                widget.waiting.selected?.isMocked == true)
              Positioned(
                top: top + 18,
                left: 12,
                right: 76,
                child: GlassPanel(
                  radius: 16,
                  padding: const EdgeInsets.all(10),
                  child: InkWell(
                    onTap: widget.onWaitingOptions,
                    child: Text(
                      widget.waiting.locating
                          ? 'Finding your location…'
                          : widget.waiting.failure != null
                          ? 'Location unavailable · Choose on map or open settings'
                          : widget.waiting.selected!.isMocked
                          ? 'DEMO / Mock passenger location'
                          : 'Low accuracy · Check your waiting pin',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
            NotificationListener<DraggableScrollableNotification>(
              onNotification: (notification) {
                if ((_extent ?? _min) != notification.extent) {
                  setState(() => _extent = notification.extent);
                }
                return true;
              },
              child: DraggableScrollableSheet(
                key: const ValueKey('jeepney-sheet'),
                controller: _sheet,
                initialChildSize: selected != null ? _mid : _min,
                minChildSize: _min,
                maxChildSize: _max,
                snap: true,
                snapSizes: {_min, _mid, _max}.toList()..sort(),
                builder: (context, scroll) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: GlassPanel(
                    radius: 28,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        GestureDetector(
                          key: const ValueKey('sheet-handle'),
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragUpdate: (drag) {
                            if (_sheet.isAttached) {
                              _sheet.jumpTo(
                                (_sheet.size - drag.delta.dy / height).clamp(
                                  _min,
                                  _max,
                                ),
                              );
                            }
                          },
                          onVerticalDragEnd: (_) {
                            final stops = [_min, _mid, _max]
                              ..sort(
                                (a, b) => (a - _sheet.size).abs().compareTo(
                                  (b - _sheet.size).abs(),
                                ),
                              );
                            _size(stops.first);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Semantics(
                                  label: 'Drag to expand or collapse jeepney results',
                                  child: Center(
                                    child: Container(
                                      margin: const EdgeInsets.only(top: 10),
                                      width: 36,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: JeepLinkColors.muted.withValues(
                                          alpha: .4,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        direction,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: extent > _min + .02
                                          ? 'Collapse jeepney panel'
                                          : 'Expand jeepney panel',
                                      onPressed: () => _size(
                                        extent > _min + .02 ? _min : _mid,
                                      ),
                                      icon: Icon(
                                        extent > _min + .02
                                            ? Icons.keyboard_arrow_down
                                            : Icons.keyboard_arrow_up,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Expand full jeepney list',
                                      onPressed: () => _size(_max),
                                      icon: const Icon(
                                        Icons.unfold_more_rounded,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '${vehicles.length} jeepneys · ${c.apiMode && !c.hasSimulationRoutes ? 'API' : 'DEMO'}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 12),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            controller: scroll,
                            scrollCacheExtent: const ScrollCacheExtent.pixels(
                              1200,
                            ),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                            children: [
                              if (selected != null) ...[
                                const SizedBox(height: 10),
                                GlassPanel(
                                  key: const ValueKey('selected-jeepney'),
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        selected.id,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      StatusBadge(
                                        status: selected.status,
                                        label: selected.statusLabel,
                                      ),
                                      Text(selected.sourceLabel),
                                      Text(selected.connectivityLabel),
                                      Text(
                                        'Last GPS update: ${reportTime(selected.recordedAt)}',
                                      ),
                                      const Text(
                                        'Driver-reported status · ETA unavailable',
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            widget.onDetails(selected),
                                        child: const Text(
                                          'View report details',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              Text(
                                source,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: JeepLinkColors.green,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (c.loading || c.refreshing)
                                const LinearProgressIndicator(
                                  semanticsLabel: 'Loading jeepney reports',
                                ),
                              if (c.error != null) ...[
                                const Text('Unable to update the fleet'),
                                TextButton(
                                  onPressed: c.refresh,
                                  child: const Text('Try again'),
                                ),
                              ],
                              if (c.selectedRoute == null)
                                JourneyState(controller: c),
                              if (c.selectedRoute != null) ...[
                                const SizedBox(height: 12),
                                TextFormField(
                                  key: ValueKey(
                                    'map-search-${c.selectedRoute!.id}',
                                  ),
                                  initialValue: c.query,
                                  onChanged: c.setQuery,
                                  decoration: const InputDecoration(
                                    labelText: 'Search this route',
                                    prefixIcon: Icon(Icons.search_rounded),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (vehicles.isEmpty &&
                                    !c.loading &&
                                    c.error == null)
                                  Text(
                                    c.query.isEmpty
                                        ? 'No jeepney reports for this route yet'
                                        : 'No matching jeepneys',
                                  ),
                                for (final vehicle in vehicles)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: GlassPanel(
                                      key: ValueKey('vehicle-${vehicle.id}'),
                                      padding: const EdgeInsets.all(12),
                                      onTap: () => _select(vehicle),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            vehicle.id,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          Text(
                                            c.selectedRoute!.label,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          StatusBadge(
                                            status: vehicle.status,
                                            label: vehicle.statusLabel,
                                          ),
                                          Text(
                                            vehicle.sourceLabel,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            '${vehicle.freshnessLabel} · ${reportTime(vehicle.recordedAt)}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                          if (vehicle.position == null)
                                            const Text(
                                              'GPS location unavailable',
                                            ),
                                          const Text(
                                            'ETA unavailable',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                              TextButton(
                                onPressed: widget.onWaitingOptions,
                                child: const Text('Waiting location options'),
                              ),
                              const Text(
                                'Blue pin: passenger reference only. Boarding depends on actual routes and operating practices.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
