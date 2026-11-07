import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/passenger_auth.dart';
import '../domain/passenger_route.dart';

class FavoriteRoute {
  const FavoriteRoute({required this.route, required this.available});
  final PassengerRoute route;
  final bool available;
}

abstract interface class FavoriteRepository {
  Future<List<FavoriteRoute>> list(String token);
  Future<void> save(String token, String routeId);
  Future<void> remove(String token, String routeId);
  void dispose();
}

class ApiFavoriteRepository implements FavoriteRepository {
  ApiFavoriteRepository({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client() {
    validatePassengerOrigin(baseUrl);
  }
  final Uri baseUrl;
  final http.Client _client;
  final Duration timeout;
  static final _id = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  Future<http.Response> _request(
    String method,
    String token, [
    String? id,
  ]) async {
    if (id != null && !_id.hasMatch(id)) {
      throw const AuthFailure(
        'This route cannot be saved. Refresh registered routes.',
      );
    }
    try {
      final request =
          http.Request(
              method,
              baseUrl.resolve('/api/favorites${id == null ? '' : '/$id'}'),
            )
            ..followRedirects = false
            ..headers['Authorization'] = 'Bearer $token'
            ..headers['Accept'] = 'application/json';
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
      if (response.statusCode == 401) {
        throw const AuthFailure(
          'Your session has expired. Please log in again.',
          unauthorized: true,
        );
      }
      if (response.statusCode == 409) {
        throw const AuthFailure(
          'This route is no longer available. Refresh routes before saving.',
        );
      }
      if ((method == 'GET' && response.statusCode != 200) ||
          (method != 'GET' && response.statusCode != 204)) {
        throw const AuthFailure('Could not update favorites. Please retry.');
      }
      return response;
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure(
        'Could not reach favorites. Check your connection and retry.',
      );
    }
  }

  @override
  Future<List<FavoriteRoute>> list(String token) async {
    final response = await _request('GET', token);
    try {
      final rows = jsonDecode(response.body)['data'];
      if (rows is! List) throw const FormatException();
      final ids = <String>{};
      return rows.map((row) {
        if (row is! Map ||
            row['routeId'] is! String ||
            !_id.hasMatch(row['routeId']) ||
            row['available'] is! bool ||
            !ids.add(row['routeId'])) {
          throw const FormatException();
        }
        return FavoriteRoute(
          route: PassengerRoute(
            id: row['routeId'],
            origin: Municipality.values.firstWhere(
              (m) => m.label == row['origin'],
            ),
            destination: Municipality.values.firstWhere(
              (m) => m.label == row['destination'],
            ),
          ),
          available: row['available'],
        );
      }).toList();
    } catch (_) {
      throw const AuthFailure('Favorites response is invalid. Please retry.');
    }
  }

  @override
  Future<void> save(String token, String routeId) async {
    await _request('PUT', token, routeId);
  }

  @override
  Future<void> remove(String token, String routeId) async {
    await _request('DELETE', token, routeId);
  }

  @override
  void dispose() => _client.close();
}
