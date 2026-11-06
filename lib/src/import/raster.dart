import 'dart:math' as math;

/// A point in cell units: columns east and rows south of the map's
/// north-west corner. Cell `(x, y)` spans `[x, x + 1) × [y, y + 1)`; its
/// centre is `(x + 0.5, y + 0.5)`.
typedef CellPoint = (double, double);

/// The cells of a [width] × [depth] map whose centre is inside [paths],
/// row by row: a cell is inside when a ray from its centre crosses the
/// paths' edges an odd number of times (even-odd rule). The paths need not
/// be joined into rings: a multipolygon's member ways count as they are,
/// as long as together they close.
Iterable<(int, int)> cellsInside(
  List<List<CellPoint>> paths, {
  required int width,
  required int depth,
}) sync* {
  final edges = [
    for (final path in paths)
      for (var index = 1; index < path.length; index++)
        (path[index - 1], path[index]),
  ];
  if (edges.isEmpty) return;
  var top = double.infinity;
  var bottom = double.negativeInfinity;
  for (final ((_, y1), (_, y2)) in edges) {
    top = math.min(top, math.min(y1, y2));
    bottom = math.max(bottom, math.max(y1, y2));
  }
  final firstRow = math.max(0, (top - 0.5).ceil());
  final lastRow = math.min(depth - 1, (bottom - 0.5).floor());
  for (var row = firstRow; row <= lastRow; row++) {
    final centre = row + 0.5;
    final crossings = <double>[
      for (final ((x1, y1), (x2, y2)) in edges)
        if ((y1 <= centre) != (y2 <= centre))
          x1 + (centre - y1) * (x2 - x1) / (y2 - y1),
    ]..sort();
    for (var index = 0; index + 1 < crossings.length; index += 2) {
      final from = math.max(0, (crossings[index] - 0.5).ceil());
      final to = math.min(width - 1, (crossings[index + 1] - 0.5).ceil() - 1);
      for (var column = from; column <= to; column++) {
        yield (column, row);
      }
    }
  }
}

/// The cells [path] passes through, in order from its start, each cell
/// beside the one before it (4-connected): where the path crosses a
/// corner, the cell it grazes is included. Cells may be off the map.
List<(int, int)> cellsAlong(List<CellPoint> path) {
  final cells = <(int, int)>[];
  void add((int, int) cell) {
    if (cells.isEmpty || cells.last != cell) cells.add(cell);
  }

  final (startX, startY) = path.first;
  add((startX.floor(), startY.floor()));
  for (var index = 1; index < path.length; index++) {
    _walk(path[index - 1], path[index], add);
  }
  return cells;
}

/// Adds the cells from the one of [a] to the one of [b], the grid
/// traversal of Amanatides and Woo, stepping one axis at a time.
void _walk(CellPoint a, CellPoint b, void Function((int, int)) add) {
  final (ax, ay) = a;
  final (bx, by) = b;
  var x = ax.floor();
  var y = ay.floor();
  final endX = bx.floor();
  final endY = by.floor();
  final dx = bx - ax;
  final dy = by - ay;
  final stepX = dx.sign.toInt();
  final stepY = dy.sign.toInt();
  final deltaX = dx == 0 ? double.infinity : stepX / dx;
  final deltaY = dy == 0 ? double.infinity : stepY / dy;
  var nextX = dx == 0 ? double.infinity : ((stepX > 0 ? x + 1 : x) - ax) / dx;
  var nextY = dy == 0 ? double.infinity : ((stepY > 0 ? y + 1 : y) - ay) / dy;
  while (x != endX || y != endY) {
    if (y == endY || (x != endX && nextX < nextY)) {
      x += stepX;
      nextX += deltaX;
    } else if (x == endX || nextY < nextX) {
      y += stepY;
      nextY += deltaY;
    } else {
      // Through a corner: the cell beside it keeps the cells 4-connected.
      add((x + stepX, y));
      x += stepX;
      y += stepY;
      nextX += deltaX;
      nextY += deltaY;
    }
    add((x, y));
  }
}

/// The cells of a [width] × [depth] map whose centre is within
/// [halfWidth] cells of [path].
Set<(int, int)> cellsNear(
  List<CellPoint> path,
  double halfWidth, {
  required int width,
  required int depth,
}) {
  final cells = <(int, int)>{};
  for (var index = 1; index < path.length; index++) {
    final (ax, ay) = path[index - 1];
    final (bx, by) = path[index];
    final fromX = math.max(0, (math.min(ax, bx) - halfWidth - 0.5).ceil());
    final toX = math.min(width - 1, (math.max(ax, bx) + halfWidth).floor());
    final fromY = math.max(0, (math.min(ay, by) - halfWidth - 0.5).ceil());
    final toY = math.min(depth - 1, (math.max(ay, by) + halfWidth).floor());
    for (var y = fromY; y <= toY; y++) {
      for (var x = fromX; x <= toX; x++) {
        if (_distance((x + 0.5, y + 0.5), (ax, ay), (bx, by)) <= halfWidth) {
          cells.add((x, y));
        }
      }
    }
  }
  return cells;
}

/// The distance from [p] to the segment from [a] to [b].
double _distance(CellPoint p, CellPoint a, CellPoint b) {
  final (px, py) = p;
  final (ax, ay) = a;
  final (bx, by) = b;
  final dx = bx - ax;
  final dy = by - ay;
  final length = dx * dx + dy * dy;
  final t = length == 0
      ? 0.0
      : (((px - ax) * dx + (py - ay) * dy) / length).clamp(0.0, 1.0);
  final x = ax + t * dx - px;
  final y = ay + t * dy - py;
  return math.sqrt(x * x + y * y);
}

/// The cell of the mean of [paths]' points.
(int, int) middleCell(List<List<CellPoint>> paths) {
  var x = 0.0;
  var y = 0.0;
  var count = 0;
  for (final path in paths) {
    for (final (px, py) in path) {
      x += px;
      y += py;
      count++;
    }
  }
  return ((x / count).floor(), (y / count).floor());
}
