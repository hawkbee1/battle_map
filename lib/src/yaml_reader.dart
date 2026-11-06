import 'package:battle_map/src/map_format.dart';
import 'package:battle_pathfinding/battle_pathfinding.dart';
import 'package:yaml/yaml.dart';

/// Island names: letters, digits, `_` and `-`, so they stay plain YAML.
final islandNamePattern = RegExp(r'^[a-z][a-z0-9_-]*$');

/// {@template yaml_reader}
/// A value of a YAML [file] at a dotted [key], read with error messages
/// that name both: each value out of the format throws a
/// [MapFormatException].
/// {@endtemplate}
final class YamlReader {
  /// {@macro yaml_reader}
  new(this.file, this.key, this.value);

  /// The root of [text], the content of [file].
  factory parse(String file, String text) {
    final Object? value;
    try {
      value = loadYaml(text);
    } on YamlException catch (error) {
      throw MapFormatException(file: file, key: '', problem: error.message);
    }
    return YamlReader(file, '', value);
  }

  /// The file, for error messages.
  final String file;

  /// The dotted key of [value] in [file].
  final String key;

  /// The value.
  final Object? value;

  /// Throws a [MapFormatException] at this key.
  Never fail(String problem) =>
      throw MapFormatException(file: file, key: key, problem: problem);

  String _keyOf(Object name) => key.isEmpty ? '$name' : '$key.$name';

  YamlMap get _map => switch (value) {
    final YamlMap map => map,
    _ => fail('must be a map'),
  };

  /// Whether this map has the key [name].
  bool has(String name) => _map.containsKey(name);

  /// The value of [name] in this map; it must be there.
  YamlReader child(String name) => has(name)
      ? YamlReader(file, _keyOf(name), _map[name])
      : YamlReader(file, _keyOf(name), null).fail('is missing');

  /// The keys and values of this map.
  Iterable<(String, YamlReader)> get entries => [
    for (final MapEntry(:Object key, :value) in _map.entries)
      ('$key', YamlReader(file, _keyOf(key), value)),
  ];

  /// The items of this list.
  List<YamlReader> get items => switch (value) {
    final YamlList list => [
      for (final (index, item) in list.indexed)
        YamlReader(file, '$key[$index]', item),
    ],
    _ => fail('must be a list'),
  };

  /// This value as text.
  String get string => switch (value) {
    final String text => text,
    _ => fail('must be text'),
  };

  /// This value as text or a list of texts.
  List<String> get strings =>
      value is YamlList ? [for (final item in items) item.string] : [string];

  /// This value as an island name.
  String get islandName => islandNamePattern.hasMatch(string)
      ? string
      : fail('must match $islandNamePattern');

  /// This value as a whole number.
  int get integer => switch (value) {
    final int number => number,
    _ => fail('must be a whole number'),
  };

  /// This value as a whole number above zero.
  int get positive => integer > 0 ? integer : fail('must be positive');

  /// This value as a number.
  double get number => switch (value) {
    final num number => number.toDouble(),
    _ => fail('must be a number'),
  };

  /// This value as true or false.
  bool get boolean => switch (value) {
    final bool flag => flag,
    _ => fail('must be true or false'),
  };

  /// `[x, y]` on the ground, `[x, y, island]` on a floating island.
  CellRef get cell {
    final parts = items;
    if (parts.length != 2 && parts.length != 3) {
      fail('must be [x, y] or [x, y, island]');
    }
    return CellRef(
      parts[0].integer,
      parts[1].integer,
      surface: parts.length == 3 ? parts[2].islandName : groundSurface,
    );
  }

  /// `[x, y, width, depth]`.
  (int, int, int, int) get area {
    final parts = items;
    if (parts.length != 4) fail('must be [x, y, width, depth]');
    return (
      parts[0].integer,
      parts[1].integer,
      parts[2].positive,
      parts[3].positive,
    );
  }
}
