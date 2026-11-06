import 'dart:convert';

import 'package:battle_map/src/map_format.dart';

/// A longitude and a latitude, in degrees.
typedef LonLat = (double, double);

/// The kind of an OpenStreetMap element.
enum OsmType {
  /// A point.
  node,

  /// A line, or an area when it is closed.
  way,

  /// A group of ways: a multipolygon's outer and inner rings.
  relation,
}

/// {@template osm_element}
/// An OpenStreetMap element with its geometry: a node's one point, a way's
/// points, a relation's member ways.
/// {@endtemplate}
final class OsmElement {
  /// {@macro osm_element}
  const new({
    required this.type,
    required this.id,
    required this.tags,
    required this.paths,
  });

  /// Node, way or relation.
  final OsmType type;

  /// Its OpenStreetMap id.
  final int id;

  /// Its tags.
  final Map<String, String> tags;

  /// Its points: one path of one point for a node, one path for a way, a
  /// path per member way for a relation.
  final List<List<LonLat>> paths;

  /// Whether it can be an area: a relation, or a way that ends where it
  /// starts.
  bool get isArea =>
      type == OsmType.relation ||
      (type == OsmType.way &&
          paths.single.length > 3 &&
          paths.single.first == paths.single.last);
}

/// {@template osm_extract}
/// The elements of an Overpass API answer (`[out:json]`, `out geom`), and
/// the date of the OpenStreetMap data it holds.
/// {@endtemplate}
final class OsmExtract {
  /// {@macro osm_extract}
  const new({required this.elements, required this.timestamp});

  /// Reads an Overpass answer. Throws a [MapFormatException] naming [file]
  /// when it is not one.
  factory parse(String json, {String file = 'osm.json'}) {
    Never fail(String key, String problem) =>
        throw MapFormatException(file: file, key: key, problem: problem);
    final Object? root;
    try {
      root = jsonDecode(json);
    } on FormatException catch (error) {
      fail('', error.message);
    }
    if (root case {
      'osm3s': {'timestamp_osm_base': final String timestamp},
      'elements': final List<Object?> elements,
    }) {
      return OsmExtract(
        timestamp: timestamp,
        elements: [
          for (final (index, element) in elements.indexed)
            _element(element) ??
                fail('elements[$index]', 'is not a node, way or relation'),
        ],
      );
    }
    fail('', 'is not an Overpass answer with out geom');
  }

  /// The elements, in the answer's order.
  final List<OsmElement> elements;

  /// When the OpenStreetMap data was last updated, as the Overpass API
  /// gives it.
  final String timestamp;

  static OsmElement? _element(Object? element) {
    LonLat? point(Object? node) => switch (node) {
      {'lon': final num lon, 'lat': final num lat} => (
        lon.toDouble(),
        lat.toDouble(),
      ),
      _ => null,
    };
    List<LonLat> path(List<Object?> geometry) => [
      for (final node in geometry) ?point(node),
    ];
    Map<String, String> tagsOf(Map<Object?, Object?> element) => {
      if (element['tags'] case final Map<Object?, Object?> tags)
        for (final MapEntry(:key, :value) in tags.entries) '$key': '$value',
    };
    return switch (element) {
      {'type': 'node', 'id': final int id} when point(element) != null =>
        OsmElement(
          type: OsmType.node,
          id: id,
          tags: tagsOf(element),
          paths: [
            [point(element)!],
          ],
        ),
      {
        'type': 'way',
        'id': final int id,
        'geometry': final List<Object?> geometry,
      } =>
        OsmElement(
          type: OsmType.way,
          id: id,
          tags: tagsOf(element),
          paths: [path(geometry)],
        ),
      {
        'type': 'relation',
        'id': final int id,
        'members': final List<Object?> members,
      } =>
        OsmElement(
          type: OsmType.relation,
          id: id,
          tags: tagsOf(element),
          paths: [
            for (final member in members)
              if (member case {
                'type': 'way',
                'geometry': final List<Object?> geometry,
              })
                path(geometry),
          ],
        ),
      _ => null,
    };
  }
}
