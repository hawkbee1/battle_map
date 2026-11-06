# battle_map

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: MIT][license_badge]][license_link]

The **map format, builder and loader** of Battle Team, a 3D, massive, persistent,
real-time team battle game (stack decision 5 of the plan).

- **The format**: a map is cut into tiles of 256 × 256 cells of 10 m. Each tile has a
  16-bit height image (`heights.png`, metres above the map's base), an indexed terrain
  image (`terrain.png`, one index of the map's `terrain_index` per cell) and a features
  file (`objects.yaml`: objects, constructions, links and floating islands). The map
  file (`map.yaml`) gives the cell and tile sizes, the terrain index, the HQ starting
  points for each team count it supports and the relics' starting cells.
- **The builder** (`bin/build_map.dart`) checks a source map (whole-map images and one
  `objects.yaml`) against the game data and writes its tiles:
  ```sh
  dart run battle_map:build_map <plan> <source> <output>
  ```
  It refuses unknown terrain and armour types, bridges and ladders that do not link
  land to land, floating islands reached otherwise than by bridges and ladders, objects
  on water, relics off solid ground or in a number that allows a tie, and missing HQ
  starting points. Each problem names its tile, its cell or its object.
- **One loader** for the server and the client (a Factory Method): `HostMapLoader`
  gives the host the navigation model of
  [battle_pathfinding](https://github.com/hawkbee1/battle_pathfinding) and the objects
  with their hit points and armour type; the client will make its meshes.
- **Maps from real data** (`package:battle_map/map_import.dart`): an import file
  (`import.yaml`) picks an area in Lambert-93 and rules that turn OpenStreetMap
  elements into terrain, bridges and objects. `bin/fetch_map_sources.dart` fetches the
  IGN RGE ALTI heights and the OpenStreetMap elements, `bin/import_map.dart` makes the
  source map to correct by hand, `bin/preview_map.dart` draws it, and
  `bin/source_map.dart` turns a built map back into a source map. The maps, their
  licences (ODbL, Licence Ouverte) and how they were made are in
  [`maps/`](maps/README.md); the first is `saint_lo`, the Vire valley through Saint-Lô.
- **Pure Dart, no I/O in `lib/`**: the caller passes bytes and text. Only the tools in
  `bin/` read and write files. The game data comes from
  [battle_rules](https://github.com/hawkbee1/battle_rules).

Benchmarks: `bin/map_memory_bench.dart`, results in
[`benchmark_results/`](benchmark_results/README.md).

## Part of hawkbee

This repository is a git submodule of the
[hawkbee](https://github.com/hawkbee1/hawkbee) monorepo and **only builds inside
it** (pub workspace, `resolution: workspace`):

```sh
git clone --recurse-submodules https://github.com/hawkbee1/hawkbee.git
cd hawkbee && flutter pub get
```

The tests read the game data from the plan in that checkout
(`apps/battle_team/plan/data`).

## Licence

The code is under the MIT licence. The map data in `maps/` is not: it is under the ODbL
1.0 (OpenStreetMap) and the Licence Ouverte 2.0 (IGN), see [`maps/`](maps/README.md).

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
