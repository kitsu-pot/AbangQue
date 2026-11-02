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
    this.allowSimulation = false,
    this.pollInterval = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  final Uri baseUrl;
  final bool allowSimulation;
  Timer? _expiryTimer;
  Duration? _staleAfter;
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
        (json['data'] as List)
            .map(parseApiJeepney)
            .where((v) => !v.isSimulated || allowSimulation),
      );
      if (vehicles.map((v) => v.id).toSet().length != vehicles.length) {
        throw const FormatException('Duplicate vehicle IDs');
      }
      if (!_disposed) {
        final meta = json['meta'];
        final seconds = meta is Map ? meta['staleAfterSeconds'] : null;
        _staleAfter = seconds is int && seconds > 0
            ? Duration(seconds: seconds)
            : null;
        _latest = vehicles;
        _publishWithFreshness();
      }
    } catch (_) {
      if (!_disposed) {
        _expiryTimer?.cancel();
        _latest = null;
        _updates.addError(const ApiLoadException());
      }
    }
  }

  // Expire locally at the server's threshold even between successful polls.
  // A timer never makes a stale report fresh; only a new API snapshot can do that.
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
    reportedStatus: j['status'] == 'FULL'
        ? OccupancyStatus.full
        : j['status'] == 'AVAILABLE'
        ? OccupancyStatus.available
        : OccupancyStatus.unknown,
  );
}
