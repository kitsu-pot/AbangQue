import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/jeepney.dart';
import '../domain/jeepney_repository.dart';
import '../domain/passenger_route.dart';

class JeepneyController extends ChangeNotifier {
  JeepneyController(
    this._repository, {
    this.apiMode = false,
    this._routeRepository = const UnconfiguredRouteRepository(),
  }) {
    unawaited(_loadRoutes());
    _subscription = _repository.watchJeepneys().listen(
      (vehicles) {
        _vehicles = List.unmodifiable(vehicles);
        loading = false;
        error = null;
        notifyListeners();
      },
      onError: (Object failure) {
        loading = false;
        if (apiMode) _vehicles = const [];
        error = apiMode
            ? 'Unable to load API data. Check the backend and API URL, then retry.'
            : 'Unable to load jeepneys. Please try again.';
        notifyListeners();
      },
      onDone: () {
        if (loading) {
          loading = false;
          error = 'The jeepney data source is unavailable. Please try again.';
          notifyListeners();
        }
      },
    );
  }

  final JeepneyRepository _repository;
  final bool apiMode;
  late final StreamSubscription<List<Jeepney>> _subscription;
  List<Jeepney> _vehicles = const [];
  bool loading = true;
  bool refreshing = false;
  final RouteRepository _routeRepository;
  RouteCatalog _catalog = RouteCatalog();
  bool routesLoading = true;
  String? routesError;
  Municipality? origin;
  Municipality? destination;
  bool journeySubmitted = false;
  String? _selectedRouteId;
  int _routesRequest = 0;
  bool get hasSimulationRoutes => routes.any((r) => r.isDemo);
  List<PassengerRoute> get routes => _catalog.routes;
  List<PassengerRoute> get matchingRoutes => journeySubmitted
      ? routes
            .where((r) => r.origin == origin && r.destination == destination)
            .toList()
      : const [];
  PassengerRoute? get selectedRoute =>
      matchingRoutes.where((r) => r.id == _selectedRouteId).firstOrNull;
  bool get validJourney =>
      origin != null && destination != null && origin != destination;

  void setOrigin(Municipality? value) {
    origin = value;
    _resetJourney();
  }

  void setDestination(Municipality? value) {
    destination = value;
    _resetJourney();
  }

  void swapJourney() {
    final previous = origin;
    origin = destination;
    destination = previous;
    _resetJourney();
  }

  void _resetJourney() {
    journeySubmitted = false;
    selectedJeepneyId = null;
    _selectedRouteId = null;
    query = '';
    notifyListeners();
  }

  void editJourney() => _resetJourney();

  void findJeepneys() {
    if (!validJourney || routesLoading || routesError != null) return;
    journeySubmitted = true;
    query = '';
    _selectedRouteId = matchingRoutes.length == 1
        ? matchingRoutes.single.id
        : null;
    notifyListeners();
  }

  Future<bool> openFavorite(String routeId) async {
    final request = _routesRequest + 1;
    await _loadRoutes();
    if (_disposed || request != _routesRequest || routesError != null) {
      return false;
    }
    final route = routes.where((r) => r.id == routeId && !r.isDemo).firstOrNull;
    if (route == null) return false;
    origin = route.origin;
    destination = route.destination;
    journeySubmitted = true;
    _selectedRouteId = route.id;
    query = '';
    selectedJeepneyId = null;
    notifyListeners();
    return true;
  }

  void selectRoute(String id) {
    if (!matchingRoutes.any((r) => r.id == id)) return;
    _selectedRouteId = id;
    query = '';
    notifyListeners();
  }

  List<Jeepney> get journeyVehicles {
    final route = selectedRoute;
    if (route == null || routesError != null || routesLoading) return const [];
    final ids = _catalog.assignments
        .where((a) => a.routeId == route.id)
        .map((a) => a.jeepneyId)
        .toSet();
    return _vehicles
        .where(
          (v) =>
              ids.contains(v.id) &&
              (route.isDemo ? v.isSimulated : !v.isSimulated),
        )
        .toList();
  }

  Future<void> _loadRoutes() async {
    final request = ++_routesRequest;
    routesLoading = true;
    routesError = null;
    try {
      final catalog = await _routeRepository.loadCatalog();
      if (_disposed || request != _routesRequest) return;
      _catalog = catalog;
      if (!matchingRoutes.any((r) => r.id == _selectedRouteId)) {
        _selectedRouteId = null;
      }
    } catch (_) {
      if (_disposed || request != _routesRequest) return;
      _catalog = RouteCatalog();
      _selectedRouteId = null;
      routesError = 'Unable to load registered routes. Please retry.';
    } finally {
      if (!_disposed && request == _routesRequest) {
        routesLoading = false;
        notifyListeners();
      }
    }
  }

  String? selectedJeepneyId;
  Jeepney? get selectedJeepney =>
      filteredVehicles.where((v) => v.id == selectedJeepneyId).firstOrNull;
  void selectJeepney(Jeepney vehicle) {
    if (!filteredVehicles.any((v) => v.id == vehicle.id)) return;
    selectedJeepneyId = vehicle.id;
    notifyListeners();
  }

  String query = '';
  String? error;
  bool _disposed = false;

  List<Jeepney> get vehicles => _vehicles;
  List<Jeepney> get filteredVehicles => journeyVehicles.where((vehicle) {
    final text = '${vehicle.id} ${vehicle.name}'.toLowerCase();
    return text.contains(query.trim().toLowerCase());
  }).toList();

  void setQuery(String value) {
    query = value;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (refreshing) return;
    refreshing = true;
    if (_vehicles.isEmpty) loading = true;
    error = null;
    notifyListeners();
    try {
      await Future.wait([_repository.refresh(), _loadRoutes()]);
    } catch (_) {
      if (!_disposed) {
        if (apiMode) _vehicles = const [];
        error = 'Could not refresh jeepneys. Please try again.';
      }
    } finally {
      if (!_disposed) {
        refreshing = false;
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    // The app composition root owns and disposes the repository.
    super.dispose();
  }
}
