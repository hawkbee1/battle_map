import 'dart:typed_data';

import 'package:battle_map/src/map_format.dart';
import 'package:battle_pathfinding/battle_pathfinding.dart';
import 'package:image/image.dart' as img;

/// {@template tile_files}
/// The three files of one tile: its 16-bit height image, its indexed
/// terrain image and its features file (stack decision 5).
/// {@endtemplate}
final class TileFiles {
  /// {@macro tile_files}
  const new({
    required this.heightsPng,
    required this.terrainPng,
    required this.objectsYaml,
  });

  /// `heights.png`: one 16-bit value per cell, in metres above the map's
  /// base.
  final Uint8List heightsPng;

  /// `terrain.png`: one palette index per cell, into the map's
  /// `terrain_index`.
  final Uint8List terrainPng;

  /// `objects.yaml`: the features whose first cell is in the tile, and the
  /// islands whose first area starts in it.
  final String objectsYaml;
}

/// {@template built_map_files}
/// A built map: its map file and its tiles, by tile name `<column>_<row>`
/// (`tiles/<name>/` on disk).
/// {@endtemplate}
final class BuiltMapFiles {
  /// {@macro built_map_files}
  const new({required this.mapYaml, required this.tiles});

  /// The map file.
  final String mapYaml;

  /// The tiles, by name.
  final Map<String, TileFiles> tiles;
}

/// {@template map_data}
/// A whole map in memory: its [spec], its size in cells, one height and one
/// terrain index per cell, row by row, and its [features].
/// {@endtemplate}
final class MapData {
  /// {@macro map_data}
  ///
  /// Throws an [ArgumentError] when [heights] or [terrain] does not hold
  /// [width] × [depth] cells.
  new({
    required this.spec,
    required this.width,
    required this.depth,
    required this.heights,
    required this.terrain,
    required this.features,
  }) {
    for (final (name, length) in [
      ('heights', heights.length),
      ('terrain', terrain.length),
    ]) {
      if (length != width * depth) {
        throw ArgumentError.value(length, name, 'must hold width × depth');
      }
    }
  }

  /// A source map: its map file, its whole-map height and terrain images
  /// and its features file (stack decision 5, authoring). Throws a
  /// [MapFormatException] for a file out of the format.
  factory fromSource({
    required String mapYaml,
    required Uint8List heightsPng,
    required Uint8List terrainPng,
    required String objectsYaml,
  }) {
    final heights = decodeHeights(heightsPng, file: 'heights.png');
    final terrain = decodeTerrain(terrainPng, file: 'terrain.png');
    if (terrain.width != heights.width || terrain.depth != heights.depth) {
      throw MapFormatException(
        file: 'terrain.png',
        key: '',
        problem:
            'is ${terrain.width} × ${terrain.depth}, '
            'heights.png ${heights.width} × ${heights.depth}',
      );
    }
    return MapData(
      spec: MapSpec.parse(mapYaml),
      width: heights.width,
      depth: heights.depth,
      heights: heights.values,
      terrain: terrain.values,
      features: MapFeatures.parse(objectsYaml),
    );
  }

  /// A built map, its tiles put back together. Throws a
  /// [MapFormatException] for a missing tile or a tile of the wrong size.
  factory fromBuilt(BuiltMapFiles files) {
    final spec = MapSpec.parse(files.mapYaml);
    final width =
        spec.width ??
        (throw const MapFormatException(
          file: mapFile,
          key: 'width',
          problem: 'is missing in a built map',
        ));
    final depth =
        spec.depth ??
        (throw const MapFormatException(
          file: mapFile,
          key: 'depth',
          problem: 'is missing in a built map',
        ));
    final heights = Uint16List(width * depth);
    final terrain = Uint8List(width * depth);
    final features = <MapFeature>[];
    final islands = <MapIsland>[];
    final size = spec.tileSize;
    for (final (column, row) in tilesOf(width, depth, size)) {
      final name = '${column}_$row';
      final tile =
          files.tiles[name] ??
          (throw MapFormatException(
            file: 'tiles/$name',
            key: '',
            problem: 'is missing',
          ));
      final tileWidth = _span(column, size, width);
      final tileDepth = _span(row, size, depth);
      final tileHeights = decodeHeights(
        tile.heightsPng,
        file: 'tiles/$name/heights.png',
      );
      final tileTerrain = decodeTerrain(
        tile.terrainPng,
        file: 'tiles/$name/terrain.png',
      );
      for (final (layer, file) in [
        (tileHeights, 'heights.png'),
        (tileTerrain, 'terrain.png'),
      ]) {
        if (layer.width != tileWidth || layer.depth != tileDepth) {
          throw MapFormatException(
            file: 'tiles/$name/$file',
            key: '',
            problem: 'must be $tileWidth × $tileDepth',
          );
        }
      }
      for (var y = 0; y < tileDepth; y++) {
        final into = (row * size + y) * width + column * size;
        heights.setRange(
          into,
          into + tileWidth,
          tileHeights.values,
          y * tileWidth,
        );
        terrain.setRange(
          into,
          into + tileWidth,
          tileTerrain.values,
          y * tileWidth,
        );
      }
      final tileFeatures = MapFeatures.parse(
        tile.objectsYaml,
        file: 'tiles/$name/$objectsFile',
      );
      features.addAll(tileFeatures.features);
      islands.addAll(tileFeatures.islands);
    }
    return MapData(
      spec: spec,
      width: width,
      depth: depth,
      heights: heights,
      terrain: terrain,
      features: MapFeatures(features: features, islands: islands),
    );
  }

  /// The map file, the cells' size and what the map places.
  final MapSpec spec;

  /// Columns, west to east.
  final int width;

  /// Rows, north to south.
  final int depth;

  /// The ground height of each cell, in metres, row by row.
  final Uint16List heights;

  /// The terrain index of each cell, row by row.
  final Uint8List terrain;

  /// The objects, constructions, links and islands.
  final MapFeatures features;

  /// The tile a ground column and row fall in, as `<column>_<row>`.
  String tileOf(int x, int y) => '${x ~/ spec.tileSize}_${y ~/ spec.tileSize}';

  /// This map written as tiles (stack decision 5).
  BuiltMapFiles toBuilt() {
    final size = spec.tileSize;
    final tiles = <String, TileFiles>{};
    for (final (column, row) in tilesOf(width, depth, size)) {
      final name = '${column}_$row';
      final tileWidth = _span(column, size, width);
      final tileDepth = _span(row, size, depth);
      final tileHeights = Uint16List(tileWidth * tileDepth);
      final tileTerrain = Uint8List(tileWidth * tileDepth);
      for (var y = 0; y < tileDepth; y++) {
        final from = (row * size + y) * width + column * size;
        tileHeights.setRange(y * tileWidth, (y + 1) * tileWidth, heights, from);
        tileTerrain.setRange(y * tileWidth, (y + 1) * tileWidth, terrain, from);
      }
      tiles[name] = TileFiles(
        heightsPng: encodeHeights(tileWidth, tileDepth, tileHeights),
        terrainPng: encodeTerrain(
          tileWidth,
          tileDepth,
          tileTerrain,
          colors: spec.terrainIndex.length,
        ),
        objectsYaml: MapFeatures(
          features: [
            for (final feature in features.features)
              if (_tileOfCell(feature.cells.first) == name) feature,
          ],
          islands: [
            for (final island in features.islands)
              if (tileOf(island.areas.first.$1, island.areas.first.$2) == name)
                island,
          ],
        ).toYaml(),
      );
    }
    return BuiltMapFiles(
      mapYaml: spec.toYaml(width: width, depth: depth),
      tiles: tiles,
    );
  }

  String _tileOfCell(CellRef cell) => tileOf(cell.x, cell.y);
}

/// The tiles of a [width] × [depth] map cut in tiles of [size] cells, as
/// column and row.
Iterable<(int, int)> tilesOf(int width, int depth, int size) sync* {
  for (var row = 0; row * size < depth; row++) {
    for (var column = 0; column * size < width; column++) {
      yield (column, row);
    }
  }
}

/// The cells of tile [index] along a side of [length] cells.
int _span(int index, int size, int length) =>
    length - index * size < size ? length - index * size : size;

/// A decoded layer: its size and its values, row by row.
typedef Layer<T> = ({int width, int depth, T values});

/// The heights of a 16-bit greyscale PNG. Throws a [MapFormatException]
/// naming [file] when it is not one.
Layer<Uint16List> decodeHeights(Uint8List png, {required String file}) {
  final image = _decode(png, file);
  if (image.format != img.Format.uint16 ||
      image.numChannels != 1 ||
      image.hasPalette) {
    throw MapFormatException(
      file: file,
      key: '',
      problem: 'must be a 16-bit greyscale PNG',
    );
  }
  final values = Uint16List(image.width * image.height);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      values[y * image.width + x] = image.getPixel(x, y).r.toInt();
    }
  }
  return (width: image.width, depth: image.height, values: values);
}

/// The palette indices of an indexed PNG. Throws a [MapFormatException]
/// naming [file] when it is not one.
Layer<Uint8List> decodeTerrain(Uint8List png, {required String file}) {
  final image = _decode(png, file);
  if (!image.hasPalette) {
    throw MapFormatException(
      file: file,
      key: '',
      problem: 'must be an indexed PNG',
    );
  }
  final values = Uint8List(image.width * image.height);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      values[y * image.width + x] = image.getPixelIndex(x, y);
    }
  }
  return (width: image.width, depth: image.height, values: values);
}

/// [heights], row by row, as a [width] × [depth] 16-bit greyscale PNG.
Uint8List encodeHeights(int width, int depth, Uint16List heights) {
  final image = img.Image(
    width: width,
    height: depth,
    format: img.Format.uint16,
    numChannels: 1,
  );
  for (var y = 0; y < depth; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelR(x, y, heights[y * width + x]);
    }
  }
  return img.encodePng(image);
}

/// [indices], row by row, as a [width] × [depth] indexed PNG with
/// [colors] palette entries, each a distinct grey for an image editor.
Uint8List encodeTerrain(
  int width,
  int depth,
  Uint8List indices, {
  required int colors,
}) {
  final palette = img.PaletteUint8(colors, 3);
  for (var index = 0; index < colors; index++) {
    final grey = index * 255 ~/ colors;
    palette.setRgb(index, grey, grey, grey);
  }
  final image = img.Image(width: width, height: depth, palette: palette);
  for (var y = 0; y < depth; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelIndex(x, y, indices[y * width + x]);
    }
  }
  return img.encodePng(image);
}

img.Image _decode(Uint8List png, String file) =>
    img.decodePng(png) ??
    (throw MapFormatException(file: file, key: '', problem: 'is not a PNG'));
