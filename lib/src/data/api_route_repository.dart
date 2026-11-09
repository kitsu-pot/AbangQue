import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/passenger_route.dart';
import 'public_cache/public_cache.dart';

class ApiRouteRepository
    implements RestorableRouteRepository, PublicDataSource {
  ApiRouteRepository({
    required this.baseUrl,
    this.allowSimulation = false,
    http.Client Function()? clientFactory,
    this.cache,
    this.timeout = const Duration(seconds: 10),
    DateTime Function()? clock,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _clock = clock ?? DateTime.now;
  final Uri baseUrl;
  final bool allowSimulation;
  final http.Client Function() _clientFactory;
  final PublicCache? cache;
  final Duration timeout;
  final DateTime Function() _clock;
  @override
  final state = PublicDataState();
  RouteCatalog? _latest;
  Future<RouteCatalog>? _pending;
  Future<void>? _hydration;
  Future<void> _hydrate() => _hydration ??= _readCache();
  Future<void> _readCache() async {
    try {
      final saved = await cache?.read('routes');
      if (saved != null && saved.validAt(_clock().toUtc())) {
        _latest = parseRouteCatalog(saved.data, allowSimulation);
        state.receivedAt = saved.receivedAt;
        state.hasSnapshot = true;
      }
    } catch (_) {
      /* Ignore malformed storage. */
    }
  }

  @override
  Future<RouteCatalog?> readCachedCatalog() async {
    await _hydrate();
    if (_latest == null ||
        state.receivedAt == null ||
        !CacheEntry([], state.receivedAt!).validAt(_clock().toUtc())) {
      return null;
    }
    return RouteCatalog(
      routes: _latest!.routes,
      assignments: _latest!.assignments,
      isCached: true,
      receivedAt: state.receivedAt,
    );
  }

  @override
  Future<RouteCatalog> loadCatalog() =>
      _pending ??= _load().whenComplete(() => _pending = null);
  Future<RouteCatalog> _load() async {
    await _hydrate();
    final client = _clientFactory();
    try {
      final request = http.Request('GET', baseUrl.resolve('/api/routes'))
        ..followRedirects = false;
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
      if (response.statusCode != 200 ||
          response.bodyBytes.length > publicCacheMaxBytes) {
        throw const FormatException('Route request failed');
      }
      final catalog = parseRouteCatalog(
        jsonDecode(response.body)['data'],
        allowSimulation,
      );
      _latest = catalog;
      state.receivedAt = _clock().toUtc();
      state.hasSnapshot = true;
      state.offline = false;
      state.attempted = true;
      try {
        await cache?.write(
          'routes',
          CacheEntry(publicRouteJson(catalog), state.receivedAt!),
        );
        state.cacheWriteFailed = false;
      } catch (_) {
        state.cacheWriteFailed = true;
      }
    } catch (_) {
      state.offline = true;
      state.attempted = true;
      if (_latest == null ||
          state.receivedAt == null ||
          !CacheEntry([], state.receivedAt!).validAt(_clock().toUtc())) {
        _latest = null;
        state.receivedAt = null;
        state.hasSnapshot = false;
        rethrow;
      }
    } finally {
      client.close();
    }
    return RouteCatalog(
      routes: _latest!.routes,
      assignments: _latest!.assignments,
      isCached: state.offline,
      receivedAt: state.receivedAt,
    );
  }
}

Map<String, Object> publicRouteJson(RouteCatalog catalog) => {
  'routes': catalog.routes
      .map(
        (r) => {
          'id': r.id,
          'origin': r.origin.label,
          'destination': r.destination.label,
          'isDemo': r.isDemo,
        },
      )
      .toList(),
  'assignments': catalog.assignments
      .map((a) => {'jeepneyId': a.jeepneyId, 'routeId': a.routeId})
      .toList(),
};
RouteCatalog parseRouteCatalog(dynamic data, bool allowSimulation) {
  if (data is! Map || data['routes'] is! List || data['assignments'] is! List) {
    throw const FormatException('Invalid route catalog');
  }
  if ((data['routes'] as List).length > 500 ||
      (data['assignments'] as List).length > 5000) {
    throw const FormatException('Catalog limit');
  }
  Municipality municipality(dynamic value) =>
      Municipality.values.firstWhere((m) => m.label == value);
  final routes = <PassengerRoute>[];
  for (final row in data['routes']) {
    if (row is! Map || row['id'] is! String || row['isDemo'] is! bool) {
      throw const FormatException('Invalid route');
    }
    final route = PassengerRoute(
      id: row['id'],
      origin: municipality(row['origin']),
      destination: municipality(row['destination']),
      isDemo: row['isDemo'],
    );
    if (!route.isDemo || allowSimulation) routes.add(route);
  }
  final allIds = (data['routes'] as List).map((r) => r['id']).toSet();
  if (allIds.length != (data['routes'] as List).length) {
    throw const FormatException('Duplicate routes');
  }
  final ids = routes.map((r) => r.id).toSet();
  final assignments = <RouteAssignment>[];
  for (final row in data['assignments']) {
    if (row is! Map ||
        row['jeepneyId'] is! String ||
        row['routeId'] is! String ||
        !allIds.contains(row['routeId'])) {
      throw const FormatException('Invalid assignment');
    }
    if (ids.contains(row['routeId'])) {
      assignments.add(
        RouteAssignment(jeepneyId: row['jeepneyId'], routeId: row['routeId']),
      );
    }
  }
  return RouteCatalog(routes: routes, assignments: assignments);
}
