import 'dart:io';
import 'dart:typed_data';

import 'package:battle_map/battle_map.dart';
import 'package:battle_rules/battle_rules.dart';

/// The Battle Team plan in the hawkbee checkout, relative to this package.
/// Tests run from the package folder.
const planPath = '../../apps/battle_team/plan';

/// The game data of the plan.
GameData parsePlanData() {
  String read(String path) => File('$planPath/$path').readAsStringSync();
  return GameData.parse(
    units: read('data/units.yaml'),
    combat: read('data/combat.yaml'),
    terrain: read('data/terrain.yaml'),
    battle: read('data/battle.yaml'),
    economy: read('milestones/economy.yaml'),
    medals: read('data/medals.yaml'),
  );
}

/// The valley test map's [file], with each key of [replace] replaced by
/// its value. Throws a [StateError] when a key does not occur exactly once.
String readValley(String file, [Map<String, String> replace = const {}]) {
  var text = File('test/fixtures/valley/$file').readAsStringSync();
  for (final MapEntry(:key, :value) in replace.entries) {
    final count = key.allMatches(text).length;
    if (count != 1) {
      throw StateError('"$key" occurs $count times in valley/$file');
    }
    text = text.replaceFirst(key, value);
  }
  return text;
}

/// The bytes of the valley test map's [file].
Uint8List readValleyBytes(String file) =>
    File('test/fixtures/valley/$file').readAsBytesSync();

/// The valley source map, with replacements in its map and features files.
///
/// 12 × 8 cells in tiles of 4: a river down column 5 with a bridge on the
/// road of row 1, a forest, a mountain in the south-east corner and the
/// floating island `sky` over columns 8 to 10, rows 5 and 6.
MapData valley({
  Map<String, String> map = const {},
  Map<String, String> objects = const {},
}) => MapData.fromSource(
  mapYaml: readValley(mapFile, map),
  heightsPng: readValleyBytes('heights.png'),
  terrainPng: readValleyBytes('terrain.png'),
  objectsYaml: readValley(objectsFile, objects),
);
