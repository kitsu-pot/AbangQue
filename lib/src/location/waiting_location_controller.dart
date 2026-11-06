import 'package:flutter/foundation.dart';

import 'device_location_service.dart';
import 'waiting_location.dart';

/// Session-only selection and cancellable foreground acquisition. No API transport.
class WaitingLocationController extends ChangeNotifier {
  WaitingLocation? _selected;
  WaitingLocation? get selected => _selected;
  bool locating = false;
  LocationFailure? failure;
  int _request = 0;
  DeviceLocationService? _service;
  bool _disposed = false;

  Future<void> locate(DeviceLocationService service) async {
    if (locating) return;
    final request = ++_request;
    _service = service;
    locating = true;
    failure = null;
    notifyListeners();
    try {
      final fix = await service.locate();
      if (_disposed || request != _request) return;
      _selected = WaitingLocation(
        point: fix.point,
        source: WaitingLocationSource.deviceGps,
        selectedAt: DateTime.now().toUtc(),
        measuredAt: fix.measuredAt,
        accuracyMeters: fix.accuracyMeters,
        isMocked: fix.isMocked,
      );
    } catch (error) {
      if (_disposed || request != _request) return;
      failure = error is LocationFailure
          ? error
          : const LocationFailure(LocationProblem.unavailable);
    } finally {
      if (!_disposed && request == _request) {
        locating = false;
        notifyListeners();
      }
    }
  }

  void cancel() {
    _request++;
    _service?.cancel();
    if (locating) {
      locating = false;
      failure = const LocationFailure(LocationProblem.cancelled);
      notifyListeners();
    }
  }

  void confirm(WaitingLocation location) {
    cancel();
    failure = null;
    _selected = location;
    notifyListeners();
  }

  void clear() {
    cancel();
    _selected = null;
    failure = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    _service?.cancel();
    super.dispose();
  }
}
