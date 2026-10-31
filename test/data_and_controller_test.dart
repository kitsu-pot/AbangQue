import 'package:flutter_test/flutter_test.dart';
import 'package:jeeplink/src/data/demo_jeepney_repository.dart';
import 'package:jeeplink/src/domain/jeepney.dart';
import 'package:jeeplink/src/presentation/jeepney_controller.dart';

import 'fakes.dart';

Future<void> flushEvents() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'demo snapshots are labeled and occupancy is internally consistent',
    () async {
      final now = DateTime.utc(2026, 10, 31);
      final repository = DemoJeepneyRepository(clock: () => now);
      final first = await repository.watchJeepneys().first;
      expect(first, hasLength(3));
      expect(first.map((v) => v.id).toSet(), hasLength(3));
      expect(
        first.every((v) => v.source == DataSource.demo && v.recordedAt == now),
        isTrue,
      );
      expect(
        first
            .where((v) => v.status == OccupancyStatus.full)
            .single
            .availableSeats,
        0,
      );
      expect(
        first.where((v) => v.status == OccupancyStatus.available),
        hasLength(2),
      );
      expect(() => first.clear(), throwsUnsupportedError);
      await repository.dispose();
    },
  );

  test(
    'refresh advances the simulator and new subscribers get current data',
    () async {
      final repository = DemoJeepneyRepository();
      final events = <List<Jeepney>>[];
      final subscription = repository.watchJeepneys().listen(events.add);
      await flushEvents();
      await repository.refresh();
      await flushEvents();
      expect(events, hasLength(2));
      expect(events[0].first.eta, const Duration(minutes: 4));
      expect(events[1].first.eta, const Duration(minutes: 5));
      expect(events[1].first.availableSeats, 6);
      final latest = await repository.watchJeepneys().first;
      expect(
        latest.first.position!.latitude,
        events[1].first.position!.latitude,
      );
      await subscription.cancel();
      await repository.dispose();
      await repository.dispose();
      expect(await repository.watchJeepneys().isEmpty, isTrue);
    },
  );

  test(
    'controller combines search and availability and handles errors',
    () async {
      final repository = TestRepository();
      final controller = JeepneyController(repository);
      expect(controller.loading, isTrue);
      repository.updates.add(DemoScenario.vehicles(0, DateTime.utc(2026)));
      await flushEvents();
      expect(controller.loading, isFalse);
      expect(controller.availableCount, 2);
      controller.setQuery('  demo-02  ');
      expect(controller.filteredVehicles.single.status, OccupancyStatus.full);
      controller.setAvailableOnly(true);
      expect(controller.filteredVehicles, isEmpty);
      controller.setQuery('');
      expect(controller.filteredVehicles, hasLength(2));
      repository.updates.addError(StateError('Disconnected'));
      await flushEvents();
      expect(controller.error, isNotNull);
      expect(controller.vehicles, hasLength(3));
      repository.failRefresh = true;
      await controller.refresh();
      expect(controller.error, contains('Could not refresh'));
      expect(controller.refreshing, isFalse);
      repository.failRefresh = false;
      repository.next = DemoScenario.vehicles(1, DateTime.utc(2026));
      await controller.refresh();
      await flushEvents();
      expect(controller.error, isNull);
      expect(controller.vehicles.first.eta, const Duration(minutes: 5));
      controller.dispose();
      await repository.dispose();
    },
  );

  test(
    'a source closing before its first snapshot leaves loading state',
    () async {
      final repository = TestRepository();
      final controller = JeepneyController(repository);
      await repository.dispose();
      await flushEvents();
      expect(controller.loading, isFalse);
      expect(controller.error, isNotNull);
      controller.dispose();
    },
  );
}
