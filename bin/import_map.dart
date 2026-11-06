import 'dart:io';

import 'package:battle_map/battle_map.dart';
import 'package:battle_map/map_import.dart';
import 'package:battle_rules/battle_rules.dart';
import 'package:yaml/yaml.dart';

const _usage = '''
Makes the first map from real data (stack decision 5, authoring step 1): a
source map to correct by hand, then to check and cut into tiles with
build_map.

Usage: dart run battle_map:import_map <plan> <import.yaml> <downloads> <source>
  <plan>         the plan folder (apps/battle_team/plan), for the water terrains
  <import.yaml>  the import file: the area, the rules and the starting points
  <downloads>    what fetch_map_sources fetched
  <source>       where map.yaml, heights.png, terrain.png and objects.yaml
                 are written''';

void main(List<String> arguments) {
  if (arguments case [
    final plan,
    final importPath,
    final downloads,
    final source,
  ]) {
    exitCode = _import(plan, importPath, downloads, source);
  } else {
    stderr.writeln(_usage);
    exitCode = 64;
  }
}

int _import(String plan, String importPath, String downloads, String source) {
  final terrain = TerrainData.parse(
    File('$plan/data/terrain.yaml').readAsStringSync(),
  );
  final MapImport result;
  try {
    final sources =
        loadYaml(File('$downloads/sources.yaml').readAsStringSync()) as YamlMap;
    result = importMap(
      spec: ImportSpec.parse(File(importPath).readAsStringSync()),
      elevationBil: File('$downloads/$elevationFile').readAsBytesSync(),
      osm: OsmExtract.parse(File('$downloads/$osmFile').readAsStringSync()),
      water: waterTerrainsOf(terrain),
      elevationFetched: '${sources['elevation_fetched']}',
    );
  } on MapFormatException catch (error) {
    stderr.writeln(error);
    return 65;
  }
  result.report.forEach(stdout.writeln);
  final files = result.map.toSource();
  Directory(source).createSync(recursive: true);
  File('$source/$mapFile').writeAsStringSync(files.mapYaml);
  File('$source/heights.png').writeAsBytesSync(files.heightsPng);
  File('$source/terrain.png').writeAsBytesSync(files.terrainPng);
  File('$source/$objectsFile').writeAsStringSync(files.objectsYaml);
  stdout.writeln('Wrote the source map into $source.');
  return 0;
}
