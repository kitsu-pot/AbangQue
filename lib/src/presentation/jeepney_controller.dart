import '../data/public_cache/public_cache.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/jeepney.dart';
import '../domain/jeepney_repository.dart';
import '../domain/passenger_route.dart';

class JeepneyController extends ChangeNotifier {
  JeepneyController(
    this._repository, {
    this.apiMode = false,
    this.pollInterval,
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
    _schedulePoll();
  }

  final JeepneyRepository _repository;
  final bool apiMode;
  final Duration? pollInterval;
  Timer? _pollTimer;
  int _failures = 0;
  bool _active = true;
  Future<void>? _routePending;
  PublicDataState? get fleetState => _repository is PublicDataSource
      ? (_repository as PublicDataSource).state
      : null;
  PublicDataState? get routeState => _routeRepository is PublicDataSource
      ? (_routeRepository as PublicDataSource).state
      : null;
  bool get managesConnectivity => fleetState != null || routeState != null;
  bool get offline =>
      apiMode &&
      (fleetState?.offline == true ||
          routeState?.offline == true ||
          error != null ||
          routesError != null);
  bool get checkingConnection =>
      fleetState?.attempted == false || routeState?.attempted == false;
  bool get hasPublicSnapshot =>
      fleetState?.hasSnapshot == true || routeState?.hasSnapshot == true;
  bool get cacheWarning =>
      fleetState?.cacheWriteFailed == true ||
      routeState?.cacheWriteFailed == true;
  String get connectionLabel => checkingConnection
      ? (hasPublicSnapshot
            ? 'Checking API · Saved information'
            : 'Connecting to API')
      : offline
      ? (hasPublicSnapshot
            ? 'Offline · Saved information'
            : 'API unreachable · No saved information')
      : _vehicles.any((v) => v.hasRecentTelemetry)
      ? 'API reachable · Fresh reports received'
      : 'API reachable · No fresh reports';
  void _schedulePoll() {
    _pollTimer?.cancel();
    if (_disposed || !_active || pollInterval == null) return;
    _pollTimer = Timer(
      _failures == 0 ? pollInterval! : retryDelay(_failures),
      () => unawaited(refresh()),
    );
  }

  void setActive(bool active) {
    _active = active;
    _pollTimer?.cancel();
    if (active && pollInterval != null) unawaited(refresh());
  }

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
    if (!validJourney ||
        (routesLoading && routes.isEmpty) ||
        routesError != null) {
      return;
    }
    journeySubmitted = true;
    query = '';
    _selectedRouteId = matchingRoutes.length == 1
        ? matchingRoutes.single.id
        : null;
    notifyListeners();
  }

  Future<bool> openFavorite(String routeId) async {
    final request = _routePending == null ? _routesRequest + 1 : _routesRequest;
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
    if (route == null || routesError != null) return const [];
    final ids = _catalog.assignments
        .where((a) => a.routeId == route.id)
        .map((a) => a.jeepneyId)
        .toSet();
    return vehicles
        .where(
          (v) =>
              ids.contains(v.id) &&
              (route.isDemo ? v.isSimulated : !v.isSimulated),
        )
        .toList();
  }

  Future<void> _loadRoutes() =>
      _routePending ??= _fetchRoutes().whenComplete(() => _routePending = null);

  Future<void> _fetchRoutes() async {
    final request = ++_routesRequest;
    routesLoading = true;
    routesError = null;
    try {
      if (_catalog.receivedAt == null &&
          _routeRepository is RestorableRouteRepository) {
        final saved = await _routeRepository.readCachedCatalog();
        if (_disposed || request != _routesRequest) return;
        if (saved != null) {
          _catalog = saved;
          routesLoading = false;
          notifyListeners();
        }
      }
      final catalog = await _routeRepository.loadCatalog();
      if (_disposed || request != _routesRequest) return;
      _catalog = catalog;
      if (!matchingRoutes.any((r) => r.id == _selectedRouteId)) {
        _selectedRouteId = null;
      }
    } catch (_) {
      if (_disposed || request != _routesRequest) return;
      _catalog = RouteCatalog();
      // Keep the journey intent; only a valid catalog can revoke its route ID.
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

  List<Jeepney> get vehicles => offline
      ? _vehicles
            .map((v) => v.withRetrieval(v.retrievedAt, cached: true))
            .toList()
      : _vehicles;
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
    _pollTimer?.cancel();
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
        _failures = offline ? _failures + 1 : 0;
        _schedulePoll();
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    unawaited(_subscription.cancel());
    // The app composition root owns and disposes the repository.
    super.dispose();
  }
}
