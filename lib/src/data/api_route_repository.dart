import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/passenger_route.dart';

/// Public backend catalog, never inferred from coordinates or chosen municipalities.
class ApiRouteRepository implements RouteRepository {
  ApiRouteRepository({
    required this.baseUrl,
    this.allowSimulation = false,
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;
  final Uri baseUrl;
  final bool allowSimulation;
  final http.Client Function() _clientFactory;
  @override
  Future<RouteCatalog> loadCatalog() async {
    final client = _clientFactory();
    try {
      final request = http.Request('GET', baseUrl.resolve('/api/routes'))
        ..followRedirects = false;
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 10));
      // Compatible with pre-catalog backends. Never substitute fictional routes.
      if (response.statusCode == 404) return RouteCatalog();
      if (response.statusCode != 200) {
        throw const FormatException('Route request failed');
      }
      final data = jsonDecode(response.body)['data'];
      if (data is! Map ||
          data['routes'] is! List ||
          data['assignments'] is! List) {
        throw const FormatException('Invalid route catalog');
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
            RouteAssignment(
              jeepneyId: row['jeepneyId'],
              routeId: row['routeId'],
            ),
          );
        }
      }
      return RouteCatalog(routes: routes, assignments: assignments);
    } finally {
      client.close();
    }
  }
}
