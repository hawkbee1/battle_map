import 'package:battle_map/battle_map.dart';
import 'package:battle_pathfinding/battle_pathfinding.dart';
import 'package:test/test.dart';

import '../helpers/fixtures.dart';

Matcher throwsFormat(String key, String problem) => throwsA(
  isA<MapFormatException>()
      .having((error) => error.key, 'key', key)
      .having((error) => error.problem, 'problem', contains(problem)),
);

void main() {
  group('MapSpec', () {
    MapSpec spec([Map<String, String> replace = const {}]) =>
        MapSpec.parse(readValley(mapFile, replace));

    test('MAP-02 MAP-03 reads the map file: cells, terrain index, HQ starts '
        'by team count, relics', () {
      final valley = spec();

      expect(valley.name, 'valley');
      expect(valley.cellSizeM, 10);
      expect(valley.tileSize, 4);
      expect(valley.terrainIndex.first, 'grass');
      expect(valley.teams.keys, [2, 3]);
      expect(valley.teams[2], [const CellRef(0, 0), const CellRef(11, 0)]);
      expect(valley.relics.last, const CellRef(9, 6, surface: 'sky'));
      expect((valley.width, valley.depth), (null, null));
    });

    test('tiles are 256 cells unless the map says otherwise', () {
      expect(spec({'tile_size: 4\n': ''}).tileSize, 256);
    });

    test('writes a built map file that reads back the same', () {
      final built = MapSpec.parse(spec().toYaml(width: 12, depth: 8));

      expect((built.width, built.depth), (12, 8));
      expect(built.teams, spec().teams);
      expect(built.relics, spec().relics);
      expect(built.terrainIndex, spec().terrainIndex);
    });

    test('a map with no team count or relic writes back too', () {
      const empty = MapSpec(
        name: 'empty',
        cellSizeM: 10,
        terrainIndex: ['grass'],
        teams: {},
        relics: [],
      );
      final again = MapSpec.parse(empty.toYaml(width: 1, depth: 1));

      expect(again.teams, isEmpty);
      expect(again.relics, isEmpty);
    });

    test('names the key of a file out of the format', () {
      for (final (replace, key, problem) in [
        ({'version: 1': 'version: 2'}, 'version', 'must be 1'),
        ({'name: valley\n': ''}, 'name', 'is missing'),
        ({'name: valley': 'name: 3'}, 'name', 'must be text'),
        ({'cell_size_m: 10': 'cell_size_m: ten'}, 'cell_size_m', 'number'),
        ({'tile_size: 4': 'tile_size: 0'}, 'tile_size', 'must be positive'),
        ({'tile_size: 4': 'tile_size: 2.5'}, 'tile_size', 'whole number'),
        ({'  2: ': '  two: '}, 'teams.two', 'whole numbers'),
        ({'[[0, 3], ': '[[0], '}, 'relics[0]', '[x, y] or [x, y, island]'),
        ({'[9, 6, sky]': '[9, 6, Sky]'}, 'relics[5][2]', 'must match'),
        (
          {
            'terrain_index: [grass, river, forest_floor, road, mountain, '
                    'floating_island_ground]':
                'terrain_index: grass',
          },
          'terrain_index',
          'must be a list',
        ),
      ]) {
        expect(() => spec(replace), throwsFormat(key, problem), reason: key);
      }
    });

    test('a file that is no YAML map is out of the format', () {
      expect(() => MapSpec.parse('- a'), throwsFormat('', 'must be a map'));
      expect(() => MapSpec.parse('a: ['), throwsA(isA<MapFormatException>()));
      expect(
        const MapFormatException(
          file: 'map.yaml',
          key: 'version',
          problem: 'must be 1',
        ).toString(),
        'map.yaml: version: must be 1',
      );
    });
  });

  group('MapFeatures', () {
    MapFeatures features([Map<String, String> replace = const {}]) =>
        MapFeatures.parse(readValley(objectsFile, replace));

    test('reads objects, constructions, links and floating islands', () {
      final valley = features();
      final kinds = [for (final feature in valley.features) feature.kind];

      expect(kinds.where((kind) => kind == FeatureKind.object), hasLength(4));
      expect(
        kinds.where((kind) => kind == FeatureKind.construction),
        hasLength(2),
      );
      final ladder = valley.features.firstWhere((f) => f.type == 'ladder');
      expect(ladder.cells, [
        const CellRef(7, 5),
        const CellRef(8, 5, surface: 'sky'),
      ]);
      expect(ladder.id, 'ladder@(7, 5)');
      expect(
        valley.features.firstWhere((f) => f.type == 'wall').armorType,
        'structure',
      );
      final sky = valley.islands.single;
      expect(
        (sky.name, sky.terrain, sky.heightM),
        ('sky', 'floating_island_ground', 60),
      );
      expect(sky.cells, hasLength(6));
    });

    test('every section is optional', () {
      final empty = MapFeatures.parse('{}');

      expect(empty.features, isEmpty);
      expect(empty.islands, isEmpty);
    });

    test('writes a features file that reads back the same', () {
      final again = MapFeatures.parse(features().toYaml());

      expect(
        [for (final f in again.features) (f.kind, f.id, f.armorType)],
        [for (final f in features().features) (f.kind, f.id, f.armorType)],
      );
      expect(again.islands.single.areas, [(8, 5, 3, 2)]);
      expect(const MapFeatures().toYaml(), contains('objects: []'));
      expect(MapFeatures.parse(const MapFeatures().toYaml()).features, isEmpty);
    });

    test('names the key of an area out of the format', () {
      expect(
        () => features({'[[8, 5, 3, 2]]': '[[8, 5, 3]]'}),
        throwsFormat('islands[0].areas[0]', 'must be [x, y, width, depth]'),
      );
      expect(
        () => features({'[[8, 5, 3, 2]]': '[[8, 5, 0, 2]]'}),
        throwsFormat('islands[0].areas[0][2]', 'must be positive'),
      );
    });
  });
}
