import 'dart:math' as math;

/// {@template lambert93}
/// The French official projection Lambert-93 (EPSG:2154): a Lambert
/// conformal conic projection of the GRS80 ellipsoid with standard
/// parallels 44° and 49° N, origin 46.5° N 3° E, false easting 700 km and
/// false northing 6,600 km. IGN publishes its elevation grids in it; the
/// map importer projects OpenStreetMap's longitudes and latitudes (WGS84,
/// within a metre of RGF93 here) into it.
/// {@endtemplate}
final class Lambert93 {
  /// {@macro lambert93}
  const new();

  static const double _a = 6378137;
  static const double _flattening = 1 / 298.257222101;
  static final double _e = math.sqrt(
    2 * _flattening - _flattening * _flattening,
  );
  static const double _lon0 = 3 * math.pi / 180;
  static const double _x0 = 700000;
  static const double _y0 = 6600000;

  static double _m(double lat) =>
      math.cos(lat) / math.sqrt(1 - math.pow(_e * math.sin(lat), 2));

  static double _t(double lat) =>
      math.tan(math.pi / 4 - lat / 2) /
      math.pow((1 - _e * math.sin(lat)) / (1 + _e * math.sin(lat)), _e / 2);

  static final double _lat1 = _radians(44);
  static final double _lat2 = _radians(49);
  static final double _n =
      (math.log(_m(_lat1)) - math.log(_m(_lat2))) /
      (math.log(_t(_lat1)) - math.log(_t(_lat2)));
  static final double _f = _m(_lat1) / (_n * math.pow(_t(_lat1), _n));
  static final double _r0 = _a * _f * math.pow(_t(_radians(46.5)), _n);

  static double _radians(double degrees) => degrees * math.pi / 180;

  /// The easting and northing, in metres, of [lon] and [lat] in degrees.
  (double, double) project(double lon, double lat) {
    final r = _a * _f * math.pow(_t(_radians(lat)), _n);
    final theta = _n * (_radians(lon) - _lon0);
    return (_x0 + r * math.sin(theta), _y0 + _r0 - r * math.cos(theta));
  }

  /// The longitude and latitude, in degrees, of easting [x] and northing
  /// [y].
  (double, double) unproject(double x, double y) {
    final dx = x - _x0;
    final dy = _r0 - (y - _y0);
    final r = math.sqrt(dx * dx + dy * dy);
    final theta = math.atan2(dx, dy);
    final t = math.pow(r / (_a * _f), 1 / _n);
    var lat = math.pi / 2 - 2 * math.atan(t);
    for (var step = 0; step < 8; step++) {
      final sine = _e * math.sin(lat);
      lat =
          math.pi / 2 -
          2 * math.atan(t * math.pow((1 - sine) / (1 + sine), _e / 2));
    }
    return ((theta / _n + _lon0) * 180 / math.pi, lat * 180 / math.pi);
  }
}
