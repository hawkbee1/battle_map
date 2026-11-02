import 'package:battle_map/battle_map.dart';
import 'package:battle_rules/battle_rules.dart';
import 'package:test/test.dart';

import '../helpers/fixtures.dart';

void main() {
  late GameData data;

  setUpAll(() => data = parsePlanData());

  List<String> problems(MapData map) => [
    for (final problem in checkMap(map, data)) '$problem',
  ];

  /// The problems of the valley with replacements in its files.
  List<String> problemsWith({
    Map<String, String> map = const {},
    Map<String, String> objects = const {},
  }) => problems(valley(map: map, objects: objects));

  group('buildMap', () {
    test('the valley passes every check and is written as tiles', () {
      expect(problems(valley()), isEmpty);
      expect((buildMap(valley(), data) as MapBuilt).files.tiles, hasLength(6));
    });

    test('a map that fails a check is not written', () {
      final refused = buildMap(
        valley(objects: {'type: wall': 'type: shrub'}),
        data,
      ) as MapRefused;

      expect(refused.problems.single.object, 'shrub@(7, 3)');
    });
  });

  group('checkMap: terrain', () {
    test('every terrain type of terrain_index exists', () {
      expect(
        problemsWith(map: {'[grass, river': '[meadow, river'}),
        contains('terrain_index[0]: unknown terrain type meadow'),
      );
    });

    test('every cell has an index of terrain_index', () {
      final map = valley();
      map.terrain[4] = 9;

      expect(
        problems(map),
        contains(
          'tile 1_0: cell (4, 0): terrain index 9 is not in '
          'terrain_index',
        ),
      );
    });

    test('MAP-36 floating island terrain is not on the ground', () {
      final map = valley();
      map.terrain[1] = 5;

      expect(
        problems(map),
        contains(
          'tile 0_0: cell (1, 0): floating_island_ground is for '
          'floating islands',
        ),
      );
    });
  });

  group('checkMap: floating islands', () {
    test('an island has one name', () {
      expect(
        problemsWith(
          objects: {
            'islands:\n':
                'islands:\n  - {name: sky, terrain: floating_island_ground, '
                'height_m: 90, areas: [[0, 4, 1, 1]]}\n',
          },
        ),
        contains('island sky: is named twice'),
      );
    });

    test('MAP-36 an island has a floating island terrain', () {
      expect(
        problemsWith(
          objects: {'terrain: floating_island_ground': 'terrain: grass'},
        ),
        contains('island sky: grass is not a floating island terrain'),
      );
    });

    test('an island is on the map', () {
      expect(
        problemsWith(objects: {'[[8, 5, 3, 2]]': '[[10, 5, 3, 2]]'}),
        contains('tile 3_1: cell sky(12, 5): island sky: is off the map'),
      );
    });

    test('an island is above the ground under it', () {
      expect(
        problemsWith(objects: {'height_m: 60': 'height_m: 30'}),
        contains(
          'tile 2_1: cell sky(10, 6): island sky: is not above the '
          'ground (30 m)',
        ),
      );
    });
  });

  group('checkMap: objects and constructions', () {
    test('MAP-40 an object has a known type and armour type', () {
      expect(
        problemsWith(objects: {'type: wall': 'type: fence'}),
        contains('fence@(7, 3): unknown object type'),
      );
      expect(
        problemsWith(objects: {'armor_type: structure': 'armor_type: paper'}),
        contains('wall@(7, 3): unknown armour type paper'),
      );
    });

    test('two objects of one type never share a cell', () {
      expect(
        problemsWith(objects: {'[[2, 5]]': '[[1, 4]]'}),
        contains(
          'tile 0_1: cell (1, 4): tree@(1, 4): shares its cell with '
          'another tree',
        ),
      );
    });

    test('decision 217 no object stands on water or off the map', () {
      expect(
        problemsWith(objects: {'[[8, 2], [9, 2]]': '[[5, 2], [9, 2]]'}),
        contains(
          'tile 1_0: cell (5, 2): building@(5, 2): is on water '
          '(river)',
        ),
      );
      expect(
        problemsWith(objects: {'[[1, 4]]': '[[1, 40]]'}),
        contains('tile 0_10: cell (1, 40): tree@(1, 40): is off the map'),
      );
      expect(
        problemsWith(objects: {'[[6, 6], [7, 6]]': '[[5, 6], [6, 6]]'}),
        contains(
          'tile 1_1: cell (5, 6): road_segment@(5, 6): is on water '
          '(river)',
        ),
      );
    });

    test('a ladder is a link, a bridge a construction or a link', () {
      expect(
        problemsWith(objects: {'type: road_segment': 'type: ladder'}),
        contains('ladder@(6, 6): a ladder is a link'),
      );
      expect(
        problemsWith(objects: {'type: building': 'type: bridge'}),
        contains('bridge@(8, 2): a bridge is a construction or a link'),
      );
    });

    test('decision 217 a bridge stands only over water', () {
      expect(
        problemsWith(objects: {'[[5, 1]]': '[[4, 1]]'}),
        contains(
          'tile 1_0: cell (4, 1): bridge@(4, 1): is not over water '
          '(road)',
        ),
      );
      expect(
        problemsWith(objects: {'[[5, 1]]': '[[5, 1, sky]]'}),
        contains(
          'tile 1_0: cell sky(5, 1): bridge@sky(5, 1): is off the '
          'ground',
        ),
      );
    });

    test('stack decision 5 a bridge is a chain of cells that reaches land at '
        'both ends', () {
      expect(
        problemsWith(objects: {'[[5, 1]]': '[[5, 1], [5, 3]]'}),
        contains(
          'tile 1_0: cell (5, 3): bridge@(5, 1): does not follow the '
          'cell before it',
        ),
      );
      final map = valley();
      for (final (x, y) in [(4, 0), (4, 1), (4, 2), (6, 0), (6, 1), (6, 2)]) {
        map.terrain[y * 12 + x] = 1;
      }
      expect(
        problems(map),
        contains('bridge@(5, 1): does not reach land at both ends'),
      );
    });
  });

  group('checkMap: links', () {
    test('MAP-36 a link is a bridge or a ladder', () {
      expect(
        problemsWith(objects: {'type: ladder': 'type: wall'}),
        contains('wall@(7, 5): a link is a bridge or a ladder'),
      );
    });

    test('stack decision 5 a link joins land to land', () {
      expect(
        problemsWith(objects: {'from: [7, 5]': 'from: [5, 5]'}),
        contains('tile 1_1: cell (5, 5): ladder@(5, 5): is on water (river)'),
      );
      expect(
        problemsWith(objects: {'to: [8, 5, sky]': 'to: [8, 5, moon]'}),
        contains('tile 2_1: cell moon(8, 5): ladder@(7, 5): is off the map'),
      );
    });

    test('MAP-36 a link reaches a floating island', () {
      expect(
        problemsWith(objects: {'to: [8, 5, sky]': 'to: [8, 5]'}),
        contains('ladder@(7, 5): joins no floating island'),
      );
    });
  });

  group('checkMap: relics and teams', () {
    test('decision 218 RELIC-17 relics_to_hold relics or more, fewer than '
        'twice as many', () {
      expect(
        problemsWith(map: {'[0, 3], [3, 0], ': ''}),
        contains('4 relics: fewer than relics_to_hold 5'),
      );
      expect(
        problemsWith(
          map: {'relics: [': 'relics: [[1, 2], [2, 2], [3, 2], [4, 2], '},
        ),
        contains('10 relics let two teams hold 5 at once (RELIC-17)'),
      );
    });

    test('RELIC-02 decision 216 a relic starts on solid ground, an island '
        'included, alone on its cell', () {
      expect(
        problemsWith(map: {'[11, 3]': '[5, 3]'}),
        contains('tile 1_0: cell (5, 3): relics[2]: is on water (river)'),
      );
      expect(
        problemsWith(map: {'[11, 3]': '[0, 3]'}),
        contains('tile 0_0: cell (0, 3): relics[2]: shares its cell'),
      );
    });

    test('MAP-03 a map supports a team count', () {
      expect(
        problemsWith(
          map: {
            'teams:\n  2: [[0, 0], [11, 0]]\n  3: [[0, 0], [11, 0], [0, 7]]':
                'teams: {}',
          },
        ),
        contains('supports no team count'),
      );
    });

    test('MAP-04 HQ-01 each team count has its number of starting points', () {
      expect(
        problemsWith(map: {'teams:\n': 'teams:\n  1: [[3, 3]]\n'}),
        contains('teams.1: a battle has 2 teams or more'),
      );
      expect(
        problemsWith(map: {'[[0, 0], [11, 0], [0, 7]]': '[[0, 0], [11, 0]]'}),
        contains('teams.3: has 2 starting points for 3 teams'),
      );
    });

    test('decision 216 an HQ starts on the ground, on land, alone', () {
      expect(
        problemsWith(map: {', [0, 7]]': ', [9, 6, sky]]'}),
        contains(
          'tile 2_1: cell sky(9, 6): teams.3: an HQ starts on the '
          'ground',
        ),
      );
      expect(
        problemsWith(map: {'2: [[0, 0], [11, 0]]': '2: [[0, 0], [5, 0]]'}),
        contains('tile 1_0: cell (5, 0): teams.2: is on water (river)'),
      );
      expect(
        problemsWith(map: {'2: [[0, 0], [11, 0]]': '2: [[0, 0], [0, 0]]'}),
        contains('tile 0_0: cell (0, 0): teams.2: shares its cell'),
      );
    });
  });
}
