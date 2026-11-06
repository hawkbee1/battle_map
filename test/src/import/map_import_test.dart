import 'dart:typed_data';

import 'package:battle_map/battle_map.dart';
import 'package:battle_map/map_import.dart';
import 'package:battle_pathfinding/battle_pathfinding.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/import_fixtures.dart';

String terrainAt(MapData map, int x, int y) =>
    map.spec.terrainIndex[map.terrain[y * map.width + x]];

List<MapFeature> ofType(MapData map, String type) => [
  for (final feature in map.features.features)
    if (feature.type == type) feature,
];

Set<(int, int)> cellsOf(Iterable<MapFeature> features) => {
  for (final feature in features)
    for (final cell in feature.cells) (cell.x, cell.y),
};

/// A river down column 5, three cells wide with a `width` tag.
OsmElement river({String? width}) =>
    way({'waterway': 'river', 'width': ?width}, [(5.5, -1), (5.5, 9)]);

void main() {
  group('importMap', () {
    test('takes the heights in whole metres from zero, one per cell', () {
      final map = importTest(
        const [],
        elevation: bil(
          metres: 12.4,
          set: {1: -5, 2: -99999, 3: 70000, 4: 12.5},
        ),
      ).map;

      expect((map.width, map.depth), (10, 8));
      expect(map.heights.sublist(0, 6), [12, 0, 0, 0xFFFF, 13, 12]);
    });

    test('refuses an elevation file of the wrong size', () {
      expect(
        () => importTest(const [], elevation: Uint8List(12)),
        throwsA(
          isA<MapFormatException>()
              .having((error) => error.file, 'file', elevationFile)
              .having(
                (error) => error.problem,
                'problem',
                'holds 12 bytes, not 10 × 8 32-bit heights',
              ),
        ),
      );
    });

    test('paints areas in rule order; an element takes its first rule', () {
      final result = importTest([
        area({'landuse': 'forest'}, 0, 0, 4, 4),
        area({'landuse': 'residential'}, 2, 2, 4, 4),
        // Forest before water in the rules: this one is forest.
        area({'landuse': 'forest', 'natural': 'water'}, 8, 0, 2, 2),
        // A line is no area.
        way({'landuse': 'forest'}, [(6, 6), (9, 6), (9, 7)]),
      ]);
      final map = result.map;

      expect(terrainAt(map, 0, 0), 'forest_floor');
      expect(terrainAt(map, 3, 3), 'town_street');
      expect(terrainAt(map, 5, 5), 'town_street');
      expect(terrainAt(map, 8, 0), 'forest_floor');
      expect(terrainAt(map, 7, 6), 'grass');
      expect(
        result.report,
        contains('areas[0] landuse=forest → forest_floor: 2 areas, 20 cells'),
      );
    });

    test('paints lines at their width; land never covers water', () {
      final map = importTest([
        area({'natural': 'water'}, 0, 4, 3, 3),
        river(width: '30 m'),
        way({'highway': 'track'}, [(0.5, 5.5), (9.5, 5.5)]),
      ]).map;

      expect(
        [for (var x = 0; x < 10; x++) terrainAt(map, x, 0)],
        [
          ...List.filled(4, 'grass'),
          'river',
          'river',
          'river',
          ...List.filled(3, 'grass'),
        ],
      );
      expect(terrainAt(map, 1, 5), 'lake');
      expect(terrainAt(map, 5, 5), 'river');
      expect(terrainAt(map, 3, 5), 'road');
      expect(terrainAt(map, 8, 5), 'road');
      expect(ofType(map, 'reinforced_bridge'), isEmpty);
    });

    test('bridges the water a bridge way crosses, from land to land', () {
      final result = importTest([
        river(),
        way({'highway': 'primary', 'bridge': 'yes'}, [(2.5, 3.5), (8.5, 3.5)]),
        // No bridge type for tracks.
        way({'highway': 'track', 'bridge': 'yes'}, [(2.5, 5.5), (8.5, 5.5)]),
        // Not a bridge.
        way({'highway': 'primary', 'bridge': 'no'}, [(2.5, 1.5), (8.5, 1.5)]),
      ]);
      final bridges = ofType(result.map, 'reinforced_bridge');

      expect(bridges, hasLength(1));
      expect(bridges.single.kind, FeatureKind.construction);
      expect(bridges.single.cells, [const CellRef(5, 3)]);
      expect(terrainAt(result.map, 5, 1), 'river');
      expect(
        result.report,
        contains(
          'lines[1] highway=primary → reinforced_bridge: 1 bridges, '
          '0 crossings left without one',
        ),
      );
    });

    test('a bridge way that ends over water goes on along the road joined '
        'at its end', () {
      final map = importTest([
        river(width: '30'),
        way({'highway': 'primary'}, [(0.5, 3.5), (3.5, 3.5)]),
        way({'highway': 'primary', 'bridge': 'yes'}, [(3.5, 3.5), (5.5, 3.5)]),
        way({'highway': 'track'}, [(9.5, 3.5), (5.5, 3.5)]),
        // Starts over water, after a road.
        way({'highway': 'primary'}, [(0.5, 5.5), (5.5, 5.5)]),
        way({'highway': 'primary', 'bridge': 'yes'}, [(5.5, 5.5), (9.5, 5.5)]),
      ]).map;

      expect(ofType(map, 'reinforced_bridge').map((b) => b.cells), [
        for (final row in [3, 5])
          [CellRef(4, row), CellRef(5, row), CellRef(6, row)],
      ]);
    });

    test('leaves out the crossings with no land at an end, or across '
        'another bridge, and reports them', () {
      final result = importTest([
        river(width: '30'),
        area({'natural': 'water'}, 0, 6, 2, 2),
        way({'highway': 'primary', 'bridge': 'yes'}, [(2.5, 3.5), (8.5, 3.5)]),
        // The same crossing: one bridge.
        way({'highway': 'primary', 'bridge': 'yes'}, [(8.5, 3.5), (2.5, 3.5)]),
        // Ends over water.
        way({'highway': 'primary', 'bridge': 'yes'}, [(2.5, 1.5), (5.5, 1.5)]),
        // Starts over water.
        way({'highway': 'primary', 'bridge': 'yes'}, [(5.5, 0.5), (8.5, 0.5)]),
        // Comes from off the map.
        way({'highway': 'primary', 'bridge': 'yes'}, [(-2.5, 6.5), (3.5, 6.5)]),
        // Down the river onto the bridge of row 3.
        way(
          {'highway': 'primary', 'bridge': 'yes'},
          [(2.5, 2.5), (4.5, 2.5), (4.5, 3.5), (8.5, 3.5)],
        ),
      ]);

      expect(ofType(result.map, 'reinforced_bridge'), hasLength(1));
      expect(
        result.report,
        containsAllInOrder([
          endsWith(
            'reinforced_bridge: 1 bridges, 4 crossings left without one',
          ),
          matches(r'way \d+: water at \(4, 1\): no land at an end'),
          matches(r'way \d+: water at \(5, 0\): no land at an end'),
          matches(r'way \d+: water at \(0, 6\): no land at an end'),
          matches(r'way \d+: water at \(4, 2\): crosses a bridge'),
        ]),
      );
    });

    test('places objects at points, along lines and in areas, each on '
        'free land', () {
      final result = importTest([
        river(),
        way({'highway': 'track'}, [(0.5, 2.5), (9.5, 2.5)]),
        // Two cells, one of them on the road.
        area({'building': 'yes'}, 7, 1, 1, 2),
        // Too small to hold a cell's centre: on the cell of its middle.
        area({'building': 'house'}, 8.1, 5.1, 0.3, 0.3),
        // On water: nothing left.
        area({'building': 'yes'}, 5.1, 6.1, 0.3, 0.3),
        node({'natural': 'tree'}, 1.5, 1.5),
        // On a starting point.
        node({'natural': 'tree'}, 0.5, 0.5),
        // Along a line, one tree on each free cell.
        way({'barrier': 'hedge'}, [(3.5, 4.5), (7.5, 4.5)]),
        area({'landuse': 'forest'}, 0, 5, 2, 2),
        // An area rule on a line: nothing.
        way({'barrier': 'wall'}, [(0.5, 3.5), (2.5, 3.5)]),
      ]);
      final map = result.map;

      expect(ofType(map, 'building').map((b) => b.cells), [
        [const CellRef(7, 1)],
        [const CellRef(8, 5)],
      ]);
      expect(ofType(map, 'building').first.kind, FeatureKind.object);
      expect(cellsOf(ofType(map, 'tree')), {
        (1, 1),
        (3, 4),
        (4, 4),
        (6, 4),
        (7, 4),
        (0, 5),
        (1, 5),
        (0, 6),
        (1, 6),
      });
      expect(ofType(map, 'tree'), hasLength(9));
      expect(ofType(map, 'wall'), isEmpty);
      expect(
        result.report,
        contains('objects[0] building=* → building: 3 elements, 2 objects'),
      );
    });

    test('keeps the starting points, writes the attribution, and passes the '
        'builder', () {
      final result = importTest([
        river(),
        way({'highway': 'primary', 'bridge': 'yes'}, [(2.5, 3.5), (8.5, 3.5)]),
        area({'landuse': 'forest'}, 0, 0, 3, 3),
      ]);
      final spec = result.map.spec;

      expect(spec.name, 'test_area');
      expect(spec.teams, testSpec.teams);
      expect(spec.relics, testSpec.relics);
      expect(spec.attribution, [
        contains('© OpenStreetMap contributors, ODbL 1.0'),
        contains('IGN, RGE ALTI®, Licence Ouverte 2.0'),
      ]);
      expect(spec.attribution.first, endsWith('data of 2026-11-05T21:12:51Z.'));
      expect(spec.attribution.last, endsWith('fetched 2026-11-05.'));
      expect(
        result.report.last,
        'terrain cells: grass 57, forest_floor 9, road 6, town_street 0, '
        'river 8, lake 0',
      );
      expect(checkMap(result.map, parsePlanData()), [
        // The test area has no island sky for its fifth relic.
        isA<MapProblem>().having((p) => p.object, 'object', 'relics[4]'),
      ]);
    });
  });
}
