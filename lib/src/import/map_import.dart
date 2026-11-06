import 'dart:typed_data';

import 'package:battle_map/src/import/import_spec.dart';
import 'package:battle_map/src/import/lambert93.dart';
import 'package:battle_map/src/import/osm.dart';
import 'package:battle_map/src/import/raster.dart';
import 'package:battle_map/src/map_data.dart';
import 'package:battle_map/src/map_format.dart';
import 'package:battle_pathfinding/battle_pathfinding.dart';

/// The name of the elevation file: one little-endian 32-bit float per
/// cell, in metres, row by row from the north-west corner (BIL).
const elevationFile = 'elevation.bil';

/// The name of the OpenStreetMap file: an Overpass API answer.
const osmFile = 'osm.json';

/// Below this, an elevation is "no data" (IGN writes -99999).
const _noData = -1000.0;

/// {@template map_import}
/// What the importer made: the [map], as a source map to correct by hand,
/// and its [report], one line per rule and per kind of feature, for the
/// author.
/// {@endtemplate}
final class MapImport {
  /// {@macro map_import}
  const new({required this.map, required this.report});

  /// The map.
  final MapData map;

  /// What each rule did, and what it left out.
  final List<String> report;
}

/// The attribution of a map made from IGN RGE ALTI heights fetched on
/// [elevationFetched] and OpenStreetMap data of [osmTimestamp]: their
/// licences ask for it (ODbL 1.0, Licence Ouverte 2.0).
List<String> attributionOf({
  required String osmTimestamp,
  required String elevationFetched,
}) {
  const osm =
      'Terrain, water, roads, buildings and trees: © OpenStreetMap '
      'contributors, ODbL 1.0 (https://www.openstreetmap.org/copyright)';
  const ign =
      'Heights: IGN, RGE ALTI®, Licence Ouverte 2.0 '
      '(https://www.etalab.gouv.fr/licence-ouverte-open-licence)';
  return ['$osm, data of $osmTimestamp.', '$ign, fetched $elevationFetched.'];
}

/// The first map from real data (stack decision 5, authoring step 1): the
/// area of [spec], its heights from [elevationBil] (whole metres, from
/// zero), its terrain and objects from [osm] by the rules of [spec], and
/// the starting points of [spec]. [water] names the water terrains:
/// land never covers them and objects never stand on them. Throws a
/// [MapFormatException] when [elevationBil] does not hold one height per
/// cell.
MapImport importMap({
  required ImportSpec spec,
  required Uint8List elevationBil,
  required OsmExtract osm,
  required Set<String> water,
  required String elevationFetched,
}) => _Importer(spec, osm, water).run(elevationBil, elevationFetched);

final class _Importer {
  new(this.spec, this.osm, Set<String> water)
    : terrain = Uint8List(spec.width * spec.depth)
        ..fillRange(
          0,
          spec.width * spec.depth,
          spec.terrainIndex.indexOf(spec.ground),
        ),
      water = {
        for (final (index, name) in spec.terrainIndex.indexed)
          if (water.contains(name)) index,
      };

  final ImportSpec spec;
  final OsmExtract osm;
  final Uint8List terrain;

  /// The terrain indices that are water.
  final Set<int> water;
  final report = <String>[];
  final features = <MapFeature>[];

  /// The cells an object or a starting point holds.
  final taken = <(int, int)>{};

  int get width => spec.width;
  int get depth => spec.depth;

  bool onMap((int, int) cell) =>
      cell.$1 >= 0 && cell.$2 >= 0 && cell.$1 < width && cell.$2 < depth;

  int indexOf((int, int) cell) => cell.$2 * width + cell.$1;

  bool isWater((int, int) cell) => water.contains(terrain[indexOf(cell)]);

  MapImport run(Uint8List elevationBil, String elevationFetched) {
    final heights = _heights(elevationBil);
    final projected = {
      for (final element in osm.elements) element: _project(element),
    };
    _paintAreas(projected);
    _paintLines(projected);
    _bridges(projected);
    for (final start in [
      ...spec.teams.values.expand((s) => s),
      ...spec.relics,
    ]) {
      if (start.surface == groundSurface) taken.add((start.x, start.y));
    }
    _objects(projected);
    _countTerrain();
    return MapImport(
      map: MapData(
        spec: MapSpec(
          name: spec.name,
          cellSizeM: spec.cellSizeM,
          tileSize: spec.tileSize,
          terrainIndex: spec.terrainIndex,
          teams: spec.teams,
          relics: spec.relics,
          attribution: attributionOf(
            osmTimestamp: osm.timestamp,
            elevationFetched: elevationFetched,
          ),
        ),
        width: width,
        depth: depth,
        heights: heights,
        terrain: terrain,
        features: MapFeatures(features: features),
      ),
      report: report,
    );
  }

  Uint16List _heights(Uint8List bil) {
    if (bil.length != width * depth * 4) {
      throw MapFormatException(
        file: elevationFile,
        key: '',
        problem:
            'holds ${bil.length} bytes, not $width × $depth 32-bit heights',
      );
    }
    final values = ByteData.sublistView(bil);
    return Uint16List.fromList([
      for (var index = 0; index < width * depth; index++)
        switch (values.getFloat32(index * 4, Endian.little)) {
          final metres when metres < _noData => 0,
          final metres => metres.round().clamp(0, 0xFFFF),
        },
    ]);
  }

  /// [element]'s paths in cells of the map.
  List<List<CellPoint>> _project(OsmElement element) {
    const lambert = Lambert93();
    return [
      for (final path in element.paths)
        [
          for (final (lon, lat) in path)
            if (lambert.project(lon, lat) case (final x, final y))
              (
                (x - spec.originX) / spec.cellSizeM,
                (spec.originY - y) / spec.cellSizeM,
              ),
        ],
    ];
  }

  /// The elements whose first rule in [filters] is the one at [rule].
  Iterable<OsmElement> _taking(
    Iterable<OsmElement> elements,
    List<TagFilter> filters,
    int rule,
  ) => elements.where((element) {
    final first = filters.indexWhere((f) => f.matches(element.tags));
    return first == rule;
  });

  /// Paints [cell] with [index]: land never covers water.
  bool _paint((int, int) cell, int index) {
    if (!water.contains(index) && isWater(cell)) return false;
    terrain[indexOf(cell)] = index;
    return true;
  }

  void _paintAreas(Map<OsmElement, List<List<CellPoint>>> projected) {
    final filters = [for (final rule in spec.areas) rule.filter];
    final areas = projected.keys.where((element) => element.isArea);
    for (final (index, rule) in spec.areas.indexed) {
      final paint = spec.terrainIndex.indexOf(rule.terrain);
      var count = 0;
      var cells = 0;
      for (final element in _taking(areas, filters, index)) {
        count++;
        for (final cell in cellsInside(
          projected[element]!,
          width: width,
          depth: depth,
        )) {
          if (_paint(cell, paint)) cells++;
        }
      }
      report.add(
        'areas[$index] ${rule.filter} → ${rule.terrain}: '
        '$count areas, $cells cells',
      );
    }
  }

  void _paintLines(Map<OsmElement, List<List<CellPoint>>> projected) {
    final filters = [for (final rule in spec.lines) rule.filter];
    final ways = projected.keys.where((e) => e.type == OsmType.way);
    for (final (index, rule) in spec.lines.indexed) {
      final paint = spec.terrainIndex.indexOf(rule.terrain);
      var count = 0;
      var cells = 0;
      for (final element in _taking(ways, filters, index)) {
        count++;
        final path = projected[element]!.single;
        final widthM = _widthOf(element) ?? rule.widthM;
        for (final cell in {
          ...cellsAlong(path).where(onMap),
          ...cellsNear(
            path,
            widthM / spec.cellSizeM / 2,
            width: width,
            depth: depth,
          ),
        }) {
          if (_paint(cell, paint)) cells++;
        }
      }
      report.add(
        'lines[$index] ${rule.filter} → ${rule.terrain}: '
        '$count lines, $cells cells',
      );
    }
  }

  /// The width a way's `width` tag gives, in metres; null without one.
  static double? _widthOf(OsmElement element) => double.tryParse(
    RegExp(r'^\s*([0-9.]+)').firstMatch(element.tags['width'] ?? '')?[1] ?? '',
  );

  /// Bridges where the ways of a line rule with a bridge type, tagged
  /// `bridge`, cross water: each stretch of water cells along the way,
  /// with land just before and just after it. A way that ends over water
  /// goes on along a way of the line rules joined at that end.
  void _bridges(Map<OsmElement, List<List<CellPoint>>> projected) {
    final filters = [for (final rule in spec.lines) rule.filter];
    final lines = [
      for (final element in projected.keys)
        if (element.type == OsmType.way &&
            filters.any((filter) => filter.matches(element.tags)))
          element,
    ];
    final byEnd = <LonLat, List<OsmElement>>{};
    for (final line in lines) {
      final path = line.paths.single;
      for (final end in {path.first, path.last}) {
        (byEnd[end] ??= []).add(line);
      }
    }
    final ways = lines.where(
      (way) => way.tags['bridge'] != null && way.tags['bridge'] != 'no',
    );
    final bridged = <(int, int)>{};
    for (final (index, rule) in spec.lines.indexed) {
      final type = rule.bridge;
      if (type == null) continue;
      var built = 0;
      final skipped = <String>[];
      for (final way in _taking(ways, filters, index)) {
        final path = way.paths.single;
        // The cells of the way joined at [end], from [end] when [from].
        List<(int, int)> joined(LonLat end, {required bool from}) {
          for (final other in byEnd[end]!) {
            if (identical(other, way)) continue;
            final points = projected[other]!.single;
            final startsThere = other.paths.single.first == end;
            return cellsAlong(
              startsThere == from ? points : points.reversed.toList(),
            );
          }
          return const [];
        }

        final before = joined(path.first, from: false);
        final own = cellsAlong(projected[way]!.single);
        final cells = <(int, int)>[];
        for (final cell in [
          ...before,
          ...own,
          ...joined(path.last, from: true),
        ]) {
          if (cells.isEmpty || cells.last != cell) cells.add(cell);
        }
        // The joints share a cell.
        final ownFirst = before.isEmpty ? 0 : before.length - 1;
        final ownLast = ownFirst + own.length - 1;
        bool water(int at) => onMap(cells[at]) && isWater(cells[at]);
        for (var start = ownFirst; start <= ownLast; start++) {
          if (!water(start) || (start > ownFirst && water(start - 1))) {
            continue;
          }
          var first = start;
          while (first > 0 && water(first - 1)) {
            first--;
          }
          var last = start;
          while (last + 1 < cells.length && water(last + 1)) {
            last++;
          }
          final span = cells.sublist(first, last + 1);
          final (x, y) = span.first;
          if (span.every(bridged.contains)) continue;
          if (first == 0 ||
              last + 1 == cells.length ||
              !onMap(cells[first - 1]) ||
              !onMap(cells[last + 1])) {
            skipped.add(
              '  way ${way.id}: water at ($x, $y): no land at an end',
            );
          } else if (span.any(bridged.contains)) {
            skipped.add('  way ${way.id}: water at ($x, $y): crosses a bridge');
          } else {
            bridged.addAll(span);
            features.add(
              MapFeature(
                kind: FeatureKind.construction,
                type: type,
                cells: [for (final (x, y) in span) CellRef(x, y)],
              ),
            );
            built++;
          }
        }
      }
      final crossings = skipped.length;
      report
        ..add(
          'lines[$index] ${rule.filter} → $type: $built bridges, '
          '$crossings crossings left without one',
        )
        ..addAll(skipped);
    }
  }

  void _objects(Map<OsmElement, List<List<CellPoint>>> projected) {
    final filters = [for (final rule in spec.objects) rule.filter];
    for (final (index, rule) in spec.objects.indexed) {
      final notOn = {
        for (final name in rule.notOn) spec.terrainIndex.indexOf(name),
      };
      bool free((int, int) cell) =>
          onMap(cell) &&
          !isWater(cell) &&
          !notOn.contains(terrain[indexOf(cell)]) &&
          !taken.contains(cell);
      var count = 0;
      var placed = 0;
      for (final element in _taking(projected.keys, filters, index)) {
        count++;
        final paths = projected[element]!;
        final cells = switch (rule.shape) {
          ObjectShape.point => [middleCell(paths)],
          ObjectShape.line => [for (final path in paths) ...cellsAlong(path)],
          ObjectShape.area when element.isArea => switch (cellsInside(
            paths,
            width: width,
            depth: depth,
          ).toList()) {
            final List<(int, int)> inside when inside.isNotEmpty => inside,
            _ => [middleCell(paths)],
          },
          ObjectShape.area => const <(int, int)>[],
        };
        final kept = <(int, int)>[];
        for (final cell in cells) {
          if (free(cell)) {
            taken.add(cell);
            kept.add(cell);
          }
        }
        if (kept.isEmpty) continue;
        for (final group
            in rule.eachCell
                ? [
                    for (final c in kept) [c],
                  ]
                : [kept]) {
          features.add(
            MapFeature(
              kind: FeatureKind.object,
              type: rule.type,
              cells: [for (final (x, y) in group) CellRef(x, y)],
            ),
          );
          placed++;
        }
      }
      report.add(
        'objects[$index] ${rule.filter} → ${rule.type}: '
        '$count elements, $placed objects',
      );
    }
  }

  void _countTerrain() {
    final counts = List.filled(spec.terrainIndex.length, 0);
    for (final index in terrain) {
      counts[index]++;
    }
    final cells = [
      for (final (index, name) in spec.terrainIndex.indexed)
        '$name ${counts[index]}',
    ];
    report.add('terrain cells: ${cells.join(', ')}');
  }
}
