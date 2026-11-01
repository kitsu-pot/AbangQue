import 'package:flutter_test/flutter_test.dart';
import 'package:jeeplink/src/data/demo_jeepney_repository.dart';
import 'package:jeeplink/src/domain/jeepney.dart';
import 'package:jeeplink/src/domain/passenger_route.dart';
import 'package:jeeplink/src/presentation/jeepney_controller.dart';

import 'fakes.dart';

Future<void> flushEvents() => Future<void>.delayed(Duration.zero);

void main() {
  test('demo snapshots use manual status examples and never ETA or fresh device reports', () async {
    final now = DateTime.utc(2026, 10, 31);
    final repository = DemoJeepneyRepository(clock: () => now);
    final first = await repository.watchJeepneys().first;
    expect(first, hasLength(3));
    expect(first.map((v) => v.id).toSet(), hasLength(3));
    expect(
      first.every((v) => v.source == DataSource.demo && v.recordedAt == now),
      isTrue,
    );
    expect(first.every((v) => v.eta == null && !v.hasFreshReport), isTrue);
    expect(first.where((v) => v.status == OccupancyStatus.full), hasLength(1));
    expect(
      first.where((v) => v.status == OccupancyStatus.available),
      hasLength(2),
    );
    expect(() => first.clear(), throwsUnsupportedError);
    await repository.dispose();
  });

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
      expect(events[0].first.eta, isNull);
      expect(events[1].first.eta, isNull);
      expect(
        events[1].first.position!.latitude,
        isNot(events[0].first.position!.latitude),
      );
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
    'controller scopes search to a selected route and handles errors',
    () async {
      final repository = TestRepository();
      final controller = JeepneyController(
        repository,
        routeRepository: TestRouteRepository(),
      );
      expect(controller.loading, isTrue);
      repository.updates.add(DemoScenario.vehicles(0, DateTime.utc(2026)));
      await flushEvents();
      expect(controller.loading, isFalse);
      expect(controller.filteredVehicles, isEmpty);
      controller.setOrigin(Municipality.boac);
      controller.setDestination(Municipality.gasan);
      controller.findJeepneys();
      controller.setQuery('  demo-02  ');
      expect(controller.filteredVehicles.single.status, OccupancyStatus.full);
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
      expect(controller.vehicles.first.eta, isNull);
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
