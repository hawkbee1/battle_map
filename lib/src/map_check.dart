import 'package:battle_map/src/map_data.dart';
import 'package:battle_map/src/map_format.dart';
import 'package:battle_pathfinding/battle_pathfinding.dart';
import 'package:battle_rules/battle_rules.dart';

/// The object types that link two cells, and the kind of link each makes
/// (MAP-36, decision 99).
const Map<String, LinkKind> linkKinds = {
  'bridge': LinkKind.bridge,
  'reinforced_bridge': LinkKind.reinforcedBridge,
  'ladder': LinkKind.ladder,
};

/// The object types that carry ground units over water (MAP-23).
const bridgeTypes = {'bridge', 'reinforced_bridge'};

/// The terrain types that are water: those only some profiles cross
/// (`crossable_by` in `terrain.yaml`: rivers and lakes, MAP-22).
Set<String> waterTerrainsOf(TerrainData terrain) => {
  for (final type in terrain.terrainTypes.values)
    if (type.crossableBy.isNotEmpty) type.id,
};

/// {@template map_problem}
/// What the map builder refuses: [message], about a [tile], a [cell] or an
/// [object] when it is about one.
/// {@endtemplate}
final class MapProblem {
  /// {@macro map_problem}
  const new(this.message, {this.tile, this.cell, this.object});

  /// What is wrong.
  final String message;

  /// The tile, as `<column>_<row>`.
  final String? tile;

  /// The cell.
  final CellRef? cell;

  /// The object or island, for example `tree@(3, 4)` or `island sky`.
  final String? object;

  @override
  String toString() => [
    if (tile != null) 'tile $tile',
    if (cell != null) 'cell $cell',
    ?object,
    message,
  ].join(': ');
}

/// The outcome of a map build.
sealed class MapBuild {
  const new();
}

/// {@template map_built}
/// The map passed every check: its tiles are [files].
/// {@endtemplate}
final class MapBuilt extends MapBuild {
  /// {@macro map_built}
  const new(this.files);

  /// The built map.
  final BuiltMapFiles files;
}

/// {@template map_refused}
/// The map failed [problems]; no tile is written.
/// {@endtemplate}
final class MapRefused extends MapBuild {
  /// {@macro map_refused}
  const new(this.problems);

  /// Every check it failed.
  final List<MapProblem> problems;
}

/// Checks [map] against the game [data], then writes its tiles (stack
/// decision 5): see [checkMap].
MapBuild buildMap(MapData map, GameData data) {
  final problems = checkMap(map, data);
  return problems.isEmpty ? MapBuilt(map.toBuilt()) : MapRefused(problems);
}

/// What the map builder checks statically (stack decision 5): terrain and
/// armour types exist; bridges and ladders link land to land; floating
/// islands are reached only by bridges and ladders (MAP-36); no object on
/// a cell it cannot occupy, that is on water, except bridges, which stand
/// only on water with land at both ends (MAP-48, decision 217); relics on solid
/// ground, a floating island's included, from `relics_to_hold` to fewer
/// than twice as many (RELIC-02, RELIC-17, decisions 216, 218); HQ starting
/// points on the ground for every team count the map supports (MAP-03,
/// HQ-01, decision 216).
List<MapProblem> checkMap(MapData map, GameData data) =>
    _Checker(map, data).run();

final class _Checker {
  new(this.map, this.data)
    : water = waterTerrainsOf(data.terrain),
      islandTerrains = {
        for (final type in data.terrain.terrainTypes.values)
          if (type.access.isNotEmpty) type.id,
      };

  final MapData map;
  final GameData data;
  final Set<String> water;
  final Set<String> islandTerrains;
  final problems = <MapProblem>[];
  final islands = <String, Map<(int, int), String>>{};

  void fail(String message, {CellRef? cell, String? object}) => problems.add(
    MapProblem(
      message,
      tile: cell == null ? null : map.tileOf(cell.x, cell.y),
      cell: cell,
      object: object,
    ),
  );

  List<MapProblem> run() {
    _checkTerrain();
    _checkIslands();
    _checkFeatures();
    _checkRelics();
    _checkTeams();
    return problems;
  }

  bool _onMap(int x, int y) =>
      x >= 0 && y >= 0 && x < map.width && y < map.depth;

  /// The terrain type of [cell]; null when there is no such cell.
  String? terrainAt(CellRef cell) {
    if (cell.surface != groundSurface) {
      return islands[cell.surface]?[(cell.x, cell.y)];
    }
    if (!_onMap(cell.x, cell.y)) return null;
    final index = map.terrain[cell.y * map.width + cell.x];
    final names = map.spec.terrainIndex;
    return index < names.length ? names[index] : null;
  }

  /// Whether [cell] exists and is not water; reports it otherwise.
  bool land(CellRef cell, String object) {
    final terrain = terrainAt(cell);
    if (terrain == null) {
      fail('is off the map', cell: cell, object: object);
      return false;
    }
    if (water.contains(terrain)) {
      fail('is on water ($terrain)', cell: cell, object: object);
      return false;
    }
    return true;
  }

  void _checkTerrain() {
    final names = map.spec.terrainIndex;
    for (final (index, name) in names.indexed) {
      if (!data.terrain.terrainTypes.containsKey(name)) {
        fail('terrain_index[$index]: unknown terrain type $name');
      }
    }
    for (var y = 0; y < map.depth; y++) {
      for (var x = 0; x < map.width; x++) {
        final index = map.terrain[y * map.width + x];
        if (index >= names.length) {
          fail(
            'terrain index $index is not in terrain_index',
            cell: CellRef(x, y),
          );
        } else if (islandTerrains.contains(names[index])) {
          fail('${names[index]} is for floating islands', cell: CellRef(x, y));
        }
      }
    }
  }

  void _checkIslands() {
    for (final island in map.features.islands) {
      final name = 'island ${island.name}';
      if (islands.containsKey(island.name)) {
        fail('is named twice', object: name);
        continue;
      }
      if (!islandTerrains.contains(island.terrain)) {
        fail(
          '${island.terrain} is not a floating island terrain',
          object: name,
        );
      }
      final cells = islands[island.name] = {};
      for (final (x, y) in island.cells) {
        final cell = CellRef(x, y, surface: island.name);
        if (!_onMap(x, y)) {
          fail('is off the map', cell: cell, object: name);
          continue;
        }
        final ground = map.heights[y * map.width + x];
        if (island.heightM <= ground) {
          fail('is not above the ground ($ground m)', cell: cell, object: name);
        }
        cells[(x, y)] = island.terrain;
      }
    }
  }

  void _checkFeatures() {
    final seen = <(String, CellRef)>{};
    for (final feature in map.features.features) {
      final id = feature.id;
      final type = data.terrain.objects[feature.type];
      if (type == null) {
        fail('unknown object type', object: id);
        continue;
      }
      final armor = feature.armorType ?? type.armorType;
      if (!data.combat.armorTypes.contains(armor)) {
        fail('unknown armour type $armor', object: id);
      }
      for (final cell in feature.cells) {
        if (!seen.add((feature.type, cell))) {
          fail(
            'shares its cell with another ${feature.type}',
            cell: cell,
            object: id,
          );
        }
      }
      switch (feature.kind) {
        case FeatureKind.link:
          _checkLink(feature, id);
        case _ when feature.type == 'ladder':
          fail('a ladder is a link', object: id);
        case FeatureKind.object when bridgeTypes.contains(feature.type):
          fail('a bridge is a construction or a link', object: id);
        case FeatureKind.construction when bridgeTypes.contains(feature.type):
          _checkBridge(feature, id);
        case _:
          for (final cell in feature.cells) {
            land(cell, id);
          }
      }
    }
  }

  void _checkLink(MapFeature link, String id) {
    if (!linkKinds.containsKey(link.type)) {
      fail('a link is a bridge or a ladder', object: id);
    }
    for (final end in link.cells) {
      land(end, id);
    }
    if (link.cells.every((end) => end.surface == groundSurface)) {
      fail('joins no floating island', object: id);
    }
  }

  void _checkBridge(MapFeature bridge, String id) {
    final cells = bridge.cells;
    for (final cell in cells) {
      final terrain = terrainAt(cell);
      if (cell.surface != groundSurface || terrain == null) {
        fail('is off the ground', cell: cell, object: id);
        return;
      }
      if (!water.contains(terrain)) {
        fail('is not over water ($terrain)', cell: cell, object: id);
      }
    }
    for (var index = 1; index < cells.length; index++) {
      final (a, b) = (cells[index - 1], cells[index]);
      if ((a.x - b.x).abs() > 1 || (a.y - b.y).abs() > 1 || a == b) {
        fail('does not follow the cell before it', cell: b, object: id);
      }
    }
    Set<CellRef> shore(CellRef end) => {
      for (var dy = -1; dy <= 1; dy++)
        for (var dx = -1; dx <= 1; dx++)
          if (CellRef(end.x + dx, end.y + dy) case final next
              when !cells.contains(next) &&
                  terrainAt(next) != null &&
                  !water.contains(terrainAt(next)))
            next,
    };
    final first = shore(cells.first);
    final last = shore(cells.last);
    if (first.isEmpty || last.isEmpty || {...first, ...last}.length < 2) {
      fail('does not reach land at both ends', object: id);
    }
  }

  void _checkRelics() {
    final relics = map.spec.relics;
    final toHold = data.battle.victory.relicsToHold;
    if (relics.length < toHold) {
      fail('${relics.length} relics: fewer than relics_to_hold $toHold');
    } else if (relics.length >= 2 * toHold) {
      fail(
        '${relics.length} relics let two teams hold $toHold at once '
        '(RELIC-17)',
      );
    }
    final seen = <CellRef>{};
    for (final (index, relic) in relics.indexed) {
      final name = 'relics[$index]';
      if (!seen.add(relic)) fail('shares its cell', cell: relic, object: name);
      land(relic, name);
    }
  }

  void _checkTeams() {
    final teams = map.spec.teams;
    if (teams.isEmpty) fail('supports no team count');
    for (final MapEntry(key: count, value: starts) in teams.entries) {
      final name = 'teams.$count';
      if (count < 2) fail('a battle has 2 teams or more', object: name);
      if (starts.length != count) {
        fail(
          'has ${starts.length} starting points for $count teams',
          object: name,
        );
      }
      final seen = <CellRef>{};
      for (final start in starts) {
        if (start.surface != groundSurface) {
          fail('an HQ starts on the ground', cell: start, object: name);
          continue;
        }
        if (!seen.add(start)) {
          fail('shares its cell', cell: start, object: name);
        }
        land(start, name);
      }
    }
  }
}
