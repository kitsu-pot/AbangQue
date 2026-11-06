import 'dart:async';

import 'package:flutter/material.dart';

import '../config/map_config.dart';
import '../domain/jeepney.dart';
import '../presentation/widgets/common.dart';
import '../presentation/widgets/glass.dart';
import '../presentation/widgets/jeepney_map.dart';
import 'device_location_service.dart';
import 'waiting_location.dart';

class WaitingLocationPicker extends StatefulWidget {
  const WaitingLocationPicker({
    super.key,
    required this.service,
    this.initial,
    this.requestDeviceLocation = false,
    this.mapConfig = const MapConfig(),
    this.tileProviderFactory,
  });
  final DeviceLocationService service;
  final WaitingLocation? initial;
  final bool requestDeviceLocation;
  final MapConfig mapConfig;
  final TileProviderFactory? tileProviderFactory;
  @override
  State<WaitingLocationPicker> createState() => _WaitingLocationPickerState();
}

class _WaitingLocationPickerState extends State<WaitingLocationPicker>
    with WidgetsBindingObserver {
  WaitingLocation? _draft;
  LocationFailure? _error;
  bool _busy = false;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
    WidgetsBinding.instance.addObserver(this);
    // Only the explicit Use My Location action sets this flag.
    if (widget.requestDeviceLocation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_locate());
      });
    }
  }

  void _cancelRequest() {
    _request++;
    widget.service.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.detached) &&
        _busy) {
      _cancelRequest();
      setState(() {
        _busy = false;
        _error = const LocationFailure(LocationProblem.cancelled);
      });
    }
  }

  Future<void> _locate() async {
    if (_busy) return;
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final fix = await widget.service.locate();
      if (!mounted || request != _request) return;
      setState(
        () => _draft = WaitingLocation(
          point: fix.point,
          source: WaitingLocationSource.deviceGps,
          accuracyMeters: fix.accuracyMeters,
          measuredAt: fix.measuredAt,
          isMocked: fix.isMocked,
          selectedAt: DateTime.now().toUtc(),
        ),
      );
    } catch (error) {
      if (mounted && request == _request) {
        setState(
          () => _error = error is LocationFailure
              ? error
              : const LocationFailure(LocationProblem.unavailable),
        );
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  void _manual(GeoPoint point) {
    _cancelRequest();
    setState(() {
      _busy = false;
      _error = null;
      _draft = WaitingLocation(
        point: point,
        source: WaitingLocationSource.manualMap,
        selectedAt: DateTime.now().toUtc(),
      );
    });
  }

  void _confirm() {
    final draft = _draft;
    if (draft == null || _busy) return;
    if (draft.source == WaitingLocationSource.deviceGps &&
        (draft.measuredAt == null ||
            DateTime.now().toUtc().difference(draft.measuredAt!) >
                const Duration(minutes: 2))) {
      setState(() => _error = const LocationFailure(LocationProblem.oldFix));
      return;
    }
    Navigator.pop(
      context,
      WaitingLocation(
        point: draft.point,
        source: draft.source,
        selectedAt: DateTime.now().toUtc(),
        measuredAt: draft.measuredAt,
        accuracyMeters: draft.accuracyMeters,
        isMocked: draft.isMocked,
      ),
    );
  }

  Future<void> _settings(bool app) async {
    final opened = app
        ? await widget.service.openAppSettings()
        : await widget.service.openLocationSettings();
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Open Android Settings manually, then return and tap Retry.',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _cancelRequest();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GlassBackdrop(
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Waiting location'),
        toolbarHeight: MediaQuery.textScalerOf(context).scale(1) > 1.5
            ? 104
            : 64,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Choose where to wait',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Optional · Tap the map to place or reposition your pin. Confirm only after checking it.',
                  ),
                  const SizedBox(height: 16),
                  GlassPanel(
                    padding: const EdgeInsets.all(6),
                    child: SizedBox(
                      height: 330,
                      child: JeepneyMap(
                        key: const ValueKey('waiting-picker-map'),
                        jeepneys: const [],
                        onSelect: (_) {},
                        waitingPoint: _draft?.point,
                        onWaitingPointTap: _manual,
                        pickingWaitingLocation: true,
                        config: widget.mapConfig,
                        tileProviderFactory: widget.tileProviderFactory,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  GlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_draft == null)
                          const Text(
                            'No point selected. The initial map view is an area reference, not your location.',
                          )
                        else ...[
                          Text(
                            _draft!.sourceLabel,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_draft!.point.latitude.toStringAsFixed(6)}, ${_draft!.point.longitude.toStringAsFixed(6)}',
                            key: const ValueKey('waiting-coordinates'),
                          ),
                          const SizedBox(height: 8),
                          Text(_draft!.accuracyLabel),
                          if (_draft!.lowAccuracy)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'This reading covers a broad area. Reposition the pin manually or retry before confirming.',
                              ),
                            ),
                          if (_draft!.measuredAt != null)
                            Text(
                              'Device reading: ${reportTime(_draft!.measuredAt)}',
                            ),
                        ],
                        if (_busy)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: LinearProgressIndicator(
                              semanticsLabel: 'Requesting one device location',
                            ),
                          ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                _error!.message,
                                key: const ValueKey('location-error'),
                              ),
                            ),
                          ),
                        const SizedBox(height: 14),
                        PassengerButton(
                          onPressed: _busy ? null : _locate,
                          icon: const Icon(Icons.my_location_rounded),
                          label: Text(
                            _error == null
                                ? 'Use My Location'
                                : 'Retry location',
                          ),
                        ),
                        if (_error?.problem == LocationProblem.deniedForever ||
                            _error?.problem == LocationProblem.denied)
                          TextButton(
                            onPressed: () => _settings(true),
                            child: const Text('Open app settings'),
                          ),
                        if (_error?.problem == LocationProblem.disabled)
                          TextButton(
                            onPressed: () => _settings(false),
                            child: const Text('Open location settings'),
                          ),
                        const SizedBox(height: 10),
                        const Text(
                          'Only one reading is used. No background tracking. Nothing is sent to your account or the AbangQue backend.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const GlassPanel(child: Text(boardingLocationNotice)),
                  const SizedBox(height: 14),
                  const Text(
                    'Map tiles are provided by OpenStreetMap. Viewing this area requests its map tiles; no passenger pin or account data is sent with them.',
                  ),
                  const SizedBox(height: 16),
                  PassengerButton(
                    onPressed: _draft == null || _busy ? null : _confirm,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Confirm Location'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
