import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/jeepney.dart';
import '../domain/jeepney_repository.dart';

class JeepneyController extends ChangeNotifier {
  JeepneyController(this._repository, {this.apiMode = false}) {
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
  bool availableOnly = false;
  String query = '';
  String? error;
  bool _disposed = false;

  List<Jeepney> get vehicles => _vehicles;
  int get availableCount => _vehicles
      .where((vehicle) => vehicle.status == OccupancyStatus.available)
      .length;

  List<Jeepney> get filteredVehicles => _vehicles.where((vehicle) {
    final matchesStatus =
        !availableOnly || vehicle.status == OccupancyStatus.available;
    final text = '${vehicle.id} ${vehicle.name}'.toLowerCase();
    return matchesStatus && text.contains(query.trim().toLowerCase());
  }).toList();

  void setAvailableOnly(bool value) {
    availableOnly = value;
    notifyListeners();
  }

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
      await _repository.refresh();
    } catch (_) {
      if (!_disposed) error = 'Could not refresh jeepneys. Please try again.';
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
