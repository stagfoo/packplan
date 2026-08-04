import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Reads and writes the whole plan list as one JSON file. There is never much
/// data here — a few containers with a few dozen goods — so rewriting the file
/// on each change keeps things simple and atomic enough.
class GearRepository {
  GearRepository({Directory? directory}) : _directory = directory;

  Directory? _directory;

  Future<File> _file() async {
    _directory ??= await getApplicationDocumentsDirectory();
    return File('${_directory!.path}/packplan.json');
  }

  Future<List<GearContainer>> load() async {
    final file = await _file();
    if (!await file.exists()) return [];

    try {
      final decoded = jsonDecode(await file.readAsString());
      final containers = (decoded as Map<String, dynamic>)['containers'];
      return (containers as List<dynamic>)
          .map((c) => GearContainer.fromJson(c as Map<String, dynamic>))
          .toList();
    } on FormatException {
      // A corrupt file should not brick the app — start over rather than
      // refusing to launch.
      return [];
    }
  }

  Future<void> save(List<GearContainer> containers) async {
    final file = await _file();
    await file.parent.create(recursive: true);

    // Write beside the real file and rename, so an interrupted write cannot
    // leave a half-written plan behind.
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({'containers': containers.map((c) => c.toJson()).toList()}),
    );
    await temp.rename(file.path);
  }
}
