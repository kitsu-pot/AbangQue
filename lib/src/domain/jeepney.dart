/// Domain types have no UI or transport dependencies.
/// FULL/AVAILABLE is a manually reported state, never a passenger count.
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
    required this.recordedAt,
    required this.source,
    this.fromApi = false,
    this.isStale = false,
    this.lastSeenAt,
    this.connectionStatus,
    this.reportedStatus,
  });
  final String id;
  final String name;
  final GeoPoint? position;
  final DateTime? recordedAt;
  final DateTime? lastSeenAt;
  final DataSource source;
  final bool fromApi;
  final bool isStale;
  final String? connectionStatus;
  final OccupancyStatus? reportedStatus;

  /// ETA remains unavailable in every mode until an agreed algorithm exists.
  Duration? get eta => null;
  bool get hasFreshReport =>
      fromApi &&
      source == DataSource.hardware &&
      !isStale &&
      recordedAt != null &&
      lastSeenAt != null &&
      connectionStatus == 'ONLINE';
  OccupancyStatus get status {
    if (isStale ||
        (fromApi && (source == DataSource.demo || !hasFreshReport))) {
      return OccupancyStatus.unknown;
    }
    return reportedStatus ?? OccupancyStatus.unknown;
  }

  String get statusLabel =>
      isStale ? 'STALE / UNKNOWN' : status.name.toUpperCase();
  String get sourceLabel => fromApi
      ? (source == DataSource.demo
            ? 'API · Historical DEMO'
            : 'API · Driver report')
      : 'DEMO · Offline simulation';
  String get freshnessLabel => !fromApi
      ? 'Simulated report'
      : source == DataSource.demo
      ? 'Historical demo'
      : recordedAt == null
      ? 'No report yet'
      : hasFreshReport
      ? 'Fresh report'
      : 'Report outdated';
}
