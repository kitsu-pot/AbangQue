import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/jeepney.dart';
import '../domain/jeepney_repository.dart';

/// Passenger read API only. No credential storage, device POSTs, or demo fallback.
class ApiJeepneyRepository implements JeepneyRepository {
  ApiJeepneyRepository({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
    this.pollInterval = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();
  final Uri baseUrl;
  final http.Client _client;
  final Duration timeout;
  final Duration? pollInterval;
  final _updates = StreamController<List<Jeepney>>.broadcast();
  Timer? _timer;
  bool _started = false;
  bool _disposed = false;
  Future<void>? _pending;
  List<Jeepney>? _latest;

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
      if (pollInterval != null) {
        _timer = Timer.periodic(pollInterval!, (_) => unawaited(refresh()));
      }
    }
  });

  @override
  Future<void> refresh() {
    if (_disposed) return Future.value();
    return _pending ??= _fetch().whenComplete(() => _pending = null);
  }

  Future<void> _fetch() async {
    try {
      final request = http.Request('GET', baseUrl.resolve('/api/jeepneys'))
        ..followRedirects = false
        ..headers['Accept'] = 'application/json';
      // Refuse redirects, including HTTPS-to-HTTP downgrades. Bound the entire
      // response, not just the time until headers arrive.
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
      if (response.statusCode != 200) {
        throw const FormatException('API request failed');
      }
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic> || json['data'] is! List) {
        throw const FormatException('Invalid API envelope');
      }
      final vehicles = List<Jeepney>.unmodifiable(
        (json['data'] as List).map(parseApiJeepney),
      );
      if (vehicles.map((v) => v.id).toSet().length != vehicles.length) {
        throw const FormatException('Duplicate vehicle IDs');
      }
      if (!_disposed) {
        _latest = vehicles;
        _updates.add(vehicles);
      }
    } catch (_) {
      if (!_disposed) {
        _latest = null;
        _updates.addError(const ApiLoadException());
      }
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _client.close();
    await _updates.close();
  }
}

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
      !['demo', 'device'].contains(j['source']) ||
      j['isDemo'] != (j['source'] == 'demo') ||
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
    passengerCount: null,
    capacity: null,
    // Phase 2 has no ETA contract beyond null. Never invent one.
    eta: null,
    recordedAt: recorded,
    lastSeenAt: seen,
    source: j['source'] == 'demo' ? DataSource.demo : DataSource.hardware,
    fromApi: true,
    isStale: stale,
    connectionStatus: j['connectionStatus'],
    reportedStatus: j['status'] == 'FULL'
        ? OccupancyStatus.full
        : j['status'] == 'AVAILABLE'
        ? OccupancyStatus.available
        : OccupancyStatus.unknown,
  );
}
