import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/auth_controller.dart';
import '../auth/passenger_auth.dart';
import '../domain/passenger_route.dart';
import 'favorite_repository.dart';

class FavoriteController extends ChangeNotifier {
  FavoriteController({required this.auth, required this.repository}) {
    auth?.addListener(_accountChanged);
    _accountChanged();
  }
  final AuthController? auth;
  final FavoriteRepository? repository;
  List<FavoriteRoute> items = const [];
  String? error;
  bool loading = false;
  bool loaded = false;
  final Set<String> pending = {};
  String? _account;
  int _generation = 0;
  bool _disposed = false;
  bool get signedIn => auth?.user != null;
  bool get enabled => repository != null;
  bool contains(String id) => items.any((f) => f.route.id == id);
  void _accountChanged() {
    final id = auth?.user?.id;
    if (_account == id) return;
    _account = id;
    _generation++;
    items = const [];
    pending.clear();
    error = null;
    loaded = false;
    loading = false;
    if (!_disposed) notifyListeners();
    if (id != null && enabled) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (!signedIn || !enabled || loading || pending.isNotEmpty) return;
    final generation = _generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await auth!.authenticated(repository!.list);
      if (generation != _generation || _disposed) return;
      items = List.unmodifiable(result);
      loaded = true;
    } catch (e) {
      if (generation == _generation && !_disposed) {
        error = e is AuthFailure
            ? e.message
            : 'Could not load favorites. Please retry.';
      }
    } finally {
      if (generation == _generation && !_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> toggle(PassengerRoute route) async {
    if (!signedIn ||
        !enabled ||
        route.isDemo ||
        !loaded ||
        loading ||
        pending.contains(route.id)) {
      return;
    }
    final generation = _generation;
    final removing = contains(route.id);
    pending.add(route.id);
    error = null;
    notifyListeners();
    try {
      await auth!.authenticated(
        (token) => removing
            ? repository!.remove(token, route.id)
            : repository!.save(token, route.id),
      );
      if (generation != _generation || _disposed) return;
      items = List.unmodifiable(
        removing
            ? items.where((f) => f.route.id != route.id)
            : [...items, FavoriteRoute(route: route, available: true)],
      );
    } catch (e) {
      if (generation == _generation && !_disposed) {
        error = e is AuthFailure
            ? e.message
            : 'Could not update favorites. Please retry.';
      }
    } finally {
      if (generation == _generation && !_disposed) {
        pending.remove(route.id);
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    auth?.removeListener(_accountChanged);
    repository?.dispose();
    super.dispose();
  }
}
