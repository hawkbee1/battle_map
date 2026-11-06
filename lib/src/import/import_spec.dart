import 'package:battle_map/src/map_format.dart';
import 'package:battle_map/src/yaml_reader.dart';
import 'package:battle_pathfinding/battle_pathfinding.dart';

/// The name of an import file.
const importFile = 'import.yaml';

/// The version of the import file this package reads.
const importFormatVersion = 1;

/// The elevation sources the importer reads (stack decision 5): IGN RGE
/// ALTI for France, in Lambert-93.
const elevationSources = {'ign_rge_alti'};

/// {@template tag_filter}
/// Which OpenStreetMap elements a rule takes: each key of [tags] must be
/// on the element with one of its values; a null set takes any value
/// (`'*'` in the file).
/// {@endtemplate}
final class TagFilter {
  /// {@macro tag_filter}
  const new(this.tags);

  /// The keys, and the values each key may have; null for any value.
  final Map<String, Set<String>?> tags;

  /// Whether the element tagged [elementTags] passes.
  bool matches(Map<String, String> elementTags) => tags.entries.every((tag) {
    final value = elementTags[tag.key];
    return value != null && (tag.value?.contains(value) ?? true);
  });

  @override
  String toString() => [
    for (final MapEntry(:key, :value) in tags.entries)
      '$key=${value?.join('|') ?? '*'}',
  ].join(',');
}

/// {@template area_rule}
/// Paints the cells inside the areas that pass [filter] with [terrain].
/// {@endtemplate}
final class AreaRule {
  /// {@macro area_rule}
  const new({required this.filter, required this.terrain});

  /// The areas it paints.
  final TagFilter filter;

  /// Their terrain type.
  final String terrain;
}

/// {@template line_rule}
/// Paints the cells along the lines that pass [filter] with [terrain],
/// [widthM] wide unless the line has a `width` tag. With a [bridge] type,
/// the parts of those lines tagged `bridge` that cross water become
/// bridges of that type.
/// {@endtemplate}
final class LineRule {
  /// {@macro line_rule}
  const new({
    required this.filter,
    required this.terrain,
    required this.widthM,
    this.bridge,
  });

  /// The lines it paints.
  final TagFilter filter;

  /// Their terrain type.
  final String terrain;

  /// Their width, in metres, when they have no `width` tag.
  final double widthM;

  /// The object type of their bridges over water; null for none.
  final String? bridge;
}

/// Where an object rule puts objects.
enum ObjectShape {
  /// On the cell of a node, or of the middle of a way.
  point,

  /// On the cells along a way.
  line,

  /// On the cells inside an area; on the cell of its middle when it covers
  /// none.
  area,
}

/// {@template object_rule}
/// Puts objects of [type] on the elements that pass [filter], at their
/// [shape]: one object on all its cells, or one on each cell with
/// [eachCell]. Never on water, on a cell of a terrain in [notOn], on a
/// cell another object holds, or on a starting point.
/// {@endtemplate}
final class ObjectRule {
  /// {@macro object_rule}
  const new({
    required this.filter,
    required this.type,
    required this.shape,
    this.eachCell = false,
    this.notOn = const {},
  });

  /// The elements it takes.
  final TagFilter filter;

  /// The object type, a key of `terrain.yaml` `objects`.
  final String type;

  /// Point, line or area.
  final ObjectShape shape;

  /// One object on each cell, rather than one on all of them.
  final bool eachCell;

  /// The terrain types it leaves free.
  final Set<String> notOn;
}

/// {@template import_spec}
/// An import file (stack decision 5, authoring step 1): the area to take
/// from real data, the map it becomes, the rules that turn OpenStreetMap
/// elements into terrain and objects, and the starting points placed by
/// hand (authoring step 3).
///
/// The map covers [width] × [depth] cells of [cellSizeM] from its
/// north-west corner ([originX], [originY]) in Lambert-93 metres; its
/// heights come from [elevation]. Each cell starts as [ground]; [areas],
/// then [lines], are painted in order, a later rule over an earlier one,
/// but land never over water. An element takes the first rule it passes
/// in each list. The [objects] are placed last, in order.
/// {@endtemplate}
final class ImportSpec {
  /// {@macro import_spec}
  const new({
    required this.name,
    required this.elevation,
    required this.originX,
    required this.originY,
    required this.width,
    required this.depth,
    required this.cellSizeM,
    required this.tileSize,
    required this.terrainIndex,
    required this.ground,
    required this.areas,
    required this.lines,
    required this.objects,
    required this.teams,
    required this.relics,
  });

  /// Reads an import file. Throws a [MapFormatException] naming the key.
  factory parse(String text, {String file = importFile}) {
    final root = YamlReader.parse(file, text);
    final version = root.child('version');
    if (version.integer != importFormatVersion) {
      version.fail('must be $importFormatVersion');
    }
    final elevation = root.child('elevation');
    if (!elevationSources.contains(elevation.string)) {
      elevation.fail('must be one of ${elevationSources.join(', ')}');
    }
    final terrainIndex = [
      for (final item in root.child('terrain_index').items) item.string,
    ];
    String terrain(YamlReader node) => terrainIndex.contains(node.string)
        ? node.string
        : node.fail('is not in terrain_index');
    List<YamlReader> list(String key) =>
        root.has(key) ? root.child(key).items : const [];
    final origin = root.child('origin').items;
    if (origin.length != 2) root.child('origin').fail('must be [x, y]');
    return ImportSpec(
      name: root.child('name').string,
      elevation: elevation.string,
      originX: origin[0].number,
      originY: origin[1].number,
      width: root.child('width').positive,
      depth: root.child('depth').positive,
      cellSizeM: root.child('cell_size_m').number,
      tileSize: root.has('tile_size') ? root.child('tile_size').positive : 256,
      terrainIndex: terrainIndex,
      ground: terrain(root.child('ground')),
      areas: [
        for (final node in list('areas'))
          AreaRule(
            filter: _filter(node.child('tags')),
            terrain: terrain(node.child('terrain')),
          ),
      ],
      lines: [
        for (final node in list('lines'))
          LineRule(
            filter: _filter(node.child('tags')),
            terrain: terrain(node.child('terrain')),
            widthM: node.child('width_m').number,
            bridge: node.has('bridge') ? node.child('bridge').string : null,
          ),
      ],
      objects: [
        for (final node in list('objects'))
          ObjectRule(
            filter: _filter(node.child('tags')),
            type: node.child('type').string,
            shape: switch (node.child('shape').string) {
              'point' => ObjectShape.point,
              'line' => ObjectShape.line,
              'area' => ObjectShape.area,
              _ => node.child('shape').fail('must be point, line or area'),
            },
            eachCell: node.has('each_cell') && node.child('each_cell').boolean,
            notOn: node.has('not_on')
                ? {for (final item in node.child('not_on').items) terrain(item)}
                : const {},
          ),
      ],
      teams: {
        for (final (count, starts) in root.child('teams').entries)
          int.tryParse(count) ?? starts.fail('team counts are whole numbers'): [
            for (final start in starts.items) start.cell,
          ],
      },
      relics: [for (final relic in root.child('relics').items) relic.cell],
    );
  }

  /// The map's name.
  final String name;

  /// Where its heights come from: one of [elevationSources].
  final String elevation;

  /// The easting of its west edge, in Lambert-93 metres.
  final double originX;

  /// The northing of its north edge, in Lambert-93 metres.
  final double originY;

  /// Its columns, west to east.
  final int width;

  /// Its rows, north to south.
  final int depth;

  /// The side of a cell, in metres.
  final double cellSizeM;

  /// The side of a tile, in cells.
  final int tileSize;

  /// The terrain type of each index of the terrain image.
  final List<String> terrainIndex;

  /// The terrain of the cells no rule paints.
  final String ground;

  /// The area rules, in painting order.
  final List<AreaRule> areas;

  /// The line rules, in painting order, after the areas.
  final List<LineRule> lines;

  /// The object rules, in placing order.
  final List<ObjectRule> objects;

  /// The HQ starting points, one per team, by team count.
  final Map<int, List<CellRef>> teams;

  /// The relics' starting cells.
  final List<CellRef> relics;

  /// The OpenStreetMap keys the rules read.
  Set<String> get keys => {
    for (final filter in [
      ...areas.map((rule) => rule.filter),
      ...lines.map((rule) => rule.filter),
      ...objects.map((rule) => rule.filter),
    ])
      ...filter.tags.keys,
  };

  static TagFilter _filter(YamlReader node) => TagFilter({
    for (final (key, values) in node.entries)
      key: values.value == '*' ? null : values.strings.toSet(),
  });
}
