import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:geolocator/geolocator.dart';

import '../domain/jeepney.dart';

enum LocationProblem {
  denied,
  deniedForever,
  disabled,
  timeout,
  unavailable,
  cancelled,
  oldFix,
}

class LocationFailure implements Exception {
  const LocationFailure(this.problem);
  final LocationProblem problem;
  String get message => switch (problem) {
    LocationProblem.denied => 'Location permission was denied. Retry when ready, or choose a point on the map.',
    LocationProblem.deniedForever => 'Location permission is blocked. Open app settings, choose Permissions → Location, and allow access while using the app. You can also choose on the map.',
    LocationProblem.disabled => 'Device location is turned off. Enable Location in device settings, then tap Retry. Manual map selection still works.',
    LocationProblem.timeout => 'A location could not be obtained in time. Try again with a clearer sky view, or choose on the map.',
    LocationProblem.oldFix => 'That device reading is outdated. Retry for a new reading, or choose on the map.',
    LocationProblem.cancelled =>
      'Location request stopped. Tap Use My Location to try again.',
    LocationProblem.unavailable =>
      'Device location is unavailable. Retry, or choose a point on the map.',
  };
}

class DeviceFix {
  const DeviceFix({
    required this.point,
    required this.measuredAt,
    this.accuracyMeters,
    this.isMocked = false,
  });
  final GeoPoint point;
  final DateTime measuredAt;
  final double? accuracyMeters;
  final bool isMocked;
}

abstract interface class DeviceLocationService {
  Future<DeviceFix> locate();
  void cancel();
  Future<bool> openAppSettings();
  Future<bool> openLocationSettings();
}

/// A cancellable one-reading acquisition. The native subscription exists only
/// after a button press and is removed on first fix, timeout, cancel or app pause.
/// No foreground-service configuration, background permission or location history.
class ForegroundDeviceLocationService implements DeviceLocationService {
  ForegroundDeviceLocationService({
    GeolocatorPlatform? platform,
    this.timeout = const Duration(seconds: 20),
    DateTime Function()? clock,
  }) : _platform = platform ?? GeolocatorPlatform.instance,
       _clock = clock ?? DateTime.now;
  final GeolocatorPlatform _platform;
  final Duration timeout;
  final DateTime Function() _clock;
  int _generation = 0;
  StreamSubscription<Position>? _subscription;
  Completer<Position>? _result;
  Timer? _timer;
  @override
  void cancel() {
    _generation++;
    _timer?.cancel();
    final sub = _subscription;
    _subscription = null;
    if (sub != null) unawaited(sub.cancel());
    final result = _result;
    _result = null;
    if (result != null && !result.isCompleted) {
      result.completeError(const LocationFailure(LocationProblem.cancelled));
    }
  }

  @override
  Future<DeviceFix> locate() async {
    cancel();
    final generation = _generation;
    void checkActive() {
      if (generation != _generation) {
        throw const LocationFailure(LocationProblem.cancelled);
      }
    }

    try {
      // Native permission configuration in this phase targets Android and Windows.
      // Other platforms retain the fully functional manual picker.
      if (kIsWeb ||
          ![
            TargetPlatform.android,
            TargetPlatform.windows,
          ].contains(defaultTargetPlatform)) {
        throw const LocationFailure(LocationProblem.unavailable);
      }
      final enabled = await _platform.isLocationServiceEnabled().timeout(
        const Duration(seconds: 5),
      );
      checkActive();
      if (!enabled) throw const LocationFailure(LocationProblem.disabled);
      var permission = await _platform.checkPermission().timeout(
        const Duration(seconds: 5),
      );
      checkActive();
      if (permission == LocationPermission.denied) {
        permission = await _platform.requestPermission();
        checkActive();
      }
      if (permission == LocationPermission.deniedForever) {
        throw const LocationFailure(LocationProblem.deniedForever);
      }
      if (permission == LocationPermission.denied) {
        throw const LocationFailure(LocationProblem.denied);
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw const LocationFailure(LocationProblem.unavailable);
      }
      final result = Completer<Position>();
      _result = result;
      _subscription = _platform
          .getPositionStream(
            locationSettings: LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: timeout,
            ),
          )
          .listen(
            (position) {
              if (!result.isCompleted) result.complete(position);
            },
            onError: (Object error) {
              if (!result.isCompleted) result.completeError(error);
            },
            onDone: () {
              if (!result.isCompleted) {
                result.completeError(
                  const LocationFailure(LocationProblem.unavailable),
                );
              }
            },
          );
      _timer = Timer(timeout, () {
        if (!result.isCompleted) {
          result.completeError(const LocationFailure(LocationProblem.timeout));
        }
      });
      final position = await result.future;
      checkActive();
      final age = _clock().toUtc().difference(position.timestamp.toUtc());
      if (age > const Duration(minutes: 2) ||
          age < const Duration(seconds: -30)) {
        throw const LocationFailure(LocationProblem.oldFix);
      }
      if (!position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.latitude.abs() > 90 ||
          position.longitude.abs() > 180) {
        throw const LocationFailure(LocationProblem.unavailable);
      }
      return DeviceFix(
        point: GeoPoint(position.latitude, position.longitude),
        measuredAt: position.timestamp.toUtc(),
        accuracyMeters: position.accuracy.isFinite && position.accuracy > 0
            ? position.accuracy
            : null,
        isMocked: position.isMocked,
      );
    } on LocationFailure {
      rethrow;
    } on TimeoutException {
      throw const LocationFailure(LocationProblem.timeout);
    } on PermissionDeniedException {
      throw const LocationFailure(LocationProblem.denied);
    } on LocationServiceDisabledException {
      throw const LocationFailure(LocationProblem.disabled);
    } catch (_) {
      throw const LocationFailure(LocationProblem.unavailable);
    } finally {
      if (generation == _generation) {
        _timer?.cancel();
        await _subscription?.cancel();
        _subscription = null;
        _result = null;
      }
    }
  }

  @override
  Future<bool> openAppSettings() async {
    try {
      return await _platform.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openLocationSettings() async {
    try {
      return await _platform.openLocationSettings();
    } catch (_) {
      return false;
    }
  }
}
