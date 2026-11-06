import 'dart:typed_data';

import 'package:battle_map/battle_map.dart';
import 'package:test/test.dart';

import '../helpers/fixtures.dart';

Matcher throwsFormatIn(String file, String problem) => throwsA(
  isA<MapFormatException>()
      .having((error) => error.file, 'file', file)
      .having((error) => error.problem, 'problem', contains(problem)),
);

void main() {
  group('MapData', () {
    test('reads a source map: its images give its size, heights and '
        'terrain', () {
      final map = valley();

      expect((map.width, map.depth), (12, 8));
      // The river down column 5, the mountain in the south-east corner.
      expect(map.heights[5], 8);
      expect(map.spec.terrainIndex[map.terrain[5]], 'river');
      expect(map.heights[7 * 12 + 11], 30);
      expect(map.tileOf(11, 7), '2_1');
    });

    test('the layers must hold every cell', () {
      expect(
        () => MapData(
          spec: valley().spec,
          width: 2,
          depth: 2,
          heights: Uint16List(4),
          terrain: Uint8List(3),
          features: const MapFeatures(),
        ),
        throwsArgumentError,
      );
    });

    test('the images must be a 16-bit greyscale PNG and an indexed PNG of '
        'one size', () {
      MapData source({Uint8List? heights, Uint8List? terrain}) =>
          MapData.fromSource(
            mapYaml: readValley(mapFile),
            heightsPng: heights ?? readValleyBytes('heights.png'),
            terrainPng: terrain ?? readValleyBytes('terrain.png'),
            objectsYaml: readValley(objectsFile),
          );

      expect(
        () => source(heights: Uint8List.fromList([1, 2, 3])),
        throwsFormatIn('heights.png', 'is not a PNG'),
      );
      expect(
        () => source(heights: readValleyBytes('terrain.png')),
        throwsFormatIn('heights.png', '16-bit greyscale'),
      );
      expect(
        () => source(terrain: readValleyBytes('heights.png')),
        throwsFormatIn('terrain.png', 'indexed'),
      );
      expect(
        () => source(terrain: encodeTerrain(2, 2, Uint8List(4), colors: 6)),
        throwsFormatIn('terrain.png', 'heights.png 12 × 8'),
      );
    });

    test('stack decision 5 the map is cut into tiles and put back together '
        'the same', () {
      final map = valley();
      final built = map.toBuilt();
      final again = MapData.fromBuilt(built);

      expect(built.tiles.keys, ['0_0', '1_0', '2_0', '0_1', '1_1', '2_1']);
      expect(again.heights, map.heights);
      expect(again.terrain, map.terrain);
      expect(again.spec.width, 12);
      expect(
        [for (final feature in again.features.features) feature.id]..sort(),
        [for (final feature in map.features.features) feature.id]..sort(),
      );
      expect(again.features.islands.single.name, 'sky');
      // The ladder from (7, 5) is in tile 1_1, the island's corner in 2_1.
      expect(built.tiles['1_1']!.objectsYaml, contains('ladder'));
      expect(built.tiles['2_1']!.objectsYaml, contains('name: sky'));
    });

    test('edge tiles are smaller when the map is not a whole number of '
        'tiles', () {
      expect(tilesOf(5, 3, 4), [(0, 0), (1, 0)]);
      final map = valley(map: {'tile_size: 4': 'tile_size: 5'});
      final again = MapData.fromBuilt(map.toBuilt());

      expect(map.toBuilt().tiles.keys, [
        '0_0',
        '1_0',
        '2_0',
        '0_1',
        '1_1',
        '2_1',
      ]);
      expect(again.heights, map.heights);
    });

    test('a built map gives its size, every tile, each of its size', () {
      final built = valley().toBuilt();
      BuiltMapFiles withMap(String mapYaml) =>
          BuiltMapFiles(mapYaml: mapYaml, tiles: built.tiles);
      final tile = built.tiles['0_0']!;

      expect(
        () => MapData.fromBuilt(withMap(readValley(mapFile))),
        throwsFormatIn(mapFile, 'is missing in a built map'),
      );
      expect(
        () => MapData.fromBuilt(
          withMap(built.mapYaml.replaceFirst('depth: 8\n', '')),
        ),
        throwsFormatIn(mapFile, 'is missing in a built map'),
      );
      expect(
        () => MapData.fromBuilt(
          BuiltMapFiles(
            mapYaml: built.mapYaml,
            tiles: {...built.tiles}..remove('1_0'),
          ),
        ),
        throwsFormatIn('tiles/1_0', 'is missing'),
      );
      expect(
        () => MapData.fromBuilt(
          BuiltMapFiles(
            mapYaml: built.mapYaml,
            tiles: {
              ...built.tiles,
              '0_0': TileFiles(
                heightsPng: encodeHeights(2, 2, Uint16List(4)),
                terrainPng: tile.terrainPng,
                objectsYaml: tile.objectsYaml,
              ),
            },
          ),
        ),
        throwsFormatIn('tiles/0_0/heights.png', 'must be 4 × 4'),
      );
    });

    test('stack decision 5 writes a source map that reads back the same, to '
        'correct a built map by hand', () {
      final map = MapData.fromBuilt(valley().toBuilt());
      final files = map.toSource();
      final again = MapData.fromSource(
        mapYaml: files.mapYaml,
        heightsPng: files.heightsPng,
        terrainPng: files.terrainPng,
        objectsYaml: files.objectsYaml,
      );

      expect(files.mapYaml, isNot(contains('width')));
      expect((again.width, again.depth), (12, 8));
      expect(again.heights, map.heights);
      expect(again.terrain, map.terrain);
      expect(again.features.toYaml(), map.features.toYaml());
    });
  });
}
