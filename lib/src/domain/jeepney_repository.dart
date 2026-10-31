import 'jeepney.dart';

/// A future adapter can map REST polling, WebSocket, or MQTT backend events to
/// immutable snapshots. Widgets must never connect directly to GPS hardware.
abstract interface class JeepneyRepository {
  Stream<List<Jeepney>> watchJeepneys();
  Future<void> refresh();
  Future<void> dispose();
}
