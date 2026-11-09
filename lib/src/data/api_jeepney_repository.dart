import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/jeepney.dart';
import '../domain/jeepney_repository.dart';
import 'public_cache/public_cache.dart';

/// Only public GETs. Cache failures never imply a successful API response.
class ApiJeepneyRepository implements JeepneyRepository, PublicDataSource {
  ApiJeepneyRepository({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
    this.allowSimulation = false,
    this.pollInterval = const Duration(seconds: 30),
    this.cache,
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;
  final Uri baseUrl;
  final bool allowSimulation;
  final Duration timeout;
  final Duration? pollInterval;
  final PublicCache? cache;
  final http.Client _client;
  final DateTime Function() _clock;
  @override
  final state = PublicDataState();
  final _updates = StreamController<List<Jeepney>>.broadcast();
  Timer? _timer, _expiryTimer;
  Duration? _staleAfter;
  bool _started = false, _disposed = false, _hydrated = false;
  int _failures = 0;
  Future<void>? _pending;
  List<Jeepney>? _latest;
  Completer<void>? _abort;
  List<Jeepney> _parse(dynamic rows) {
    if (rows is! List || rows.length > 500) {
      throw const FormatException('Invalid fleet');
    }
    final vehicles = rows
        .map(parseApiJeepney)
        .where((v) => !v.isSimulated || allowSimulation)
        .toList();
    if (vehicles.map((v) => v.id).toSet().length != vehicles.length) {
      throw const FormatException('Duplicate IDs');
    }
    return vehicles;
  }

  @override
  Stream<List<Jeepney>> watchJeepneys() => Stream.multi((listener) {
    if (_disposed) {
      listener.close();
      return;
    }
    final sub = _updates.stream.listen(
      listener.add,
      onError: listener.addError,
      onDone: listener.close,
    );
    listener.onCancel = sub.cancel;
    if (_latest != null) listener.add(_latest!);
    if (!_started) {
      _started = true;
      unawaited(refresh());
    }
  });
  @override
  Future<void> refresh() {
    if (_disposed) return Future.value();
    return _pending ??= _fetch().whenComplete(() => _pending = null);
  }

  Future<void> _fetch() async {
    _timer?.cancel();
    try {
      if (!_hydrated) {
        _hydrated = true;
        try {
          final saved = await cache?.read('jeepneys');
          if (!_disposed && saved != null && saved.validAt(_clock().toUtc())) {
            _latest = _parse(saved.data)
                .map((v) => v.withRetrieval(saved.receivedAt, cached: true))
                .toList();
            state.receivedAt = saved.receivedAt;
            state.hasSnapshot = true;
            _updates.add(_latest!);
          }
        } catch (_) {
          /* Invalid cache is ignored, never used as fresh data. */
        }
      }
      if (_disposed) return;
      final abort = _abort = Completer<void>();
      final request =
          http.AbortableRequest(
              'GET',
              baseUrl.resolve('/api/jeepneys'),
              abortTrigger: abort.future,
            )
            ..followRedirects = false
            ..headers['Accept'] = 'application/json';
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
      if (response.statusCode != 200 ||
          response.bodyBytes.length > publicCacheMaxBytes) {
        throw const FormatException('API request failed');
      }
      final json = jsonDecode(response.body);
      final vehicles = _parse(json['data']);
      if (_disposed) return;
      final received = _clock().toUtc();
      final seconds = json['meta'] is Map
          ? json['meta']['staleAfterSeconds']
          : null;
      // Conservative fallback for old API versions, never infinite freshness.
      _staleAfter = Duration(
        seconds: seconds is int && seconds > 0 ? seconds : 120,
      );
      _latest = vehicles.map((v) => v.withRetrieval(received)).toList();
      state.receivedAt = received;
      state.hasSnapshot = true;
      state.offline = false;
      state.attempted = true;
      _failures = 0;
      _publishWithFreshness();
      try {
        await cache?.write(
          'jeepneys',
          CacheEntry(vehicles.map(publicJeepneyJson).toList(), received),
        );
        state.cacheWriteFailed = false;
      } catch (_) {
        state.cacheWriteFailed = true;
      }
    } catch (_) {
      if (!_disposed) {
        state.offline = true;
        state.attempted = true;
        _failures++;
        _expiryTimer?.cancel();
        if (_latest != null &&
            state.receivedAt != null &&
            CacheEntry([], state.receivedAt!).validAt(_clock().toUtc())) {
          _latest = _latest!
              .map((v) => v.withRetrieval(state.receivedAt, cached: true))
              .toList();
          _updates.add(_latest!);
        } else {
          _latest = null;
          state.hasSnapshot = false;
          state.receivedAt = null;
          _updates.addError(const ApiLoadException());
        }
      }
    } finally {
      if (_abort != null && !_abort!.isCompleted) _abort!.complete();
      if (!_disposed && pollInterval != null) {
        _timer = Timer(
          _failures == 0 ? pollInterval! : retryDelay(_failures),
          () => unawaited(refresh()),
        );
      }
    }
  }

  void _publishWithFreshness() {
    _expiryTimer?.cancel();
    if (_disposed || _latest == null) return;
    final now = _clock().toUtc();
    DateTime? next;
    _latest = List.unmodifiable(
      _latest!.map((v) {
        if (_staleAfter == null ||
            v.isStale ||
            v.recordedAt == null ||
            v.lastSeenAt == null) {
          return v;
        }
        final oldest = v.recordedAt!.isBefore(v.lastSeenAt!)
            ? v.recordedAt!
            : v.lastSeenAt!;
        final expires = oldest.add(_staleAfter!);
        if (!expires.isAfter(now)) return v.asStale();
        if (next == null || expires.isBefore(next!)) next = expires;
        return v;
      }),
    );
    _updates.add(_latest!);
    if (next != null) {
      _expiryTimer = Timer(next!.difference(now), _publishWithFreshness);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _expiryTimer?.cancel();
    if (_abort != null && !_abort!.isCompleted) _abort!.complete();
    _client.close();
    await _updates.close();
  }
}

// Explicit allowlist: no passenger, credentials, arbitrary API extras or ETA.
Map<String, Object?> publicJeepneyJson(Jeepney v) => {
  'id': v.id,
  'name': v.name,
  'operatorName': v.operatorName,
  'source': v.source == DataSource.hardware
      ? 'device'
      : v.source == DataSource.simulated
      ? 'simulated'
      : 'demo',
  'isDemo': v.source != DataSource.hardware,
  'isSimulated': v.isSimulated,
  'isStale': v.isStale,
  'connectionStatus': v.connectionStatus,
  'timestamp': v.recordedAt?.toUtc().toIso8601String(),
  'lastSeenAt': v.lastSeenAt?.toUtc().toIso8601String(),
  'position': v.position == null
      ? null
      : {'latitude': v.position!.latitude, 'longitude': v.position!.longitude},
  'status': v.reportedStatus == OccupancyStatus.unknown
      ? null
      : v.reportedStatus?.name.toUpperCase(),
  'lastReportedStatus': v.lastReportedStatus?.name.toUpperCase(),
};

class ApiLoadException implements Exception {
  const ApiLoadException();
  @override
  String toString() =>
      'Unable to load API data. Check the backend and API URL, then retry.';
}

Jeepney parseApiJeepney(dynamic value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid vehicle');
  }
  final j = value;
  if (j['id'] is! String ||
      (j['id'] as String).isEmpty ||
      j['name'] is! String ||
      !['demo', 'device', 'simulated'].contains(j['source']) ||
      j['isDemo'] != (j['source'] != 'device') ||
      (j['source'] == 'simulated' && j['isSimulated'] != true) ||
      (j.containsKey('isSimulated') &&
          j['isSimulated'] != (j['source'] == 'simulated')) ||
      j['isStale'] is! bool ||
      !['ONLINE', 'OFFLINE', 'DEMO'].contains(j['connectionStatus']) ||
      ![null, 'FULL', 'AVAILABLE'].contains(j['status'])) {
    throw const FormatException('Invalid vehicle fields');
  }
  DateTime? date(dynamic v) {
    if (v == null) return null;
    if (v is! String || !RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(v)) {
      throw const FormatException('Invalid timestamp');
    }
    return DateTime.parse(v).toUtc();
  }

  GeoPoint? point;
  if (j['position'] != null) {
    final p = j['position'];
    if (p is! Map || p['latitude'] is! num || p['longitude'] is! num) {
      throw const FormatException('Invalid position');
    }
    final lat = (p['latitude'] as num).toDouble();
    final lon = (p['longitude'] as num).toDouble();
    if (!lat.isFinite ||
        !lon.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lon < -180 ||
        lon > 180) {
      throw const FormatException('Invalid coordinates');
    }
    point = GeoPoint(lat, lon);
  }
  final recorded = date(j['timestamp']);
  final seen = date(j['lastSeenAt']);
  final stale =
      j['isStale'] as bool ||
      j['connectionStatus'] == 'OFFLINE' ||
      recorded == null ||
      seen == null;
  return Jeepney(
    id: j['id'],
    name: j['name'],
    position: point,
    recordedAt: recorded,
    lastSeenAt: seen,
    source: j['source'] == 'simulated'
        ? DataSource.simulated
        : j['source'] == 'demo'
        ? DataSource.demo
        : DataSource.hardware,
    operatorName:
        j['operatorName'] is String &&
            (j['operatorName'] as String).trim().isNotEmpty
        ? j['operatorName']
        : null,
    fromApi: true,
    isStale: stale,
    connectionStatus: j['connectionStatus'],
    lastReportedStatus: j['lastReportedStatus'] == 'FULL'
        ? OccupancyStatus.full
        : j['lastReportedStatus'] == 'AVAILABLE'
        ? OccupancyStatus.available
        : null,
    reportedStatus: j['status'] == 'FULL'
        ? OccupancyStatus.full
        : j['status'] == 'AVAILABLE'
        ? OccupancyStatus.available
        : OccupancyStatus.unknown,
  );
}
