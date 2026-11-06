import 'dart:typed_data';

import 'package:battle_map/map_import.dart';

/// A small import file: 10 × 8 cells of 10 m from 400 km E, 6,900 km N,
/// with a rule of each kind.
const testImportYaml = '''
version: 1
name: test_area
elevation: ign_rge_alti
origin: [400000, 6900000]
width: 10
depth: 8
cell_size_m: 10
tile_size: 4
terrain_index: [grass, forest_floor, road, town_street, river, lake]
ground: grass
areas:
  - {tags: {landuse: forest}, terrain: forest_floor}
  - {tags: {landuse: residential}, terrain: town_street}
  - {tags: {natural: water}, terrain: lake}
lines:
  - {tags: {waterway: river}, terrain: river, width_m: 10}
  - {tags: {highway: primary}, terrain: road, width_m: 10, bridge: reinforced_bridge}
  - {tags: {highway: track}, terrain: road, width_m: 10}
objects:
  - {tags: {building: '*'}, type: building, shape: area, not_on: [road]}
  - {tags: {natural: tree}, type: tree, shape: point}
  - {tags: {barrier: hedge}, type: tree, shape: line, each_cell: true}
  - {tags: {landuse: forest}, type: tree, shape: area, each_cell: true}
  - {tags: {barrier: wall}, type: wall, shape: area}
teams:
  2: [[0, 0], [9, 7]]
relics: [[1, 7], [2, 7], [3, 7], [4, 7], [5, 7, sky]]
''';

/// The test import file.
final ImportSpec testSpec = ImportSpec.parse(testImportYaml);

/// The longitude and latitude of the point [x] columns east and [y] rows
/// south of the test area's north-west corner.
LonLat at(double x, double y) => const Lambert93().unproject(
  testSpec.originX + x * testSpec.cellSizeM,
  testSpec.originY - y * testSpec.cellSizeM,
);

var _id = 0;

/// A way through [points], in cells of the test area.
OsmElement way(Map<String, String> tags, List<(double, double)> points) =>
    OsmElement(
      type: OsmType.way,
      id: ++_id,
      tags: tags,
      paths: [
        [for (final (x, y) in points) at(x, y)],
      ],
    );

/// A closed way around the cells from ([x], [y]), [width] × [depth].
OsmElement area(
  Map<String, String> tags,
  double x,
  double y,
  double width,
  double depth,
) => way(tags, [
  (x, y),
  (x + width, y),
  (x + width, y + depth),
  (x, y + depth),
  (x, y),
]);

/// A node at ([x], [y]), in cells of the test area.
OsmElement node(Map<String, String> tags, double x, double y) => OsmElement(
  type: OsmType.node,
  id: ++_id,
  tags: tags,
  paths: [
    [at(x, y)],
  ],
);

/// The test area's heights as BIL, all [metres] but those of [set].
Uint8List bil({double metres = 0, Map<int, double> set = const {}}) {
  final cells = testSpec.width * testSpec.depth;
  final data = ByteData(cells * 4);
  for (var index = 0; index < cells; index++) {
    data.setFloat32(index * 4, set[index] ?? metres, Endian.little);
  }
  return data.buffer.asUint8List();
}

/// The test area imported from [elements] and [elevation].
MapImport importTest(List<OsmElement> elements, {Uint8List? elevation}) =>
    importMap(
      spec: testSpec,
      elevationBil: elevation ?? bil(metres: 10),
      osm: OsmExtract(elements: elements, timestamp: '2026-11-05T21:12:51Z'),
      water: const {'river', 'lake'},
      elevationFetched: '2026-11-05',
    );
