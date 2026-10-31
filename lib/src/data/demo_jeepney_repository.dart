import 'dart:async';

import '../domain/jeepney.dart';
import '../domain/jeepney_repository.dart';

/// Fictional points near Boac. These are NOT stops or official routes.
abstract final class DemoScenario {
  static const center = GeoPoint(13.4463, 121.8398);

  static List<Jeepney> vehicles(int step, DateTime recordedAt) {
    final alternate = step.isOdd;
    return List.unmodifiable([
      Jeepney(
        id: 'DEMO-01',
        name: 'Demo jeepney 01',
        position: GeoPoint(13.4490 + (alternate ? .0003 : 0), 121.8374),
        reportedStatus: OccupancyStatus.available,
        recordedAt: recordedAt,
        source: DataSource.demo,
      ),
      Jeepney(
        id: 'DEMO-02',
        name: 'Demo jeepney 02',
        position: GeoPoint(13.4433, 121.8423 + (alternate ? .0003 : 0)),
        reportedStatus: OccupancyStatus.full,
        recordedAt: recordedAt,
        source: DataSource.demo,
      ),
      Jeepney(
        id: 'DEMO-03',
        name: 'Demo jeepney 03',
        position: GeoPoint(13.4512, 121.8445 - (alternate ? .0003 : 0)),
        reportedStatus: OccupancyStatus.available,
        recordedAt: recordedAt,
        source: DataSource.demo,
      ),
    ]);
  }
}

/// Advances only on an explicit refresh. No fake live connection or timers.
class DemoJeepneyRepository implements JeepneyRepository {
  DemoJeepneyRepository({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final _updates = StreamController<List<Jeepney>>.broadcast();
  int _step = 0;
  bool _disposed = false;

  @override
  Stream<List<Jeepney>> watchJeepneys() => Stream.multi((listener) {
    if (_disposed) {
      listener.close();
      return;
    }
    final subscription = _updates.stream.listen(
      listener.add,
      onError: listener.addError,
      onDone: listener.close,
    );
    listener.add(DemoScenario.vehicles(_step, _clock()));
    listener.onCancel = subscription.cancel;
  });

  @override
  Future<void> refresh() async {
    if (!_disposed) {
      _updates.add(DemoScenario.vehicles(++_step, _clock()));
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _updates.close();
  }
}
