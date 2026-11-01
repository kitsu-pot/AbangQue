import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredSession {
  const StoredSession(this.token, this.expiresAt, {this.pendingLogout = false});
  final String token;
  final DateTime expiresAt;
  final bool pendingLogout;
  String encode() => jsonEncode({
    'token': token,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'pendingLogout': pendingLogout,
  });
  factory StoredSession.decode(String value) {
    final data = jsonDecode(value);
    if (data is! Map ||
        data['token'] is! String ||
        !RegExp(r'^aqp_[A-Za-z0-9_-]{43}$').hasMatch(data['token']) ||
        data['expiresAt'] is! String ||
        data['pendingLogout'] is! bool) {
      throw const FormatException();
    }
    return StoredSession(
      data['token'],
      DateTime.parse(data['expiresAt']).toUtc(),
      pendingLogout: data['pendingLogout'],
    );
  }
}

abstract interface class SessionStore {
  Future<StoredSession?> read();
  Future<void> write(StoredSession session);
  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  SecureSessionStore(Uri origin, {FlutterSecureStorage? storage})
    : _key = 'abangque.passenger.v1.${Uri.encodeComponent(origin.origin)}',
      _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );
  final FlutterSecureStorage _storage;
  final String _key;
  @override
  Future<StoredSession?> read() async {
    final value = await _storage.read(key: _key);
    if (value == null) return null;
    try {
      return StoredSession.decode(value);
    } on FormatException {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(StoredSession session) =>
      _storage.write(key: _key, value: session.encode());
  @override
  Future<void> clear() => _storage.delete(key: _key);
}
