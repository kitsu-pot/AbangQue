import '../domain/jeepney.dart';

enum WaitingLocationSource { deviceGps, manualMap }

/// A passenger's reference point, never a verified stop or route assignment.
/// Kept in memory only. No account ID, serialization or transport contract.
class WaitingLocation {
  WaitingLocation({
    required this.point,
    required this.source,
    required this.selectedAt,
    this.accuracyMeters,
    this.measuredAt,
    this.isMocked = false,
  }) {
    if (!point.latitude.isFinite ||
        !point.longitude.isFinite ||
        point.latitude < -90 ||
        point.latitude > 90 ||
        point.longitude < -180 ||
        point.longitude > 180 ||
        (accuracyMeters != null &&
            (!accuracyMeters!.isFinite || accuracyMeters! <= 0)) ||
        (source == WaitingLocationSource.manualMap &&
            (accuracyMeters != null || measuredAt != null || isMocked))) {
      throw ArgumentError('Invalid waiting point');
    }
  }
  final GeoPoint point;
  final WaitingLocationSource source;
  final double? accuracyMeters;
  final DateTime selectedAt;
  final DateTime? measuredAt;
  final bool isMocked;
  bool get isVerifiedBoardingPoint => false;
  bool get lowAccuracy => accuracyMeters != null && accuracyMeters! > 100;
  String get sourceLabel => source == WaitingLocationSource.manualMap
      ? 'Manually selected on map'
      : isMocked
      ? 'DEMO / Mock device location'
      : 'Device location · one reading';
  String get accuracyLabel => source == WaitingLocationSource.manualMap
      ? 'Map-selected point · GPS accuracy does not apply'
      : accuracyMeters == null
      ? 'Accuracy unavailable · Check the pin before confirming'
      : '${lowAccuracy ? 'Low accuracy · ' : ''}Estimated accuracy: ±${accuracyMeters!.ceil()} m · Not an exact position';
}

const boardingLocationNotice =
    'Your selected waiting location is for reference only. Boarding availability depends on the jeepney’s actual route and operating practices.';
