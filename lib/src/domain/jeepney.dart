/// Domain types have no Flutter, map, or transport dependencies.
enum OccupancyStatus { available, full, unknown }

enum DataSource { demo, hardware }

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude)
    : assert(latitude >= -90 && latitude <= 90),
      assert(longitude >= -180 && longitude <= 180);
  final double latitude;
  final double longitude;
}

class Jeepney {
  const Jeepney({
    required this.id,
    required this.name,
    required this.position,
    required this.passengerCount,
    required this.capacity,
    required this.eta,
    required this.recordedAt,
    required this.source,
    this.fromApi = false,
    this.isStale = false,
    this.lastSeenAt,
    this.connectionStatus,
    this.reportedStatus,
  }) : assert(capacity == null || capacity > 0),
       assert(
         passengerCount == null ||
             (passengerCount >= 0 &&
                 capacity != null &&
                 passengerCount <= capacity),
       );
  final String id;
  final String name;
  final GeoPoint? position;
  final int? passengerCount;
  final int? capacity;
  final Duration? eta;
  final DateTime? recordedAt;
  final DateTime? lastSeenAt;
  final DataSource source;
  final bool fromApi;
  final bool isStale;
  final String? connectionStatus;
  final OccupancyStatus? reportedStatus;
  int? get availableSeats =>
      capacity == null || passengerCount == null || isStale
      ? null
      : capacity! - passengerCount!;
  OccupancyStatus get status {
    if (isStale || (fromApi && source == DataSource.demo)) {
      return OccupancyStatus.unknown;
    }
    if (fromApi) return reportedStatus ?? OccupancyStatus.unknown;
    if (availableSeats == null) return OccupancyStatus.unknown;
    return availableSeats == 0
        ? OccupancyStatus.full
        : OccupancyStatus.available;
  }

  String get statusLabel =>
      isStale ? 'STALE / UNKNOWN' : status.name.toUpperCase();
  String get sourceLabel => fromApi
      ? (source == DataSource.demo
            ? 'API · Historical DEMO'
            : 'API · Device record')
      : 'Simulated jeepney';
}
