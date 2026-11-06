import 'dart:io';

import 'package:battle_map/battle_map.dart';
import 'package:battle_map/map_import.dart';
import 'package:battle_pathfinding/battle_pathfinding.dart';
import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';

/// The committed map saint_lo: the Vire valley through Saint-Lô, from
/// IGN RGE ALTI and OpenStreetMap, corrected by hand.
const builtPath = 'maps/built/saint_lo';
const importPath = 'maps/source/saint_lo/import.yaml';

BuiltMapFiles readBuilt(String folder) => BuiltMapFiles(
  mapYaml: File('$folder/$mapFile').readAsStringSync(),
  tiles: {
    for (final tile in Directory('$folder/tiles').listSync())
      if (tile is Directory)
        tile.uri.pathSegments.lastWhere((s) => s.isNotEmpty): TileFiles(
          heightsPng: File('${tile.path}/heights.png').readAsBytesSync(),
          terrainPng: File('${tile.path}/terrain.png').readAsBytesSync(),
          objectsYaml: File('${tile.path}/$objectsFile').readAsStringSync(),
        ),
  },
);

void main() {
  late GameData data;
  late BuiltMapFiles files;
  late MapData map;

  setUpAll(() {
    data = parsePlanData();
    files = readBuilt(builtPath);
    map = MapData.fromBuilt(files);
  });

  group('saint_lo', () {
    test('MAP-04 is 10 × 50 km: 1,000 × 5,000 cells of 10 m, in 80 tiles', () {
      expect((map.width, map.depth, map.spec.cellSizeM), (1000, 5000, 10));
      expect(files.tiles, hasLength(4 * 20));
    });

    test('passes every check of the builder', () {
      expect(checkMap(map, data), isEmpty);
    });

    test('MAP-02 defines ground, biomes, water, roads, towns, trees, '
        'buildings, bridges, the starting points of 2 to 5 teams and 8 '
        'relics', () {
      final cells = <String, int>{};
      for (final index in map.terrain) {
        final name = map.spec.terrainIndex[index];
        cells[name] = (cells[name] ?? 0) + 1;
      }
      final objects = <String, int>{};
      for (final feature in map.features.features) {
        objects[feature.type] = (objects[feature.type] ?? 0) + 1;
      }

      for (final terrain in [
        'grass',
        'forest_floor',
        'mud',
        'road',
        'town_street',
        'river',
        'lake',
      ]) {
        expect(cells[terrain], greaterThan(1000), reason: terrain);
      }
      for (final type in ['tree', 'building', 'wall', 'bridge']) {
        expect(objects[type], greaterThan(10), reason: type);
      }
      expect(objects['reinforced_bridge'], greaterThan(10));
      expect(map.spec.teams.keys, [2, 3, 4, 5]);
      expect(map.spec.relics, hasLength(8));
    });

    test('MAP-01 is authored: the import of its file, starting points '
        'placed by hand, a bridge reinforced by hand for the north HQ', () {
      final spec = ImportSpec.parse(File(importPath).readAsStringSync());

      expect(map.spec.name, spec.name);
      expect(map.spec.teams, spec.teams);
      expect(map.spec.relics, spec.relics);
      expect(
        map.features.features.where(
          (feature) =>
              feature.id == 'reinforced_bridge@${const CellRef(499, 256)}',
        ),
        hasLength(1),
      );
    });

    test('credits its sources as their licences require', () {
      expect(map.spec.attribution, [
        contains('© OpenStreetMap contributors, ODbL 1.0'),
        contains('IGN, RGE ALTI®, Licence Ouverte 2.0'),
      ]);
    });

    test('MAP-05 loads in the host', () {
      final host = HostMapLoader(data.terrain).load(files);

      expect((host.navigation.width, host.navigation.depth), (1000, 5000));
      expect(host.objects, hasLength(map.features.features.length));
      expect(host.hqStarts[5], hasLength(5));
      expect(host.relicStarts, hasLength(8));
    });
  });
}
