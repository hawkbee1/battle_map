import 'package:battle_map/map_import.dart';
import 'package:test/test.dart';

void main() {
  group('cellsInside', () {
    test('takes the cells whose centre is inside, row by row', () {
      final square = [
        (1.0, 1.0),
        (3.0, 1.0),
        (3.0, 3.0),
        (1.0, 3.0),
        (1.0, 1.0),
      ];

      expect(cellsInside([square], width: 5, depth: 5).toList(), [
        (1, 1),
        (2, 1),
        (1, 2),
        (2, 2),
      ]);
    });

    test('leaves out a hole: the even-odd rule', () {
      final outer = [
        (0.0, 0.0),
        (5.0, 0.0),
        (5.0, 5.0),
        (0.0, 5.0),
        (0.0, 0.0),
      ];
      final hole = [(2.0, 2.0), (3.0, 2.0), (3.0, 3.0), (2.0, 3.0), (2.0, 2.0)];

      final cells = cellsInside([outer, hole], width: 5, depth: 5).toSet();

      expect(cells, hasLength(24));
      expect(cells, isNot(contains((2, 2))));
    });

    test('reads a ring cut in several ways, as a multipolygon gives it', () {
      final north = [(0.0, 0.0), (2.0, 0.0), (2.0, 2.0)];
      final south = [(2.0, 2.0), (0.0, 2.0), (0.0, 0.0)];

      expect(cellsInside([north, south], width: 5, depth: 5).toSet(), {
        (0, 0),
        (1, 0),
        (0, 1),
        (1, 1),
      });
    });

    test('keeps to the map', () {
      final big = [(-3.0, -3.0), (9.0, -3.0), (9.0, 9.0), (-3.0, 9.0)];

      expect(
        cellsInside(
          [
            [...big, big.first],
          ],
          width: 2,
          depth: 3,
        ).toList(),
        [(0, 0), (1, 0), (0, 1), (1, 1), (0, 2), (1, 2)],
      );
    });

    test('a point or nothing covers no cell', () {
      expect(cellsInside([], width: 5, depth: 5), isEmpty);
      expect(
        cellsInside(
          [
            [(1.5, 1.5)],
          ],
          width: 5,
          depth: 5,
        ),
        isEmpty,
      );
    });
  });

  group('cellsAlong', () {
    test('follows a line cell by cell, from its start', () {
      expect(cellsAlong([(3.5, 0.5), (0.5, 0.5)]), [
        (3, 0),
        (2, 0),
        (1, 0),
        (0, 0),
      ]);
      expect(cellsAlong([(0.5, 0.2), (0.5, 2.7)]), [(0, 0), (0, 1), (0, 2)]);
    });

    test('a diagonal stays 4-connected, through corners too', () {
      final cells = cellsAlong([(0.5, 0.5), (3.5, 3.5)]);

      expect(cells.first, (0, 0));
      expect(cells.last, (3, 3));
      for (var index = 1; index < cells.length; index++) {
        final (x1, y1) = cells[index - 1];
        final (x2, y2) = cells[index];
        expect((x1 - x2).abs() + (y1 - y2).abs(), 1, reason: '${cells[index]}');
      }
    });

    test('a shallow slope steps along x, then y', () {
      expect(cellsAlong([(0.5, 0.5), (3.5, 1.5)]), [
        (0, 0),
        (1, 0),
        (2, 0),
        (2, 1),
        (3, 1),
      ]);
      expect(cellsAlong([(0.5, 0.5), (1.5, 3.5)]), [
        (0, 0),
        (0, 1),
        (1, 1),
        (1, 2),
        (1, 3),
      ]);
    });

    test('joins its segments and may leave the map', () {
      expect(cellsAlong([(-0.5, 0.5), (0.5, 0.5), (0.5, 1.5)]), [
        (-1, 0),
        (0, 0),
        (0, 1),
      ]);
      expect(cellsAlong([(2.5, 2.5)]), [(2, 2)]);
    });
  });

  group('cellsNear', () {
    test('takes the cells whose centre is within half the width', () {
      expect(cellsNear([(0.5, 2.5), (4.5, 2.5)], 1, width: 5, depth: 5), {
        for (var x = 0; x < 5; x++) ...{(x, 1), (x, 2), (x, 3)},
      });
    });

    test('keeps to the map, and a point keeps its own cell', () {
      expect(cellsNear([(0.5, 0.5), (0.5, 0.5)], 0.6, width: 1, depth: 1), {
        (0, 0),
      });
    });
  });

  test('middleCell is the cell of the mean of the points', () {
    expect(
      middleCell([
        [(1.0, 1.0), (3.0, 1.0)],
        [(3.0, 3.0), (1.0, 3.0)],
      ]),
      (2, 2),
    );
  });
}
