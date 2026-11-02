/// Domain types have no UI or transport dependencies.
/// FULL/AVAILABLE is a manually reported state, never a passenger count.
enum OccupancyStatus { available, full, unknown }

enum DataSource { demo, hardware, simulated }

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
    this.operatorName,
  });
  final String id;
  final String name;
  final String? operatorName;
  bool get isSimulated => source == DataSource.simulated;
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
      source == DataSource.hardware && hasRecentTelemetry;
  bool get hasRecentTelemetry =>
      fromApi &&
      source != DataSource.demo &&
      !isStale &&
      recordedAt != null &&
      lastSeenAt != null &&
      connectionStatus == 'ONLINE';
  OccupancyStatus get status {
    if (isStale ||
        (fromApi && (source == DataSource.demo || !hasRecentTelemetry))) {
      return OccupancyStatus.unknown;
    }
    return reportedStatus ?? OccupancyStatus.unknown;
  }

  Jeepney asStale() => Jeepney(
    id: id,
    name: name,
    position: position,
    recordedAt: recordedAt,
    lastSeenAt: lastSeenAt,
    source: source,
    fromApi: fromApi,
    isStale: true,
    connectionStatus: 'OFFLINE',
    reportedStatus: reportedStatus,
    operatorName: operatorName,
  );
  String get connectivityLabel => !fromApi
      ? 'DEMO · No device connection'
      : source == DataSource.demo
      ? 'Historical DEMO · No device connection'
      : recordedAt == null || lastSeenAt == null
      ? 'UNKNOWN · No report received'
      : isStale
      ? 'OFFLINE / STALE · No recent report'
      : isSimulated
      ? 'ONLINE · Simulated sender report is fresh'
      : 'ONLINE · Last device report is fresh';

  String get statusLabel =>
      isStale ? 'STALE / UNKNOWN' : status.name.toUpperCase();
  String get sourceLabel => isSimulated
      ? 'API · SIMULATED / DEMO'
      : fromApi
      ? (source == DataSource.demo
            ? 'API · Historical DEMO'
            : 'API · Driver report')
      : 'DEMO · Offline simulation';
  String get freshnessLabel => isSimulated
      ? (hasRecentTelemetry
            ? 'Fresh SIMULATED report'
            : 'SIMULATED report outdated')
      : !fromApi
      ? 'Simulated report'
      : source == DataSource.demo
      ? 'Historical demo'
      : recordedAt == null
      ? 'No report yet'
      : hasFreshReport
      ? 'Fresh report'
      : 'Report outdated';
}
