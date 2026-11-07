import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class PassengerProfile {
  const PassengerProfile({
    required this.id,
    required this.fullName,
    required this.email,
  });
  final String id;
  final String fullName;
  final String email;
  factory PassengerProfile.parse(dynamic data) {
    if (data is! Map ||
        data['role'] != 'PASSENGER' ||
        data['id'] is! String ||
        data['fullName'] is! String ||
        data['email'] is! String) {
      throw const AuthFailure('Invalid account response. Please try again.');
    }
    return PassengerProfile(
      id: data['id'],
      fullName: data['fullName'],
      email: data['email'],
    );
  }
}

class PassengerSession {
  const PassengerSession({
    required this.user,
    required this.expiresAt,
    this.token,
  });
  final PassengerProfile user;
  final DateTime expiresAt;
  final String? token;
}

class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.unauthorized = false});
  final String message;
  final bool unauthorized;
  @override
  String toString() => message;
}

abstract interface class PassengerAuthRepository {
  Future<PassengerSession> login(String email, String password);
  Future<PassengerSession> register(String name, String email, String password);
  Future<PassengerSession> restore(String token);
  Future<PassengerProfile> updateName(String token, String name);
  Future<void> logout(String token);
  void dispose();
}

class ApiPassengerAuthRepository implements PassengerAuthRepository {
  ApiPassengerAuthRepository({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client() {
    validatePassengerOrigin(baseUrl);
  }
  final Uri baseUrl;
  final http.Client _client;
  final Duration timeout;

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? body,
    String? token,
  }) async {
    try {
      final request = http.Request(method, baseUrl.resolve('/api/auth/$path'))
        ..followRedirects = false
        ..headers['Accept'] = 'application/json';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
      if (response.statusCode == 204) return {};
      if (response.statusCode == 401) {
        throw AuthFailure(
          path == 'login'
              ? 'Email or password is incorrect.'
              : 'Your session has expired. Please sign in again.',
          unauthorized: path != 'login',
        );
      }
      if (response.statusCode == 409) {
        throw const AuthFailure(
          'Registration could not be completed with this email. Try signing in or use another email.',
        );
      }
      if (response.statusCode == 429) {
        throw const AuthFailure(
          'Too many attempts. Please wait 15 minutes and try again.',
        );
      }
      if (response.statusCode == 400) {
        throw const AuthFailure(
          'Please check your details. Use a valid email and a password of 15–128 characters.',
        );
      }
      if (response.statusCode == 403) {
        throw const AuthFailure(
          'Passenger account access is unavailable. Check the secure API configuration.',
        );
      }
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw const AuthFailure(
          'Account service unavailable. Please try again. You can continue as a guest.',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['data'] is! Map<String, dynamic>) {
        throw const FormatException();
      }
      return decoded['data'];
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure(
        'Could not reach the account service. Check your connection and try again.',
      );
    }
  }

  PassengerSession _session(
    Map<String, dynamic> data, {
    bool requireToken = false,
  }) {
    final expires = DateTime.tryParse(
      data['expiresAt'] is String ? data['expiresAt'] : '',
    );
    final token = data['token'];
    if (expires == null ||
        (requireToken &&
            (token is! String ||
                !RegExp(r'^aqp_[A-Za-z0-9_-]{43}$').hasMatch(token)))) {
      throw const AuthFailure('Invalid session response. Please try again.');
    }
    return PassengerSession(
      user: PassengerProfile.parse(data['user']),
      expiresAt: expires.toUtc(),
      token: token,
    );
  }

  @override
  Future<PassengerSession> login(String email, String password) async =>
      _session(
        await _request(
          'POST',
          'login',
          body: {'email': email.trim(), 'password': password},
        ),
        requireToken: true,
      );
  @override
  Future<PassengerSession> register(
    String name,
    String email,
    String password,
  ) async => _session(
    await _request(
      'POST',
      'register',
      body: {
        'fullName': name.trim(),
        'email': email.trim(),
        'password': password,
      },
    ),
    requireToken: true,
  );
  @override
  Future<PassengerSession> restore(String token) async =>
      _session(await _request('GET', 'me', token: token));
  @override
  Future<PassengerProfile> updateName(String token, String name) async =>
      PassengerProfile.parse(
        (await _request(
          'PATCH',
          'me',
          token: token,
          body: {'fullName': name.trim()},
        ))['user'],
      );
  @override
  Future<void> logout(String token) async {
    await _request('POST', 'logout', token: token);
  }

  @override
  void dispose() => _client.close();
}

void validatePassengerOrigin(Uri baseUrl) {
  if (baseUrl.userInfo.isNotEmpty ||
      baseUrl.hasQuery ||
      baseUrl.hasFragment ||
      !baseUrl.hasAuthority ||
      (baseUrl.path.isNotEmpty && baseUrl.path != '/') ||
      !(baseUrl.scheme == 'https' ||
          (kDebugMode &&
              baseUrl.scheme == 'http' &&
              ['127.0.0.1', 'localhost', '10.0.2.2'].contains(baseUrl.host)))) {
    throw ArgumentError(
      'Authentication requires HTTPS outside local debug builds.',
    );
  }
}
