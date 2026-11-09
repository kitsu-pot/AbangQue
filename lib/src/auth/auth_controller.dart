import 'dart:async';

import 'package:flutter/foundation.dart';

import 'passenger_auth.dart';
import 'session_store.dart';

class AuthController extends ChangeNotifier {
  AuthController({required this.repository, required this.store});
  final PassengerAuthRepository? repository;
  final SessionStore store;
  PassengerProfile? user;
  StoredSession? _saved;
  bool busy = false;
  bool restoring = false;
  bool guest = false;
  String? error;
  bool _disposed = false;
  Timer? _expiry;
  bool get enabled => repository != null;
  bool get entered => guest || user != null;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void continueAsGuest() {
    if (busy && !restoring) return;
    guest = true;
    _notify();
  }

  void openSignIn() {
    if (busy) return;
    guest = false;
    error = null;
    _notify();
  }

  void clearError() {
    error = null;
    _notify();
  }

  void _accept(PassengerSession session, String token) {
    if (_disposed) return;
    if (!session.expiresAt.isAfter(DateTime.now())) {
      throw const AuthFailure(
        'Your session has expired. Please sign in again.',
        unauthorized: true,
      );
    }
    _saved = StoredSession(token, session.expiresAt);
    user = session.user;
    guest = false;
    _expiry?.cancel();
    _expiry = Timer(session.expiresAt.difference(DateTime.now()), () {
      // Expired tokens are unusable server-side. Disk cleanup happens on next restore.
      user = null;
      _saved = null;
      guest = true;
      error = 'Your session has expired. Please sign in again.';
      _notify();
    });
  }

  Future<void> _forget() async {
    user = null;
    _saved = null;
    _expiry?.cancel();
    await store.clear();
  }

  String _message(Object e) => e is AuthFailure
      ? e.message
      : 'Secure session storage is unavailable. Please retry. Guest access is still available.';
  Future<void> restore() async {
    if (busy || !enabled) return;
    busy = true;
    restoring = true;
    error = null;
    _notify();
    try {
      final saved = await store.read();
      if (_disposed) return;
      _saved = saved;
      if (saved == null) {
        user = null;
        _expiry?.cancel();
        return;
      }
      if (!saved.expiresAt.isAfter(DateTime.now())) {
        await _forget();
        return;
      }
      if (saved.pendingLogout) {
        await repository!.logout(saved.token);
        await _forget();
        return;
      }
      final session = await repository!.restore(saved.token);
      if (!_disposed && !guest) _accept(session, saved.token);
    } catch (e) {
      if (_disposed) return;
      // A failed network check is not proof that the verified session expired.
      // Cold starts still have no user until the server verifies the stored token.
      if (e is AuthFailure && e.unauthorized) {
        try {
          await _forget();
        } catch (_) {
          /* Server has already invalidated it. */
        }
      }
      error = _message(e);
    } finally {
      busy = false;
      restoring = false;
      _notify();
    }
  }

  Future<void> authenticate({
    required String email,
    required String password,
    String? name,
  }) async {
    if (busy || !enabled) return;
    busy = true;
    error = null;
    _notify();
    try {
      // Finish a failed offline logout before replacing its stored token.
      final previous = await store.read();
      if (previous != null && previous.pendingLogout) {
        await repository!.logout(previous.token);
        await store.clear();
      }
      final session = name == null
          ? await repository!.login(email, password)
          : await repository!.register(name, email, password);
      final saved = StoredSession(session.token!, session.expiresAt);
      try {
        await store.write(saved);
      } catch (_) {
        // Do not enter a persistent account if its credential cannot be stored.
        try {
          await repository!.logout(saved.token);
        } catch (_) {
          /* Expires server-side. */
        }
        rethrow;
      }
      _accept(session, saved.token);
    } catch (e) {
      error = _message(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  /// Tokens stay inside the account/API boundary, never in presentation or preferences.
  Future<T> authenticated<T>(Future<T> Function(String token) action) async {
    final saved = _saved;
    if (user == null ||
        saved == null ||
        saved.pendingLogout ||
        !saved.expiresAt.isAfter(DateTime.now())) {
      throw const AuthFailure(
        'Please log in to access your favorites.',
        unauthorized: true,
      );
    }
    try {
      return await action(saved.token);
    } on AuthFailure catch (e) {
      if (e.unauthorized && _saved?.token == saved.token) {
        try {
          await _forget();
        } catch (_) {
          /* Removed from memory even if storage fails. */
        }
        guest = true;
        error = e.message;
        _notify();
      }
      rethrow;
    }
  }

  Future<void> updateName(String name) async {
    final saved = _saved;
    if (busy || saved == null || user == null) return;
    busy = true;
    error = null;
    _notify();
    try {
      final updated = await repository!.updateName(saved.token, name);
      if (!_disposed && _saved?.token == saved.token) user = updated;
    } catch (e) {
      if (e is AuthFailure && e.unauthorized) {
        try {
          await _forget();
        } catch (_) {
          /* Still signed out in memory. */
        }
        guest = true;
      }
      error = _message(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> logout() async {
    final saved = _saved;
    if (busy || saved == null) return;
    busy = true;
    error = null;
    _notify();
    try {
      // Durable tombstone prevents restoring the session after offline logout.
      _saved = StoredSession(saved.token, saved.expiresAt, pendingLogout: true);
      await store.write(_saved!);
      user = null;
      guest = false;
      _expiry?.cancel();
      _notify();
      try {
        await repository!.logout(saved.token);
      } catch (_) {
        error = 'Signed out on this device. Server logout is pending. Reconnect and retry session recovery, or continue as a guest.';
        return;
      }
      await _forget();
    } catch (e) {
      error = _message(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _expiry?.cancel();
    repository?.dispose();
    super.dispose();
  }
}
