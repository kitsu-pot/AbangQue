enum Municipality {
  boac('Boac'),
  mogpog('Mogpog'),
  gasan('Gasan'),
  buenavista('Buenavista'),
  santaCruz('Santa Cruz'),
  torrijos('Torrijos');

  const Municipality(this.label);
  final String label;
}

/// A backend direction or explicitly marked development fixture. Choosing two
/// municipalities never constructs one of these records.
class PassengerRoute {
  PassengerRoute({
    required this.id,
    required this.origin,
    required this.destination,
    this.isDemo = false,
  }) {
    if (id.trim().isEmpty || origin == destination) {
      throw ArgumentError(
        'A registered route needs an ID and distinct endpoints.',
      );
    }
  }
  final String id;
  final bool isDemo;
  final Municipality origin;
  final Municipality destination;
  String get direction => '${origin.label} → ${destination.label}';
  String get label => isDemo ? 'DEMO test direction · $direction' : direction;
}

class RouteAssignment {
  const RouteAssignment({required this.jeepneyId, required this.routeId});
  final String jeepneyId;
  final String routeId;
}

/// Atomic, immutable route/assignment snapshot. No inference from coordinates.
class RouteCatalog {
  RouteCatalog({
    Iterable<PassengerRoute> routes = const [],
    Iterable<RouteAssignment> assignments = const [],
  }) : routes = List.unmodifiable(routes),
       assignments = List.unmodifiable(assignments) {
    final ids = this.routes.map((r) => r.id).toSet();
    if (ids.length != this.routes.length ||
        this.assignments.any(
          (a) => a.jeepneyId.trim().isEmpty || !ids.contains(a.routeId),
        )) {
      throw ArgumentError('Invalid route catalog or dangling assignment.');
    }
  }
  final List<PassengerRoute> routes;
  final List<RouteAssignment> assignments;
}

abstract interface class RouteRepository {
  Future<RouteCatalog> loadCatalog();
}

/// Empty catalog for offline preview and tests; never assigns existing demos.
class UnconfiguredRouteRepository implements RouteRepository {
  const UnconfiguredRouteRepository();
  @override
  Future<RouteCatalog> loadCatalog() async => RouteCatalog();
}
