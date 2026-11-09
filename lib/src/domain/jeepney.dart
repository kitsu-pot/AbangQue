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
    this.retrievedAt,
    this.isCached = false,
    this.lastReportedStatus,
  });
  final DateTime? retrievedAt;
  final bool isCached;
  final OccupancyStatus? lastReportedStatus;
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
      !isCached &&
      source != DataSource.demo &&
      !isStale &&
      recordedAt != null &&
      lastSeenAt != null &&
      connectionStatus == 'ONLINE';
  OccupancyStatus get status {
    if (isCached ||
        isStale ||
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
    retrievedAt: retrievedAt,
    isCached: isCached,
    lastReportedStatus: lastReportedStatus,
  );
  Jeepney withRetrieval(DateTime? time, {bool cached = false}) => Jeepney(
    id: id,
    name: name,
    position: position,
    recordedAt: recordedAt,
    lastSeenAt: lastSeenAt,
    source: source,
    fromApi: fromApi,
    isStale: isStale,
    connectionStatus: connectionStatus,
    reportedStatus: reportedStatus,
    operatorName: operatorName,
    retrievedAt: time,
    isCached: cached,
    lastReportedStatus: lastReportedStatus,
  );
  String get connectivityLabel => isCached
      ? 'UNVERIFIED · Last known location; availability may have changed'
      : !fromApi
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

  String get statusLabel => isCached
      ? 'CACHED / UNKNOWN'
      : isStale
      ? 'STALE / UNKNOWN'
      : status.name.toUpperCase();
  String get sourceLabel => isSimulated
      ? 'API · SIMULATED / DEMO'
      : fromApi
      ? (source == DataSource.demo
            ? 'API · Historical DEMO'
            : 'API · Driver report')
      : 'DEMO · Offline simulation';
  String get freshnessLabel => isCached
      ? 'Cached report · Current availability unknown'
      : isSimulated
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
