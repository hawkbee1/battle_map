import 'dart:convert';

import 'package:battle_map/battle_map.dart';
import 'package:battle_map/map_import.dart';
import 'package:test/test.dart';

String answer(List<Object?> elements) => jsonEncode({
  'osm3s': {'timestamp_osm_base': '2026-11-05T21:12:51Z'},
  'elements': elements,
});

Matcher throwsOsm(String key, String problem) => throwsA(
  isA<MapFormatException>()
      .having((error) => error.file, 'file', 'osm.json')
      .having((error) => error.key, 'key', key)
      .having((error) => error.problem, 'problem', contains(problem)),
);

void main() {
  group('OsmExtract', () {
    test('reads nodes, ways and relations with their geometry', () {
      final osm = OsmExtract.parse(
        answer([
          {
            'type': 'node',
            'id': 1,
            'lat': 49.1,
            'lon': -1.1,
            'tags': {'natural': 'tree'},
          },
          {
            'type': 'way',
            'id': 2,
            'tags': {'highway': 'track', 'lanes': 1},
            'geometry': [
              {'lat': 49, 'lon': -1},
              null,
              {'lat': 49.1, 'lon': -1},
            ],
          },
          {
            'type': 'relation',
            'id': 3,
            'tags': {'landuse': 'forest'},
            'members': [
              {
                'type': 'way',
                'role': 'outer',
                'geometry': [
                  {'lat': 49, 'lon': -1},
                  {'lat': 49.1, 'lon': -1},
                ],
              },
              {'type': 'node', 'role': 'label', 'lat': 49, 'lon': -1},
            ],
          },
        ]),
      );

      expect(osm.timestamp, '2026-11-05T21:12:51Z');
      final [node, way, relation] = osm.elements;
      expect((node.type, node.id), (OsmType.node, 1));
      expect(node.tags, {'natural': 'tree'});
      expect(node.paths, [
        [(-1.1, 49.1)],
      ]);
      expect(way.tags, {'highway': 'track', 'lanes': '1'});
      expect(way.paths, [
        [(-1.0, 49.0), (-1.0, 49.1)],
      ]);
      expect(relation.type, OsmType.relation);
      expect(relation.paths, [
        [(-1.0, 49.0), (-1.0, 49.1)],
      ]);
      expect(relation.tags, {'landuse': 'forest'});
    });

    test('an area is a relation or a closed way', () {
      OsmElement way(List<(double, double)> points) =>
          OsmElement(type: OsmType.way, id: 1, tags: const {}, paths: [points]);

      expect(way([(0, 0), (1, 0), (1, 1), (0, 0)]).isArea, isTrue);
      expect(way([(0, 0), (1, 0), (1, 1), (0, 1)]).isArea, isFalse);
      expect(way([(0, 0), (1, 0), (0, 0)]).isArea, isFalse);
      expect(
        const OsmElement(
          type: OsmType.relation,
          id: 1,
          tags: {},
          paths: [],
        ).isArea,
        isTrue,
      );
      expect(
        const OsmElement(
          type: OsmType.node,
          id: 1,
          tags: {},
          paths: [
            [(0, 0)],
          ],
        ).isArea,
        isFalse,
      );
    });

    test('refuses what is not an Overpass answer with geometry', () {
      expect(() => OsmExtract.parse('{'), throwsOsm('', 'Unexpected end'));
      expect(
        () => OsmExtract.parse('{"elements": []}'),
        throwsOsm('', 'not an Overpass answer'),
      );
      expect(
        () => OsmExtract.parse(
          answer([
            {'type': 'way', 'id': 2},
          ]),
        ),
        throwsOsm('elements[0]', 'not a node, way or relation'),
      );
      expect(
        () => OsmExtract.parse(
          answer([
            {'type': 'node', 'id': 2},
          ]),
        ),
        throwsOsm('elements[0]', 'not a node, way or relation'),
      );
    });
  });
}
