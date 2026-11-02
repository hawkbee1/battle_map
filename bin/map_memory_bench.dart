import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:battle_map/battle_map.dart';
import 'package:battle_pathfinding/battle_pathfinding.dart';
import 'package:battle_rules/battle_rules.dart';

const _usage = '''
Measures the memory of one loaded 10 × 50 km synthetic map (stack decisions 1
and 5): 1,000 × 5,000 cells of 10 m and about 200,000 objects.

Usage: dart run battle_map:map_memory_bench <plan> [--tiles]
  <plan>    the plan folder (apps/battle_team/plan), for terrain.yaml
  --tiles   also time writing the map as tiles and loading them back''';

void main(List<String> arguments) {
  if (arguments case [final plan, ...final flags]
      when flags.every((flag) => flag == '--tiles')) {
    _measure(plan, tiles: flags.isNotEmpty);
  } else {
    stderr.writeln(_usage);
    exitCode = 64;
  }
}

void _measure(String plan, {required bool tiles}) {
  final terrain = TerrainData.parse(
    File('$plan/data/terrain.yaml').readAsStringSync(),
  );
  final map = _syntheticMap();
  final loader = HostMapLoader(terrain);
  // The ground alone first, then the whole map: RSS only grows, so the
  // objects cost the second growth minus the first.
  final start = ProcessInfo.currentRss;
  final ground = loader.make(
    MapData(
      spec: map.spec,
      width: map.width,
      depth: map.depth,
      heights: map.heights,
      terrain: map.terrain,
      features: const MapFeatures(),
    ),
  );
  final groundRss = ProcessInfo.currentRss;
  final before = ProcessInfo.currentRss;
  final clock = Stopwatch()..start();
  final host = loader.make(map);
  final makeMs = clock.elapsedMilliseconds;
  final after = ProcessInfo.currentRss;
  stdout
    ..writeln('cells: ${map.width} × ${map.depth}')
    ..writeln('objects: ${host.objects.length}')
    ..writeln('make: $makeMs ms')
    ..writeln('ground alone: ${_mb(groundRss - start)}')
    ..writeln('objects: ${_mb(after - before - (groundRss - start))}')
    ..writeln('RSS before: ${_mb(before)}, after: ${_mb(after)}')
    ..writeln(
      'loaded map: ${_mb(after - before)} (RSS growth, an upper bound)',
    );
  if (tiles) {
    clock.reset();
    final built = map.toBuilt();
    final writeMs = clock.elapsedMilliseconds;
    clock.reset();
    HostMapLoader(terrain).load(built);
    stdout
      ..writeln('tiles: ${built.tiles.length}, written in $writeMs ms')
      ..writeln('load from tiles: ${clock.elapsedMilliseconds} ms');
  }
  // Keeps the map alive until it is measured.
  if (host.navigation.width + ground.navigation.width == 0) {
    stdout.writeln(host);
  }
}

String _mb(int bytes) => '${(bytes / 1000000).toStringAsFixed(1)} MB';

/// Rolling heights, roads every 800 m, a river, forests with one tree per
/// forest cell up to 150,000, and a building every 100 cells of grass:
/// about 200,000 objects.
MapData _syntheticMap() {
  const width = 1000;
  const depth = 5000;
  const index = ['grass', 'forest_floor', 'road', 'mud', 'mountain', 'river'];
  final heights = Uint16List(width * depth);
  final terrain = Uint8List(width * depth);
  final features = <MapFeature>[];
  final random = math.Random(1);
  var trees = 0;
  for (var y = 0; y < depth; y++) {
    for (var x = 0; x < width; x++) {
      final height =
          (20 +
                  15 * math.sin(x / 97) * math.cos(y / 131) +
                  6 * math.sin(y / 29))
              .round();
      final texture =
          math.sin(x / 13) * math.cos(y / 17) + random.nextDouble() * 0.3;
      final kind = (y - depth / 2 - 40 * math.sin(x / 50)).abs() < 2.5
          ? 5
          : x % 80 == 0 || y % 80 == 0
          ? 2
          : height > 38
          ? 4
          : texture > 0.6
          ? 1
          : texture < -0.9
          ? 3
          : 0;
      heights[y * width + x] = height;
      terrain[y * width + x] = kind;
      if (kind == 1 && trees < 150000) {
        trees++;
        features.add(
          MapFeature(
            kind: FeatureKind.object,
            type: 'tree',
            cells: [CellRef(x, y)],
          ),
        );
      } else if (kind == 0 && (x * 31 + y * 17) % 100 == 0) {
        features.add(
          MapFeature(
            kind: FeatureKind.object,
            type: 'building',
            cells: [CellRef(x, y)],
          ),
        );
      }
    }
  }
  return MapData(
    spec: const MapSpec(
      name: 'synthetic',
      cellSizeM: 10,
      terrainIndex: index,
      teams: {},
      relics: [],
    ),
    width: width,
    depth: depth,
    heights: heights,
    terrain: terrain,
    features: MapFeatures(features: features),
  );
}
