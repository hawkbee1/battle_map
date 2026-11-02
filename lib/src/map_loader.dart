import 'package:battle_map/src/map_check.dart';
import 'package:battle_map/src/map_data.dart';
import 'package:battle_map/src/map_format.dart';
import 'package:battle_pathfinding/battle_pathfinding.dart';
import 'package:battle_rules/battle_rules.dart';

/// {@template map_object}
/// An object, construction or link of a loaded map, with the hit points of
/// its type and its armour type (MAP-10, MAP-40).
/// {@endtemplate}
final class MapObject {
  /// {@macro map_object}
  const new({
    required this.id,
    required this.type,
    required this.kind,
    required this.cells,
    required this.hp,
    required this.armorType,
  });

  /// Its id: its type and its first cell, for example `tree@(3, 4)`.
  final String id;

  /// Its object type, a key of `terrain.yaml` `objects`.
  final String type;

  /// Object, construction or link.
  final FeatureKind kind;

  /// Its cells; a link's two ends.
  final List<CellRef> cells;

  /// Its hit points at the start of a battle.
  final double hp;

  /// Its armour type, for the damage table.
  final String armorType;
}

/// {@template host_map}
/// What the battle host loads from a map: the [navigation] model of
/// `battle_pathfinding`, the [objects] with their HP and armour type, the
/// HQ starting points by team count and the relics' starting cells.
/// {@endtemplate}
final class HostMap {
  /// {@macro host_map}
  const new({
    required this.navigation,
    required this.objects,
    required this.hqStarts,
    required this.relicStarts,
  });

  /// The navigation model (M3 Issue 2).
  final NavigationMap navigation;

  /// The objects, constructions and links, by id.
  final Map<String, MapObject> objects;

  /// The HQ starting points, one per team, by team count (MAP-03, HQ-01).
  final Map<int, List<CellRef>> hqStarts;

  /// The relics' starting cells (RELIC-02).
  final List<CellRef> relicStarts;
}

/// {@template map_loader}
/// The one map loader of the server and the client (MAP-05), as a Factory
/// Method (stack decision 7): [load] reads a built map's tiles and hands
/// the whole map to [make], which each side implements. The host makes a
/// [HostMap] ([HostMapLoader]); the client will make its meshes (M7).
/// {@endtemplate}
abstract class MapLoader<T> {
  /// {@macro map_loader}
  const new();

  /// The map built as [files]. Throws a [MapFormatException] for a file
  /// out of the format.
  T load(BuiltMapFiles files) => make(MapData.fromBuilt(files));

  /// The factory method: what this side makes of [map].
  T make(MapData map);
}

/// {@template host_map_loader}
/// The host's map loader, with the `terrain.yaml` data: water terrains,
/// objects' HP and armour types. It expects a map the builder passed; an
/// unknown object type is a [MapFormatException].
/// {@endtemplate}
final class HostMapLoader extends MapLoader<HostMap> {
  /// {@macro host_map_loader}
  const new(this.terrain);

  /// The `terrain.yaml` data.
  final TerrainData terrain;

  @override
  HostMap make(MapData map) {
    final names = map.spec.terrainIndex;
    // One cell object per height and terrain: a big map shares them.
    final shared = <int, NavCell>{};
    final ground = List<NavCell>.generate(map.width * map.depth, (index) {
      final height = map.heights[index];
      final terrainIndex = map.terrain[index];
      return shared[height << 8 | terrainIndex] ??= NavCell(
        height: height.toDouble(),
        terrain: names[terrainIndex],
      );
    }, growable: false);
    final objects = <CellRef, Set<String>>{};
    final constructions = <CellRef, Set<String>>{};
    final links = <SurfaceLink>[];
    final mapObjects = <String, MapObject>{};
    for (final feature in map.features.features) {
      final type =
          terrain.objects[feature.type] ??
          (throw MapFormatException(
            file: objectsFile,
            key: feature.id,
            problem: 'unknown object type',
          ));
      switch (feature.kind) {
        case FeatureKind.object:
          _place(objects, feature);
        case FeatureKind.construction:
          _place(constructions, feature);
        case FeatureKind.link:
          links.add(
            SurfaceLink(
              kind: linkKinds[feature.type]!,
              from: feature.cells.first,
              to: feature.cells.last,
            ),
          );
      }
      mapObjects[feature.id] = MapObject(
        id: feature.id,
        type: feature.type,
        kind: feature.kind,
        cells: List.unmodifiable(feature.cells),
        hp: type.hp,
        armorType: feature.armorType ?? type.armorType,
      );
    }
    return HostMap(
      navigation: NavigationMap(
        cellSizeM: map.spec.cellSizeM,
        width: map.width,
        depth: map.depth,
        ground: ground,
        waterTerrains: waterTerrainsOf(terrain),
        islands: {
          for (final island in map.features.islands)
            island.name: {
              for (final cell in island.cells)
                cell: NavCell(height: island.heightM, terrain: island.terrain),
            },
        },
        objects: objects,
        constructions: constructions,
        links: links,
      ),
      objects: Map.unmodifiable(mapObjects),
      hqStarts: map.spec.teams,
      relicStarts: map.spec.relics,
    );
  }

  static void _place(Map<CellRef, Set<String>> into, MapFeature feature) {
    for (final cell in feature.cells) {
      (into[cell] ??= {}).add(feature.type);
    }
  }
}
