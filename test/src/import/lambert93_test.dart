import 'dart:math' as math;

import 'package:battle_map/map_import.dart';
import 'package:test/test.dart';

void main() {
  const lambert = Lambert93();

  group('Lambert93', () {
    test('its origin, 3° E 46.5° N, is at 700 km E, 6,600 km N', () {
      final (x, y) = lambert.project(3, 46.5);

      expect(x, closeTo(700000, 1e-6));
      expect(y, closeTo(6600000, 1e-6));
    });

    test('north is up on the central meridian, east is right', () {
      final (x1, y1) = lambert.project(3, 49);
      final (x2, _) = lambert.project(-1, 46.5);

      expect(x1, closeTo(700000, 1e-6));
      expect(y1, greaterThan(6600000));
      expect(x2, lessThan(700000));
    });

    test('keeps distances along its standard parallels, 44° and 49° N', () {
      // A short arc of a parallel of the GRS80 ellipsoid: N cos φ Δλ.
      const a = 6378137.0;
      const f = 1 / 298.257222101;
      for (final lat in [44.0, 49.0]) {
        final phi = lat * math.pi / 180;
        const e2 = 2 * f - f * f;
        final n = a / math.sqrt(1 - e2 * math.pow(math.sin(phi), 2));
        const step = 0.001;
        final arc = n * math.cos(phi) * step * math.pi / 180;
        final (x1, y1) = lambert.project(3, lat);
        final (x2, y2) = lambert.project(3 + step, lat);
        final chord = math.sqrt(math.pow(x2 - x1, 2) + math.pow(y2 - y1, 2));

        expect(chord, closeTo(arc, arc * 1e-6), reason: '$lat° N');
      }
    });

    test('unproject undoes project', () {
      for (final (lon, lat) in [(-1.09, 49.11), (7.5, 43.7), (3.0, 51.0)]) {
        final (x, y) = lambert.project(lon, lat);
        final (lon2, lat2) = lambert.unproject(x, y);

        expect(lon2, closeTo(lon, 1e-9));
        expect(lat2, closeTo(lat, 1e-9));
      }
    });
  });
}
