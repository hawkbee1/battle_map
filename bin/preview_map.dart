import 'dart:io';
import 'dart:math' as math;

import 'package:battle_map/battle_map.dart';
import 'package:image/image.dart' as img;

const _usage = '''
Draws a source map as a colour image, one pixel per cell, to check it and
to correct it by hand: terrain colours shaded by the heights, buildings,
walls, trees and bridges, HQ starting points (blue) and relics (gold).

Usage: dart run battle_map:preview_map <source> <preview.png>''';

/// The colour of each terrain type the preview knows; others are grey.
const _terrainColours = {
  'grass': (152, 196, 112),
  'forest_floor': (60, 120, 60),
  'sand': (230, 214, 160),
  'mud': (140, 120, 80),
  'rock': (150, 150, 150),
  'road': (235, 235, 225),
  'town_street': (200, 180, 170),
  'mountain': (120, 100, 90),
  'river': (60, 110, 200),
  'lake': (80, 140, 220),
  'floating_island_ground': (200, 160, 220),
};

const _objectColours = {
  'building': (150, 40, 40),
  'wall': (40, 40, 40),
  'tree': (30, 80, 30),
  'bridge': (240, 200, 0),
  'reinforced_bridge': (255, 120, 0),
  'road_segment': (235, 235, 225),
};

void main(List<String> arguments) {
  if (arguments case [final source, final output]) {
    final map = MapData.fromSource(
      mapYaml: File('$source/$mapFile').readAsStringSync(),
      heightsPng: File('$source/heights.png').readAsBytesSync(),
      terrainPng: File('$source/terrain.png').readAsBytesSync(),
      objectsYaml: File('$source/$objectsFile').readAsStringSync(),
    );
    File(output).writeAsBytesSync(img.encodePng(_draw(map)));
  } else {
    stderr.writeln(_usage);
    exitCode = 64;
  }
}

img.Image _draw(MapData map) {
  final image = img.Image(width: map.width, height: map.depth);
  final names = map.spec.terrainIndex;
  int height(int x, int y) =>
      map.heights[y.clamp(0, map.depth - 1) * map.width +
          x.clamp(0, map.width - 1)];
  for (var y = 0; y < map.depth; y++) {
    for (var x = 0; x < map.width; x++) {
      final (r, g, b) =
          _terrainColours[names[map.terrain[y * map.width + x]]] ??
          (128, 128, 128);
      // Light from the north-west.
      final slope =
          (height(x - 1, y - 1) - height(x + 1, y + 1)) / map.spec.cellSizeM;
      final shade = (1 + slope * 1.5).clamp(0.6, 1.3);
      image.setPixelRgb(
        x,
        y,
        math.min(255, r * shade),
        math.min(255, g * shade),
        math.min(255, b * shade),
      );
    }
  }
  for (final feature in map.features.features) {
    final (r, g, b) = _objectColours[feature.type] ?? (255, 0, 255);
    for (final cell in feature.cells) {
      image.setPixelRgb(cell.x, cell.y, r, g, b);
    }
  }
  void mark(int x, int y, (int, int, int) colour) {
    final (r, g, b) = colour;
    img.fillRect(
      image,
      x1: x - 6,
      y1: y - 6,
      x2: x + 6,
      y2: y + 6,
      color: img.ColorRgb8(r, g, b),
    );
  }

  for (final starts in map.spec.teams.values) {
    for (final start in starts) {
      mark(start.x, start.y, (0, 0, 255));
    }
  }
  for (final relic in map.spec.relics) {
    mark(relic.x, relic.y, (255, 200, 0));
  }
  return image;
}
