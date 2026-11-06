/// The first map from real data (stack decision 5, authoring step 1):
/// heights from IGN RGE ALTI, terrain, water, roads, bridges, buildings
/// and trees from OpenStreetMap, by the rules of an import file.
///
/// Pure Dart with no I/O, like the rest of the package: the tools in
/// `bin/` fetch the data and read and write the files. Neither the host
/// nor the client needs it.
library;

export 'src/import/import_spec.dart';
export 'src/import/lambert93.dart';
export 'src/import/map_import.dart';
export 'src/import/map_sources.dart';
export 'src/import/osm.dart';
export 'src/import/raster.dart';
