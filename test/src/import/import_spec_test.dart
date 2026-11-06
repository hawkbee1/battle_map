import 'package:battle_map/battle_map.dart';
import 'package:battle_map/map_import.dart';
import 'package:battle_pathfinding/battle_pathfinding.dart';
import 'package:test/test.dart';

import '../../helpers/import_fixtures.dart';

Matcher throwsImport(String key, String problem) => throwsA(
  isA<MapFormatException>()
      .having((error) => error.file, 'file', importFile)
      .having((error) => error.key, 'key', key)
      .having((error) => error.problem, 'problem', contains(problem)),
);

String replaced(String from, String to) {
  expect(from.allMatches(testImportYaml), hasLength(1), reason: from);
  return testImportYaml.replaceFirst(from, to);
}

void main() {
  group('ImportSpec', () {
    test('reads the area, the rules and the starting points', () {
      final spec = testSpec;

      expect((spec.name, spec.elevation), ('test_area', 'ign_rge_alti'));
      expect((spec.originX, spec.originY), (400000, 6900000));
      expect(
        (spec.width, spec.depth, spec.cellSizeM, spec.tileSize),
        (10, 8, 10, 4),
      );
      expect(spec.terrainIndex, hasLength(6));
      expect(spec.ground, 'grass');
      expect(spec.areas.map((rule) => rule.terrain), [
        'forest_floor',
        'town_street',
        'lake',
      ]);
      final primary = spec.lines[1];
      expect(
        (primary.terrain, primary.widthM, primary.bridge),
        ('road', 10, 'reinforced_bridge'),
      );
      expect(spec.lines[2].bridge, isNull);
      final building = spec.objects.first;
      expect(
        (building.type, building.shape, building.eachCell),
        ('building', ObjectShape.area, false),
      );
      expect(building.notOn, {'road'});
      expect(spec.objects[1].shape, ObjectShape.point);
      expect(spec.objects[1].notOn, isEmpty);
      expect(
        (spec.objects[2].shape, spec.objects[2].eachCell),
        (ObjectShape.line, true),
      );
      expect(spec.teams[2], [const CellRef(0, 0), const CellRef(9, 7)]);
      expect(spec.relics.last, const CellRef(5, 7, surface: 'sky'));
      expect(spec.keys, {
        'landuse',
        'natural',
        'waterway',
        'highway',
        'building',
        'barrier',
      });
    });

    test('a filter takes the elements with every key, and any value for '
        '*', () {
      final building = testSpec.objects.first.filter;
      final primary = testSpec.lines[1].filter;
      const water = TagFilter({
        'natural': {'water'},
        'water': {'river', 'canal'},
      });

      expect(building.matches({'building': 'yes'}), isTrue);
      expect(building.matches({'highway': 'primary'}), isFalse);
      expect(primary.matches({'highway': 'primary'}), isTrue);
      expect(primary.matches({'highway': 'track'}), isFalse);
      expect(water.matches({'natural': 'water', 'water': 'canal'}), isTrue);
      expect(water.matches({'natural': 'water'}), isFalse);
      expect('$water', 'natural=water,water=river|canal');
      expect('$building', 'building=*');
    });

    test('defaults: tiles of 256 cells, no rules', () {
      final spec = ImportSpec.parse(
        testImportYaml
            .replaceFirst('tile_size: 4\n', '')
            .replaceFirst(RegExp(r'areas:[\s\S]*teams:'), 'teams:'),
      );

      expect(spec.tileSize, 256);
      expect(spec.areas, isEmpty);
      expect(spec.lines, isEmpty);
      expect(spec.objects, isEmpty);
    });

    test('refuses a file out of the format, naming the key', () {
      expect(
        () => ImportSpec.parse(replaced('version: 1', 'version: 2')),
        throwsImport('version', 'must be 1'),
      );
      expect(
        () => ImportSpec.parse(
          replaced('elevation: ign_rge_alti', 'elevation: copernicus'),
        ),
        throwsImport('elevation', 'must be one of ign_rge_alti'),
      );
      expect(
        () => ImportSpec.parse(
          replaced('origin: [400000, 6900000]', 'origin: [400000]'),
        ),
        throwsImport('origin', 'must be [x, y]'),
      );
      expect(
        () => ImportSpec.parse(replaced('ground: grass', 'ground: snow')),
        throwsImport('ground', 'is not in terrain_index'),
      );
      expect(
        () => ImportSpec.parse(
          replaced('type: tree, shape: point', 'type: tree, shape: blob'),
        ),
        throwsImport('objects[1].shape', 'must be point, line or area'),
      );
      expect(
        () => ImportSpec.parse(
          replaced('shape: line, each_cell: true', 'shape: line, each_cell: 1'),
        ),
        throwsImport('objects[2].each_cell', 'must be true or false'),
      );
      expect(
        () => ImportSpec.parse(replaced('  2: [[0, 0]', '  two: [[0, 0]')),
        throwsImport('teams.two', 'team counts are whole numbers'),
      );
    });
  });
}
