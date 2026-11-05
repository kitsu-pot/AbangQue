import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:jeeplink/src/domain/jeepney.dart';
import 'package:jeeplink/src/location/device_location_service.dart';
import 'package:jeeplink/src/location/waiting_location.dart';
import 'package:jeeplink/src/location/waiting_location_controller.dart';

class FakeLocationPlatform extends GeolocatorPlatform {
  bool enabled = true;
  LocationPermission permission = LocationPermission.denied;
  LocationPermission requestedPermission = LocationPermission.whileInUse;
  int requests = 0, reads = 0, stops = 0, appSettings = 0, locationSettings = 0;
  Completer<LocationPermission>? pendingPermission;
  late final positions = StreamController<Position>.broadcast(
    onListen: () => reads++,
    onCancel: () => stops++,
  );
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return pendingPermission?.future ?? requestedPermission;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    expect(locationSettings!.accuracy, LocationAccuracy.high);
    return positions.stream;
  }

  @override
  Future<bool> openAppSettings() async {
    appSettings++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettings++;
    return true;
  }
}

Position fix({
  double accuracy = 12,
  DateTime? timestamp,
  bool mocked = false,
}) => Position(
  latitude: 13.45,
  longitude: 121.84,
  timestamp: timestamp ?? DateTime.now().toUtc(),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
  isMocked: mocked,
);
Matcher problem(LocationProblem kind) =>
    isA<LocationFailure>().having((e) => e.problem, 'problem', kind);

void main() {
  test('selection is an optional session-only reference with source, time and accuracy', () {
    final state = WaitingLocationController();
    expect(state.selected, isNull);
    state.confirm(
      WaitingLocation(
        point: const GeoPoint(13.45, 121.84),
        source: WaitingLocationSource.manualMap,
        selectedAt: DateTime.now(),
      ),
    );
    expect(state.selected!.isVerifiedBoardingPoint, false);
    expect(state.selected!.accuracyMeters, isNull);
    state.clear();
    expect(state.selected, isNull);
    state.dispose();
    expect(WaitingLocationController().selected, isNull);
    expect(
      () => WaitingLocation(
        point: const GeoPoint(13, 121),
        source: WaitingLocationSource.manualMap,
        selectedAt: DateTime.now(),
        accuracyMeters: 2,
      ),
      throwsArgumentError,
    );
  });
  test('no startup access; permission then one position; listener stops immediately', () async {
    final native = FakeLocationPlatform();
    final service = ForegroundDeviceLocationService(platform: native);
    expect(native.requests, 0);
    expect(native.reads, 0);
    final future = service.locate();
    await Future<void>.delayed(Duration.zero);
    expect(native.requests, 1);
    expect(native.reads, 1);
    native.positions.add(fix());
    final result = await future;
    expect(result.point.latitude, 13.45);
    expect(result.accuracyMeters, 12);
    expect(native.stops, 1);
    service.cancel();
    await native.positions.close();
  });
  for (final kind in [
    LocationProblem.denied,
    LocationProblem.deniedForever,
    LocationProblem.disabled,
  ]) {
    test(
      '$kind does not start positioning and settings remain explicit',
      () async {
        final native = FakeLocationPlatform();
        if (kind == LocationProblem.disabled) native.enabled = false;
        if (kind == LocationProblem.denied) {
          native.requestedPermission = LocationPermission.denied;
        }
        if (kind == LocationProblem.deniedForever) {
          native.permission = LocationPermission.deniedForever;
        }
        final service = ForegroundDeviceLocationService(platform: native);
        await expectLater(service.locate(), throwsA(problem(kind)));
        expect(native.reads, 0);
        expect(native.appSettings, 0);
        expect(await service.openAppSettings(), true);
        expect(await service.openLocationSettings(), true);
        await native.positions.close();
      },
    );
  }
  test(
    'timeout, cancellation and platform failure all stop acquisition',
    () async {
      for (final kind in [
        LocationProblem.timeout,
        LocationProblem.cancelled,
        LocationProblem.unavailable,
      ]) {
        final native = FakeLocationPlatform();
        final service = ForegroundDeviceLocationService(
          platform: native,
          timeout: const Duration(milliseconds: 40),
        );
        final future = service.locate();
        final check = expectLater(future, throwsA(problem(kind)));
        await Future<void>.delayed(Duration.zero);
        if (kind == LocationProblem.cancelled) service.cancel();
        if (kind == LocationProblem.unavailable) {
          native.positions.addError(StateError('Private native details'));
        }
        await check;
        expect(native.stops, 1);
        await native.positions.close();
      }
    },
  );
  test(
    'cancelling permission flow cannot start late location acquisition',
    () async {
      final native = FakeLocationPlatform()
        ..pendingPermission = Completer<LocationPermission>();
      final service = ForegroundDeviceLocationService(platform: native);
      final check = expectLater(
        service.locate(),
        throwsA(problem(LocationProblem.cancelled)),
      );
      await Future<void>.delayed(Duration.zero);
      service.cancel();
      native.pendingPermission!.complete(LocationPermission.whileInUse);
      await check;
      expect(native.reads, 0);
      await native.positions.close();
    },
  );
  test(
    'old positions are rejected; low accuracy and mock readings stay explicit',
    () async {
      final native = FakeLocationPlatform();
      final service = ForegroundDeviceLocationService(platform: native);
      final check = expectLater(
        service.locate(),
        throwsA(problem(LocationProblem.oldFix)),
      );
      await Future<void>.delayed(Duration.zero);
      native.positions.add(
        fix(timestamp: DateTime.now().subtract(const Duration(minutes: 3))),
      );
      await check;
      await native.positions.close();
      final other = FakeLocationPlatform();
      final next = ForegroundDeviceLocationService(platform: other).locate();
      await Future<void>.delayed(Duration.zero);
      other.positions.add(fix(accuracy: 600, mocked: true));
      final reading = await next;
      final point = WaitingLocation(
        point: reading.point,
        source: WaitingLocationSource.deviceGps,
        selectedAt: DateTime.now(),
        measuredAt: reading.measuredAt,
        accuracyMeters: reading.accuracyMeters,
        isMocked: reading.isMocked,
      );
      expect(point.lowAccuracy, true);
      expect(point.accuracyLabel, contains('Not an exact'));
      expect(point.sourceLabel, contains('DEMO'));
      await other.positions.close();
    },
  );
  test('Android requests only foreground permissions and preserves release cleartext policy', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('android.permission.ACCESS_COARSE_LOCATION'));
    expect(manifest, contains('android.permission.ACCESS_FINE_LOCATION'));
    expect(
      manifest,
      contains(
        'android.permission.ACCESS_BACKGROUND_LOCATION" tools:node="remove"',
      ),
    );
    expect(manifest, contains('android:usesCleartextTraffic="false"'));
  });
}
