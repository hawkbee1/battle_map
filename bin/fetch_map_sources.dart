import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:battle_map/map_import.dart';

const _usage = '''
Fetches the real data of a Battle Team map (stack decision 5, authoring):
the IGN RGE ALTI heights of its cells and the OpenStreetMap elements its
import rules read.

Usage: dart run battle_map:fetch_map_sources <import.yaml> <downloads>
  <import.yaml>  the import file: the area and the rules
  <downloads>    an empty folder outside the repository: downloaded data is
                 untrusted input. It gets elevation.bil, osm.json and
                 sources.yaml.''';

Future<void> main(List<String> arguments) async {
  if (arguments case [final importPath, final downloads]) {
    exitCode = await _fetch(importPath, downloads);
  } else {
    stderr.writeln(_usage);
    exitCode = 64;
  }
}

Future<int> _fetch(String importPath, String downloads) async {
  final spec = ImportSpec.parse(File(importPath).readAsStringSync());
  Directory(downloads).createSync(recursive: true);
  final client = HttpClient()..userAgent = 'battle_map importer';
  try {
    final heights = BytesBuilder(copy: false);
    for (final request in elevationRequests(spec)) {
      stdout.writeln(
        'Heights: rows ${request.firstRow} to '
        '${request.firstRow + request.rows - 1}',
      );
      final bytes = await _get(client, request.uri);
      if (bytes.length != spec.width * request.rows * 4) {
        stderr.writeln(
          'The WMS answered ${bytes.length} bytes: '
          '${utf8.decode(bytes, allowMalformed: true)}',
        );
        return 1;
      }
      heights.add(bytes);
      // The Géoplateforme allows one request a second.
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    File('$downloads/$elevationFile').writeAsBytesSync(heights.takeBytes());

    stdout.writeln('OpenStreetMap: ${spec.keys.join(', ')}');
    final osm = await _post(client, Uri.parse(overpassUrl), {
      'data': overpassQuery(spec),
    });
    File('$downloads/$osmFile').writeAsBytesSync(osm);
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    File('$downloads/sources.yaml')
        .writeAsStringSync('elevation_fetched: "$today"\n');
    stdout.writeln('Fetched into $downloads.');
    return 0;
  } on HttpException catch (error) {
    stderr.writeln(error);
    return 1;
  } finally {
    client.close();
  }
}

Future<Uint8List> _get(HttpClient client, Uri uri) async =>
    await _read(await (await client.getUrl(uri)).close(), uri);

Future<Uint8List> _post(
  HttpClient client,
  Uri uri,
  Map<String, String> form,
) async {
  final request = await client.postUrl(uri)
    ..headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    )
    ..write(Uri(queryParameters: form).query);
  return await _read(await request.close(), uri);
}

Future<Uint8List> _read(HttpClientResponse response, Uri uri) async {
  final bytes = BytesBuilder(copy: false);
  await response.forEach(bytes.add);
  if (response.statusCode != HttpStatus.ok) {
    final body = utf8.decode(bytes.takeBytes(), allowMalformed: true);
    throw HttpException('${response.statusCode}: $body', uri: uri);
  }
  return bytes.takeBytes();
}
