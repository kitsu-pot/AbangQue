import 'package:flutter_test/flutter_test.dart';
import 'package:jeeplink/src/data/api_route_repository.dart';

void main() {
  test('verified operational fields survive cache round trip without invented defaults', () {
    final data = {'routes': [{'id': 'verified', 'origin': 'Boac', 'destination': 'Gasan', 'isDemo': false, 'verifiedOperations': {'originTerminal': 'DEMO verified fixture', 'destinationTerminal': null, 'boardingNotes': 'DEMO boarding fixture'}}], 'assignments': []};
    final catalog = parseRouteCatalog(data, false);
    expect(catalog.routes.single.destinationTerminal, isNull);
    final restored = parseRouteCatalog(publicRouteJson(catalog), false);
    expect(restored.routes.single.originTerminal, 'DEMO verified fixture');
    expect(restored.routes.single.boardingNotes, 'DEMO boarding fixture');
    expect(parseRouteCatalog({'routes': [{'id': 'missing', 'origin': 'Boac', 'destination': 'Gasan', 'isDemo': false}], 'assignments': []}, false).routes.single.originTerminal, isNull);
  });
}
