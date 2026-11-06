import 'package:battle_map/map_import.dart';
import 'package:test/test.dart';

import '../../helpers/import_fixtures.dart';

void main() {
  group('boundsOf', () {
    test('holds every corner of the map, with a margin', () {
      final (south, west, north, east) = boundsOf(testSpec);

      for (final (x, y) in [(0.0, 0.0), (10.0, 0.0), (0.0, 8.0), (10.0, 8.0)]) {
        final (lon, lat) = at(x, y);
        expect(lon, inExclusiveRange(west, east));
        expect(lat, inExclusiveRange(south, north));
      }
      expect(north - south, lessThan(0.02));
    });
  });

  test('overpassQuery asks for every key the rules read, with geometry', () {
    final query = overpassQuery(testSpec);
    final (south, west, north, east) = boundsOf(testSpec);
    final box = [
      south,
      west,
      north,
      east,
    ].map((value) => value.toStringAsFixed(6)).join(',');

    expect(query, startsWith('[out:json][timeout:600];('));
    expect(query, endsWith(');out geom;'));
    for (final key in testSpec.keys) {
      expect(query, contains('nwr["$key"]($box);'));
    }
  });

  group('elevationRequests', () {
    test('asks the IGN WMS for one 32-bit height per cell, in strips', () {
      final requests = elevationRequests(testSpec, maxRows: 3);

      expect(
        [for (final r in requests) (r.firstRow, r.rows)],
        [(0, 3), (3, 3), (6, 2)],
      );
      final last = requests.last.uri;
      expect(last.origin, 'https://data.geopf.fr');
      expect(last.queryParameters, {
        'SERVICE': 'WMS',
        'VERSION': '1.3.0',
        'REQUEST': 'GetMap',
        'LAYERS': rgeAltiLayer,
        'STYLES': 'normal',
        'CRS': 'EPSG:2154',
        'BBOX': '400000.0,6899920.0,400100.0,6899940.0',
        'WIDTH': '10',
        'HEIGHT': '2',
        'FORMAT': 'image/x-bil;bits=32',
      });
      expect(elevationRequests(testSpec), hasLength(1));
    });

    test('refuses a map wider than the WMS serves', () {
      final wide = ImportSpec.parse(
        testImportYaml.replaceFirst('width: 10', 'width: 5001'),
      );

      expect(() => elevationRequests(wide), throwsArgumentError);
    });
  });
}
