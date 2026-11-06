import 'dart:io';

import 'package:battle_map/battle_map.dart';

const _usage = '''
Writes the source map of a built map (stack decision 5, authoring step 2),
to correct it by hand again and rebuild it with build_map.

Usage: dart run battle_map:source_map <built> <source>
  <built>   map.yaml and tiles/<column>_<row>/, as build_map writes them
  <source>  where map.yaml, heights.png, terrain.png and objects.yaml are
            written''';

void main(List<String> arguments) {
  if (arguments case [final built, final source]) {
    final files = MapData.fromBuilt(_read(built)).toSource();
    Directory(source).createSync(recursive: true);
    File('$source/$mapFile').writeAsStringSync(files.mapYaml);
    File('$source/heights.png').writeAsBytesSync(files.heightsPng);
    File('$source/terrain.png').writeAsBytesSync(files.terrainPng);
    File('$source/$objectsFile').writeAsStringSync(files.objectsYaml);
    stdout.writeln('Wrote the source map into $source.');
  } else {
    stderr.writeln(_usage);
    exitCode = 64;
  }
}

BuiltMapFiles _read(String folder) => BuiltMapFiles(
  mapYaml: File('$folder/$mapFile').readAsStringSync(),
  tiles: {
    for (final tile in Directory('$folder/tiles').listSync())
      if (tile is Directory)
        tile.uri.pathSegments.lastWhere((s) => s.isNotEmpty): TileFiles(
          heightsPng: File('${tile.path}/heights.png').readAsBytesSync(),
          terrainPng: File('${tile.path}/terrain.png').readAsBytesSync(),
          objectsYaml: File('${tile.path}/$objectsFile').readAsStringSync(),
        ),
  },
);
