import 'dart:io';

import 'package:battle_map/battle_map.dart';
import 'package:battle_rules/battle_rules.dart';

const _usage = '''
Builds a Battle Team map (stack decision 5): checks a source map against the
game data, then writes its tiles.

Usage: dart run battle_map:build_map <plan> <source> <output>
  <plan>    the plan folder (apps/battle_team/plan), for the game data
  <source>  map.yaml, heights.png, terrain.png and objects.yaml
  <output>  where map.yaml and tiles/<column>_<row>/ are written''';

void main(List<String> arguments) {
  if (arguments case [final plan, final source, final output]) {
    exitCode = _build(plan, source, output);
  } else {
    stderr.writeln(_usage);
    exitCode = 64;
  }
}

int _build(String plan, String source, String output) {
  String read(String path) => File(path).readAsStringSync();
  final data = GameData.parse(
    units: read('$plan/data/units.yaml'),
    combat: read('$plan/data/combat.yaml'),
    terrain: read('$plan/data/terrain.yaml'),
    battle: read('$plan/data/battle.yaml'),
    economy: read('$plan/milestones/economy.yaml'),
    medals: read('$plan/data/medals.yaml'),
  );
  final MapData map;
  try {
    map = MapData.fromSource(
      mapYaml: read('$source/$mapFile'),
      heightsPng: File('$source/heights.png').readAsBytesSync(),
      terrainPng: File('$source/terrain.png').readAsBytesSync(),
      objectsYaml: read('$source/$objectsFile'),
    );
  } on MapFormatException catch (error) {
    stderr.writeln(error);
    return 65;
  }
  switch (buildMap(map, data)) {
    case MapRefused(:final problems):
      problems.forEach(stderr.writeln);
      stderr.writeln('${problems.length} problems: no tile written.');
      return 1;
    case MapBuilt(:final files):
      File('$output/$mapFile')
        ..createSync(recursive: true)
        ..writeAsStringSync(files.mapYaml);
      for (final MapEntry(key: name, value: tile) in files.tiles.entries) {
        final folder = '$output/tiles/$name';
        Directory(folder).createSync(recursive: true);
        File('$folder/heights.png').writeAsBytesSync(tile.heightsPng);
        File('$folder/terrain.png').writeAsBytesSync(tile.terrainPng);
        File('$folder/$objectsFile').writeAsStringSync(tile.objectsYaml);
      }
      stdout.writeln('Built ${files.tiles.length} tiles into $output.');
      return 0;
  }
}
