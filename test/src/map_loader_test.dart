import 'dart:typed_data';

import 'package:battle_map/battle_map.dart';
import 'package:battle_pathfinding/battle_pathfinding.dart';
import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../helpers/fixtures.dart';

/// Another side's product, to show the Factory Method: the client makes
/// meshes in M7; this one counts cells.
final class _CellCounter extends MapLoader<int> {
  const new();

  @override
  int make(MapData map) => map.width * map.depth;
}

void main() {
  late GameData data;
  late BuiltMapFiles built;
  late HostMap host;

  setUpAll(() {
    data = parsePlanData();
    built = (buildMap(valley(), data) as MapBuilt).files;
    host = HostMapLoader(data.terrain).load(built);
  });

  group('HostMapLoader', () {
    test('MAP-05 the committed valley is built, loaded and gives the expected '
        'NavigationMap', () {
      final map = host.navigation;

      expect((map.width, map.depth, map.cellSizeM), (12, 8, 10));
      expect(map.waterTerrains, {'river', 'lake'});
      final river = map.cellAt(const CellRef(5, 3))!;
      expect((river.height, river.terrain), (8, 'river'));
      expect(map.isWater(const CellRef(5, 3)), isTrue);
      expect(map.cellAt(const CellRef(2, 5))!.terrain, 'forest_floor');
      expect(map.cellAt(const CellRef(11, 7))!.height, 30);
      final sky = map.cellAt(const CellRef(9, 6, surface: 'sky'))!;
      expect((sky.height, sky.terrain), (60, 'floating_island_ground'));
      expect(map.islands['sky'], hasLength(6));
      expect(map.objectsAt(const CellRef(1, 4)), {'tree'});
      expect(map.objectsAt(const CellRef(9, 2)), {'building'});
      expect(map.constructionsAt(const CellRef(5, 1)), {'bridge'});
      expect(map.constructionsAt(const CellRef(7, 6)), {'road_segment'});
      expect(
        [for (final link in map.links) (link.kind, link.from, link.to)],
        [
          (
            LinkKind.ladder,
            const CellRef(7, 5),
            const CellRef(8, 5, surface: 'sky'),
          ),
          (
            LinkKind.reinforcedBridge,
            const CellRef(9, 4),
            const CellRef(9, 5, surface: 'sky'),
          ),
        ],
      );
    });

    test('equal cells are shared, so a big map stays small', () {
      final ground = host.navigation.ground;

      expect(identical(ground[0], ground[2]), isTrue);
    });

    test('MAP-10 MAP-40 each object has the HP of its type and its armour '
        'type', () {
      final objects = host.objects;

      expect(objects, hasLength(8));
      final tree = objects['tree@(1, 4)']!;
      expect(
        (tree.type, tree.kind, tree.hp, tree.armorType),
        ('tree', FeatureKind.object, 100, 'structure'),
      );
      expect(objects['building@(8, 2)']!.cells, hasLength(2));
      expect(objects['bridge@(5, 1)']!.hp, 200);
      expect(objects['reinforced_bridge@(9, 4)']!.hp, 400);
      expect(objects['ladder@(7, 5)']!.kind, FeatureKind.link);
    });

    test('RELIC-02 HQ-01 the starting points', () {
      expect(host.hqStarts[3], [
        const CellRef(0, 0),
        const CellRef(11, 0),
        const CellRef(0, 7),
      ]);
      expect(host.relicStarts, hasLength(6));
    });

    test('an unknown object type is out of the format', () {
      final map = MapData(
        spec: valley().spec,
        width: 1,
        depth: 1,
        heights: Uint16List(1),
        terrain: Uint8List(1),
        features: const MapFeatures(
          features: [
            MapFeature(
              kind: FeatureKind.object,
              type: 'shrub',
              cells: [CellRef(0, 0)],
            ),
          ],
        ),
      );

      expect(
        () => HostMapLoader(data.terrain).make(map),
        throwsA(isA<MapFormatException>()),
      );
    });
  });

  group('MapLoader', () {
    test('MAP-05 stack decision 7 one loader, each side making its own '
        'product', () {
      expect(const _CellCounter().load(built), 96);
    });
  });
}
