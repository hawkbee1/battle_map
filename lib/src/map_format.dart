import 'package:battle_pathfinding/battle_pathfinding.dart';
import 'package:yaml/yaml.dart';

/// The name of the map file.
const mapFile = 'map.yaml';

/// The name of a features file: the whole map's in a source map, one per
/// tile in a built map.
const objectsFile = 'objects.yaml';

/// The version of the map format this package reads and writes.
const mapFormatVersion = 1;

/// Island names: letters, digits, `_` and `-`, so they stay plain YAML.
final _islandName = RegExp(r'^[a-z][a-z0-9_-]*$');

/// {@template map_format_exception}
/// A map file that does not follow the map format: in [file], at the
/// dotted [key], [problem].
/// {@endtemplate}
final class MapFormatException implements Exception {
  /// {@macro map_format_exception}
  const new({required this.file, required this.key, required this.problem});

  /// The file, for example `map.yaml` or `tiles/0_1/objects.yaml`.
  final String file;

  /// Where in the file, for example `teams.2`.
  final String key;

  /// What is wrong.
  final String problem;

  @override
  String toString() => '$file: $key: $problem';
}

/// {@template map_spec}
/// The map file (stack decision 5, MAP-02, MAP-03): its name, cell size,
/// tile size, the terrain type of each index of the terrain images, the
/// HQ starting points for each team count it supports (HQ-01) and the
/// relics' starting cells (RELIC-02). A built map also gives its size in
/// cells ([width], [depth]).
/// {@endtemplate}
final class MapSpec {
  /// {@macro map_spec}
  const new({
    required this.name,
    required this.cellSizeM,
    required this.terrainIndex,
    required this.teams,
    required this.relics,
    this.tileSize = 256,
    this.width,
    this.depth,
  });

  /// Reads a map file. Throws a [MapFormatException] naming the key.
  factory parse(String text, {String file = mapFile}) {
    final root = _Node.parse(file, text);
    final version = root.child('version').integer;
    if (version != mapFormatVersion) {
      root.child('version').fail('must be $mapFormatVersion');
    }
    return MapSpec(
      name: root.child('name').string,
      cellSizeM: root.child('cell_size_m').number,
      tileSize: root.has('tile_size') ? root.child('tile_size').positive : 256,
      terrainIndex: [
        for (final index in root.child('terrain_index').items) index.string,
      ],
      teams: {
        for (final (count, starts) in root.child('teams').entries)
          int.tryParse(count) ?? starts.fail('team counts are whole numbers'): [
            for (final start in starts.items) start.cell,
          ],
      },
      relics: [for (final relic in root.child('relics').items) relic.cell],
      width: root.has('width') ? root.child('width').positive : null,
      depth: root.has('depth') ? root.child('depth').positive : null,
    );
  }

  /// The map's name.
  final String name;

  /// The side of a cell, in metres (10 m in stack decision 5).
  final double cellSizeM;

  /// The side of a tile, in cells (256 in stack decision 5).
  final int tileSize;

  /// The terrain type of each index of the terrain images.
  final List<String> terrainIndex;

  /// The HQ starting points, one per team, by team count.
  final Map<int, List<CellRef>> teams;

  /// The relics' starting cells.
  final List<CellRef> relics;

  /// The map's columns; null in a source map, whose images give it.
  final int? width;

  /// The map's rows; null in a source map.
  final int? depth;

  /// The map file of this map once built, [width] × [depth] cells.
  String toYaml({required int width, required int depth}) {
    final lines = [
      'version: $mapFormatVersion',
      'name: $name',
      'cell_size_m: $cellSizeM',
      'tile_size: $tileSize',
      'width: $width',
      'depth: $depth',
      'terrain_index: [${terrainIndex.join(', ')}]',
      if (teams.isEmpty) 'teams: {}' else 'teams:',
      for (final MapEntry(:key, :value) in teams.entries)
        '  $key: [${value.map(_cellYaml).join(', ')}]',
      'relics: [${relics.map(_cellYaml).join(', ')}]',
    ];
    return '${lines.join('\n')}\n';
  }
}

/// What a feature is on the navigation map.
enum FeatureKind {
  /// On cells: a tree, a building, a wall, a trap.
  object,

  /// On cells, changing how they are crossed: a bridge over water, a road.
  construction,

  /// Between two cells that are not neighbours: a bridge or a ladder to a
  /// floating island (MAP-36).
  link,
}

/// {@template map_feature}
/// An object, construction or link of type [type] (a key of `terrain.yaml`
/// `objects`) on [cells]; a link has two, from and to. Its armour type is
/// its type's unless the map gives one ([armorType], MAP-40).
/// {@endtemplate}
final class MapFeature {
  /// {@macro map_feature}
  const new({
    required this.kind,
    required this.type,
    required this.cells,
    this.armorType,
  });

  /// Object, construction or link.
  final FeatureKind kind;

  /// Its object type.
  final String type;

  /// Its cells; a link's are its two ends.
  final List<CellRef> cells;

  /// The armour type the map gives it; null for its type's.
  final String? armorType;

  /// Its id: its type and its first cell, for example `tree@(3, 4)`.
  String get id => '$type@${cells.first}';
}

/// {@template map_island}
/// A floating island (MAP-36): its [name], its [terrain], the height of
/// its surface and the rectangles of ground cells it covers.
/// {@endtemplate}
final class MapIsland {
  /// {@macro map_island}
  const new({
    required this.name,
    required this.terrain,
    required this.heightM,
    required this.areas,
  });

  /// Its name: the surface name of its cells.
  final String name;

  /// The terrain type of its cells.
  final String terrain;

  /// The height of its surface, in metres above the map's base.
  final double heightM;

  /// The rectangles it covers: column, row, width and depth in cells.
  final List<(int, int, int, int)> areas;

  /// The columns and rows it covers.
  Iterable<(int, int)> get cells sync* {
    for (final (x, y, width, depth) in areas) {
      for (var row = y; row < y + depth; row++) {
        for (var column = x; column < x + width; column++) {
          yield (column, row);
        }
      }
    }
  }
}

/// {@template map_features}
/// A features file: [features] (objects, constructions, links) and
/// [islands], with cells in map coordinates.
/// {@endtemplate}
final class MapFeatures {
  /// {@macro map_features}
  const new({this.features = const [], this.islands = const []});

  /// Reads a features file. Throws a [MapFormatException] naming the key.
  factory parse(String text, {String file = objectsFile}) {
    final root = _Node.parse(file, text);
    MapFeature feature(FeatureKind kind, _Node node) => MapFeature(
      kind: kind,
      type: node.child('type').string,
      cells: kind == FeatureKind.link
          ? [node.child('from').cell, node.child('to').cell]
          : [for (final cell in node.child('cells').items) cell.cell],
      armorType: node.has('armor_type')
          ? node.child('armor_type').string
          : null,
    );
    List<_Node> section(String key) =>
        root.has(key) ? root.child(key).items : const [];
    return MapFeatures(
      features: [
        for (final (key, kind) in [
          ('objects', FeatureKind.object),
          ('constructions', FeatureKind.construction),
          ('links', FeatureKind.link),
        ])
          for (final node in section(key)) feature(kind, node),
      ],
      islands: [
        for (final node in section('islands'))
          MapIsland(
            name: node.child('name').islandName,
            terrain: node.child('terrain').string,
            heightM: node.child('height_m').number,
            areas: [for (final area in node.child('areas').items) area.area],
          ),
      ],
    );
  }

  /// The objects, constructions and links.
  final List<MapFeature> features;

  /// The floating islands.
  final List<MapIsland> islands;

  /// This file as text.
  String toYaml() {
    String feature(MapFeature feature) {
      final cells = feature.kind == FeatureKind.link
          ? 'from: ${_cellYaml(feature.cells.first)}, '
                'to: ${_cellYaml(feature.cells.last)}'
          : 'cells: [${feature.cells.map(_cellYaml).join(', ')}]';
      final armor = feature.armorType == null
          ? ''
          : ', armor_type: ${feature.armorType}';
      return '  - {type: ${feature.type}, $cells$armor}';
    }

    List<String> section(String key, Iterable<String> items) =>
        items.isEmpty ? ['$key: []'] : ['$key:', ...items];
    final lines = [
      for (final (key, kind) in [
        ('objects', FeatureKind.object),
        ('constructions', FeatureKind.construction),
        ('links', FeatureKind.link),
      ])
        ...section(key, [
          for (final item in features.where((item) => item.kind == kind))
            feature(item),
        ]),
      ...section('islands', islands.map(_islandYaml)),
    ];
    return '${lines.join('\n')}\n';
  }
}

String _islandYaml(MapIsland island) {
  final areas = [
    for (final (x, y, width, depth) in island.areas) '[$x, $y, $width, $depth]',
  ];
  return '  - {name: ${island.name}, terrain: ${island.terrain}, '
      'height_m: ${island.heightM}, areas: [${areas.join(', ')}]}';
}

String _cellYaml(CellRef cell) => cell.surface == groundSurface
    ? '[${cell.x}, ${cell.y}]'
    : '[${cell.x}, ${cell.y}, ${cell.surface}]';

/// A value of a YAML file at a dotted key, for error messages.
final class _Node {
  new(this.file, this.key, this.value);

  factory parse(String file, String text) {
    final Object? value;
    try {
      value = loadYaml(text);
    } on YamlException catch (error) {
      throw MapFormatException(file: file, key: '', problem: error.message);
    }
    return _Node(file, '', value);
  }

  final String file;
  final String key;
  final Object? value;

  Never fail(String problem) =>
      throw MapFormatException(file: file, key: key, problem: problem);

  String _keyOf(Object name) => key.isEmpty ? '$name' : '$key.$name';

  YamlMap get _map => switch (value) {
    final YamlMap map => map,
    _ => fail('must be a map'),
  };

  bool has(String name) => _map.containsKey(name);

  _Node child(String name) => has(name)
      ? _Node(file, _keyOf(name), _map[name])
      : _Node(file, _keyOf(name), null).fail('is missing');

  Iterable<(String, _Node)> get entries => [
    for (final MapEntry(:Object key, :value) in _map.entries)
      ('$key', _Node(file, _keyOf(key), value)),
  ];

  List<_Node> get items => switch (value) {
    final YamlList list => [
      for (final (index, item) in list.indexed)
        _Node(file, '$key[$index]', item),
    ],
    _ => fail('must be a list'),
  };

  String get string => switch (value) {
    final String text => text,
    _ => fail('must be text'),
  };

  String get islandName =>
      _islandName.hasMatch(string) ? string : fail('must match $_islandName');

  int get integer => switch (value) {
    final int number => number,
    _ => fail('must be a whole number'),
  };

  int get positive => integer > 0 ? integer : fail('must be positive');

  double get number => switch (value) {
    final num number => number.toDouble(),
    _ => fail('must be a number'),
  };

  /// `[x, y]` on the ground, `[x, y, island]` on a floating island.
  CellRef get cell {
    final parts = items;
    if (parts.length != 2 && parts.length != 3) {
      fail('must be [x, y] or [x, y, island]');
    }
    return CellRef(
      parts[0].integer,
      parts[1].integer,
      surface: parts.length == 3 ? parts[2].islandName : groundSurface,
    );
  }

  /// `[x, y, width, depth]`.
  (int, int, int, int) get area {
    final parts = items;
    if (parts.length != 4) fail('must be [x, y, width, depth]');
    return (
      parts[0].integer,
      parts[1].integer,
      parts[2].positive,
      parts[3].positive,
    );
  }
}
