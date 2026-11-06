import 'dart:math' as math;

import 'package:battle_map/src/import/import_spec.dart';
import 'package:battle_map/src/import/lambert93.dart';

/// The IGN Géoplateforme raster WMS, which serves RGE ALTI heights as
/// 32-bit floats.
const ignWmsUrl = 'https://data.geopf.fr/wms-r';

/// The IGN layer of RGE ALTI heights (1 m and 5 m grids).
const rgeAltiLayer = 'ELEVATION.ELEVATIONGRIDCOVERAGE.HIGHRES';

/// The public Overpass API endpoint.
const overpassUrl = 'https://overpass-api.de/api/interpreter';

/// The most pixels the IGN WMS serves along a side.
const ignWmsMaxPixels = 5000;

/// The margin, in degrees, added around the map's box for OpenStreetMap,
/// so the elements that cross its edges come whole.
const _margin = 0.005;

/// The south, west, north and east bounds, in degrees, of the box that
/// holds the map of [spec].
(double, double, double, double) boundsOf(ImportSpec spec) {
  const lambert = Lambert93();
  final east = spec.originX + spec.width * spec.cellSizeM;
  final south = spec.originY - spec.depth * spec.cellSizeM;
  // A Lambert-93 edge is curved in degrees: its middle is checked too.
  final corners = [
    for (final x in [spec.originX, (spec.originX + east) / 2, east])
      for (final y in [south, (south + spec.originY) / 2, spec.originY])
        lambert.unproject(x, y),
  ];
  return (
    corners.map((c) => c.$2).reduce(math.min) - _margin,
    corners.map((c) => c.$1).reduce(math.min) - _margin,
    corners.map((c) => c.$2).reduce(math.max) + _margin,
    corners.map((c) => c.$1).reduce(math.max) + _margin,
  );
}

/// The Overpass query of every element with a key the rules of [spec]
/// read, in its box, with their geometry.
String overpassQuery(ImportSpec spec) {
  final (south, west, north, east) = boundsOf(spec);
  final box = [south, west, north, east].map(_degrees).join(',');
  final keys = spec.keys.toList()..sort();
  return '[out:json][timeout:600];'
      '(${keys.map((key) => 'nwr["$key"]($box);').join()});'
      'out geom;';
}

String _degrees(double value) => value.toStringAsFixed(6);

/// One request of heights: `rows` rows of the map from `firstRow`, at
/// `uri`.
typedef ElevationRequest = ({int firstRow, int rows, Uri uri});

/// The requests that fetch the heights of [spec]'s map from the IGN WMS,
/// one value at the centre of each cell, in strips of at most [maxRows]
/// rows. Throws an [ArgumentError] when the map is wider than the WMS
/// serves.
List<ElevationRequest> elevationRequests(
  ImportSpec spec, {
  int maxRows = 1000,
}) {
  if (spec.width > ignWmsMaxPixels) {
    throw ArgumentError.value(
      spec.width,
      'width',
      'is more than the $ignWmsMaxPixels cells the WMS serves',
    );
  }
  final rowsPerRequest = math.min(maxRows, ignWmsMaxPixels);
  final east = spec.originX + spec.width * spec.cellSizeM;
  return [
    for (var first = 0; first < spec.depth; first += rowsPerRequest)
      if (math.min(rowsPerRequest, spec.depth - first) case final rows)
        (
          firstRow: first,
          rows: rows,
          uri: Uri.parse(ignWmsUrl).replace(
            queryParameters: {
              'SERVICE': 'WMS',
              'VERSION': '1.3.0',
              'REQUEST': 'GetMap',
              'LAYERS': rgeAltiLayer,
              'STYLES': 'normal',
              'CRS': 'EPSG:2154',
              'BBOX': [
                spec.originX,
                spec.originY - (first + rows) * spec.cellSizeM,
                east,
                spec.originY - first * spec.cellSizeM,
              ].join(','),
              'WIDTH': '${spec.width}',
              'HEIGHT': '$rows',
              'FORMAT': 'image/x-bil;bits=32',
            },
          ),
        ),
  ];
}
