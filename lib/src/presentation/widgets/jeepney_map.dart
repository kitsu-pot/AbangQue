import '../../config/data_config.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/map_config.dart';
import '../../data/demo_jeepney_repository.dart';
import '../../domain/jeepney.dart';
import '../../theme.dart';
import 'glass.dart';

typedef TileProviderFactory = TileProvider Function();

class JeepneyMap extends StatefulWidget {
  const JeepneyMap({
    super.key,
    required this.jeepneys,
    required this.onSelect,
    this.interactive = true,
    this.focus,
    this.config = const MapConfig(),
    this.tileProviderFactory,
    this.waitingPoint,
    this.onWaitingPointTap,
    this.pickingWaitingLocation = false,
  });

  final List<Jeepney> jeepneys;
  final ValueChanged<Jeepney> onSelect;
  final bool interactive;
  final Jeepney? focus;
  final MapConfig config;
  final TileProviderFactory? tileProviderFactory;
  final GeoPoint? waitingPoint;
  final ValueChanged<GeoPoint>? onWaitingPointTap;
  final bool pickingWaitingLocation;

  @override
  State<JeepneyMap> createState() => _JeepneyMapState();
}

class _JeepneyMapState extends State<JeepneyMap> {
  final _controller = MapController();
  late TileProvider _tileProvider;
  bool _tileError = false;
  int _tileRevision = 0;
  bool _showBoth = false;

  @override
  void initState() {
    super.initState();
    _tileProvider = widget.tileProviderFactory?.call() ?? NetworkTileProvider();
  }

  LatLng _latLng(GeoPoint point) => LatLng(point.latitude, point.longitude);

  @override
  void didUpdateWidget(covariant JeepneyMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.waitingPoint != oldWidget.waitingPoint &&
        widget.waitingPoint != null) {
      if (_showBoth && widget.focus?.position != null) {
        _fitBoth();
      } else {
        _controller.move(_latLng(widget.waitingPoint!), 15.5);
      }
    }
    if (widget.focus?.position != null &&
        (widget.focus?.id != oldWidget.focus?.id ||
            widget.focus?.position?.latitude !=
                oldWidget.focus?.position?.latitude ||
            widget.focus?.position?.longitude !=
                oldWidget.focus?.position?.longitude)) {
      if (_showBoth && widget.waitingPoint != null) {
        _fitBoth();
      } else {
        _controller.move(
          _latLng(widget.focus!.position!),
          widget.focus?.id != oldWidget.focus?.id
              ? 15.5
              : _controller.camera.zoom,
        );
      }
    }
  }

  void _fitBoth() {
    final waiting = widget.waitingPoint;
    final vehicle = widget.focus?.position;
    if (waiting == null || vehicle == null) return;
    _showBoth = true;
    _controller.fitCamera(
      CameraFit.coordinates(
        coordinates: [_latLng(waiting), _latLng(vehicle)],
        padding: const EdgeInsets.fromLTRB(54, 70, 70, 60),
        maxZoom: 16,
        minZoom: 1,
      ),
    );
  }

  void _onTileError() {
    if (_tileError) return;
    _tileError = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _retry() => setState(() {
    _tileError = false;
    _tileRevision++;
    _tileProvider = widget.tileProviderFactory?.call() ?? NetworkTileProvider();
  });

  Future<void> _openAttribution() async {
    var opened = false;
    try {
      opened = await launchUrl(Uri.parse(widget.config.attributionUrl));
    } catch (_) {
      // Surface launch failures rather than silently ignoring the action.
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Map credits: ${widget.config.attributionUrl}')),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    // TileLayer owns and disposes its tile provider.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(22),
    child: Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: _latLng(
              widget.focus?.position ??
                  widget.waitingPoint ??
                  DemoScenario.center,
            ),
            initialZoom: widget.focus == null ? 14.8 : 15.5,
            minZoom: 1,
            maxZoom: 18,
            backgroundColor: const Color(0xFFE8EEE2),
            onTap: widget.onWaitingPointTap == null
                ? null
                : (_, point) => widget.onWaitingPointTap!(
                    GeoPoint(point.latitude, point.longitude),
                  ),
            onPositionChanged: (_, hasGesture) {
              if (hasGesture) _showBoth = false;
            },
            interactionOptions: InteractionOptions(
              flags: widget.interactive
                  ? InteractiveFlag.all & ~InteractiveFlag.rotate
                  : InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              key: ValueKey(_tileRevision),
              urlTemplate: widget.config.tileUrl,
              userAgentPackageName: widget.config.userAgentPackageName,
              tileProvider: _tileProvider,
              // Request only tiles in the visible map viewport.
              panBuffer: 0,
              maxNativeZoom: 19,
              errorTileCallback: (_, _, _) => _onTileError(),
            ),
            MarkerLayer(
              markers: [
                if (widget.waitingPoint != null)
                  Marker(
                    point: _latLng(widget.waitingPoint!),
                    width: 52,
                    height: 60,
                    child: Tooltip(
                      message: widget.pickingWaitingLocation
                          ? 'Waiting point preview · Not yet confirmed'
                          : 'Selected waiting location · Reference only',
                      child: Semantics(
                        label: 'Passenger waiting location, reference only',
                        child: Container(
                          key: const ValueKey('passenger-waiting-marker'),
                          decoration: BoxDecoration(
                            color: const Color(0xFF185D87),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 5),
                            ],
                          ),
                          child: const Icon(
                            Icons.person_pin_circle_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                  ),
                for (final jeepney in widget.jeepneys.where(
                  (v) => v.position != null,
                ))
                  Marker(
                    point: _latLng(jeepney.position!),
                    width: 76,
                    height: 60,
                    child: Tooltip(
                      message:
                          '${jeepney.id} • ${jeepney.statusLabel} • ${jeepney.sourceLabel}',
                      child: Semantics(
                        button: true,
                        label:
                            '${jeepney.name}, ${jeepney.statusLabel}, ${jeepney.sourceLabel}, last reported location',
                        child: Material(
                          color: jeepney.status == OccupancyStatus.unknown
                              ? JeepLinkColors.muted
                              : jeepney.status == OccupancyStatus.full
                              ? JeepLinkColors.amber
                              : JeepLinkColors.green,
                          elevation: 3,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            key: ValueKey('marker-${jeepney.id}'),
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => widget.onSelect(jeepney),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.airport_shuttle_rounded,
                                  color: Colors.white,
                                  size: 25,
                                ),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '${jeepney.isSimulated ? 'SIM' : jeepney.id.split('-').last} · ${jeepney.statusLabel}',
                                    maxLines: 1,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 9,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 72,
          child: Align(
            alignment: Alignment.topLeft,
            child: GlassPanel(
              radius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              child: Text(
                widget.pickingWaitingLocation
                    ? 'WAITING PIN PREVIEW'
                    : widget.waitingPoint != null
                    ? (widget.jeepneys.any((v) => v.isSimulated)
                          ? 'BLUE: WAITING · BUS: SIMULATED / DEMO'
                          : widget.jeepneys.any(
                              (v) => v.source == DataSource.demo,
                            )
                          ? 'BLUE: WAITING · BUS: DEMO REPORT'
                          : 'BLUE: WAITING · BUS: LAST REPORT')
                    : widget.jeepneys.any((v) => v.isSimulated)
                    ? 'SIMULATED / DEMO LOCATIONS'
                    : modeText(
                        context,
                        'DEMO LOCATIONS',
                        'LAST REPORTED LOCATIONS',
                      ),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                  color: JeepLinkColors.ink,
                ),
              ),
            ),
          ),
        ),
        if (_tileError)
          Positioned(
            bottom: 48,
            left: 12,
            right: 72,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: Material(
                  color: JeepLinkColors.paleAmber,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Map tiles unavailable. Check your connection.',
                          style: TextStyle(
                            fontSize: 12,
                            color: JeepLinkColors.amber,
                          ),
                        ),
                        TextButton(
                          onPressed: _retry,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (widget.interactive)
          Positioned(
            right: 12,
            bottom: 56,
            child: Column(
              children: [
                if (widget.waitingPoint != null) ...[
                  if (widget.focus?.position != null) ...[
                    _mapButton(
                      Icons.fit_screen_rounded,
                      'Show waiting point and selected jeepney',
                      _fitBoth,
                    ),
                    const SizedBox(height: 6),
                  ],
                  _mapButton(
                    Icons.person_pin_circle_outlined,
                    'Show waiting point',
                    () {
                      _showBoth = false;
                      _controller.move(_latLng(widget.waitingPoint!), 15.5);
                    },
                  ),
                  const SizedBox(height: 6),
                ],
                _mapButton(
                  Icons.add,
                  'Zoom in',
                  () => _controller.move(
                    _controller.camera.center,
                    (_controller.camera.zoom + 1).clamp(1, 18),
                  ),
                ),
                const SizedBox(height: 6),
                _mapButton(
                  Icons.remove,
                  'Zoom out',
                  () => _controller.move(
                    _controller.camera.center,
                    (_controller.camera.zoom - 1).clamp(1, 18),
                  ),
                ),
                const SizedBox(height: 6),
                _mapButton(
                  Icons.center_focus_strong_rounded,
                  'Reset to Boac area',
                  () {
                    _showBoth = false;
                    _controller.move(_latLng(DemoScenario.center), 14.8);
                  },
                ),
              ],
            ),
          ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Material(
            color: Colors.white,
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(10)),
            child: InkWell(
              onTap: _openAttribution,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Text(
                  widget.config.attribution,
                  style: const TextStyle(
                    fontSize: 11,
                    color: JeepLinkColors.ink,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _mapButton(IconData icon, String label, VoidCallback onPressed) =>
      GlassIconButton(icon: icon, label: label, onPressed: onPressed);
}
