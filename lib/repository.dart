import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'units.dart';

/// Everything the app persists.
class GearData {
  const GearData({
    this.settings = const AppSettings(),
    this.items = const [],
    this.recipes = const [],
    this.containers = const [],
    this.customUnits = const [],
  });

  final AppSettings settings;
  final List<GearItem> items;
  final List<Recipe> recipes;
  final List<GearContainer> containers;
  final List<CustomUnit> customUnits;
}

/// The schema version written to the file. Bumped when the shape changes so
/// [_migrate] knows what it is looking at.
const int kSchemaVersion = 2;

/// Reads and writes everything as one JSON file. There is never much data here
/// — a few containers and a few dozen items — so rewriting the file on each
/// change keeps things simple and atomic enough.
class GearRepository {
  GearRepository({Directory? directory, Uuid? uuid})
    : _directory = directory,
      _uuid = uuid ?? const Uuid();

  Directory? _directory;
  final Uuid _uuid;

  Future<File> _file() async {
    _directory ??= await getApplicationDocumentsDirectory();
    return File('${_directory!.path}/packplan.json');
  }

  Future<GearData> load() async {
    final file = await _file();
    if (!await file.exists()) return const GearData();

    try {
      final json = jsonDecode(await file.readAsString());
      return _parse(_migrate(json as Map<String, dynamic>));
    } on FormatException {
      // A corrupt file should not brick the app — start over rather than
      // refusing to launch.
      return const GearData();
    } on TypeError {
      return const GearData();
    }
  }

  GearData _parse(Map<String, dynamic> json) => GearData(
    settings: AppSettings.fromJson(
      json['settings'] as Map<String, dynamic>? ?? const {},
    ),
    items: (json['items'] as List<dynamic>? ?? [])
        .map((item) => GearItem.fromJson(item as Map<String, dynamic>))
        .toList(),
    recipes: (json['recipes'] as List<dynamic>? ?? [])
        .map((recipe) => Recipe.fromJson(recipe as Map<String, dynamic>))
        .toList(),
    containers: (json['containers'] as List<dynamic>? ?? [])
        .map((c) => GearContainer.fromJson(c as Map<String, dynamic>))
        .toList(),
    customUnits: (json['customUnits'] as List<dynamic>? ?? [])
        .map((unit) => CustomUnit.fromJson(unit as Map<String, dynamic>))
        .toList(),
  );

  /// Version 1 kept gear inside its container, with placements keyed by the
  /// good's own id. Version 2 moved gear into a shared library, so each old
  /// good becomes a library item plus one container entry pointing at it.
  Map<String, dynamic> _migrate(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 1;
    if (version >= kSchemaVersion) return json;

    final items = <Map<String, dynamic>>[];
    final containers = <Map<String, dynamic>>[];

    for (final raw in (json['containers'] as List<dynamic>? ?? [])) {
      final container = Map<String, dynamic>.from(raw as Map<String, dynamic>);
      final goods = (container.remove('goods') as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      final oldPlacements =
          (container.remove('placements') as Map<String, dynamic>? ?? {});

      final entries = <Map<String, dynamic>>[];
      final placements = <String, dynamic>{};

      for (final good in goods) {
        // Old goods were container-scoped, so their ids are already unique
        // across the file and can be reused as library item ids.
        final itemId = good['id'] as String;
        items.add({...good, 'tags': <String>[]});

        final entryId = _uuid.v4();
        entries.add({'id': entryId, 'itemId': itemId});

        final placement = oldPlacements[itemId] as Map<String, dynamic>?;
        if (placement != null) {
          placements[entryId] = {...placement, 'entryId': entryId}
            ..remove('goodId');
        }
      }

      containers.add({
        ...container,
        'tolerance': container['tolerance'] ?? 0,
        'entries': entries,
        'placements': placements,
      });
    }

    return {
      'version': kSchemaVersion,
      'settings': json['settings'] ?? const <String, dynamic>{},
      'items': items,
      'recipes': json['recipes'] ?? const <dynamic>[],
      'containers': containers,
      'customUnits': json['customUnits'] ?? const <dynamic>[],
    };
  }

  Future<void> save(GearData data) async {
    final file = await _file();
    await file.parent.create(recursive: true);

    // Write beside the real file and rename, so an interrupted write cannot
    // leave a half-written plan behind.
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'version': kSchemaVersion,
        'settings': data.settings.toJson(),
        'items': data.items.map((item) => item.toJson()).toList(),
        'recipes': data.recipes.map((recipe) => recipe.toJson()).toList(),
        'containers': data.containers.map((c) => c.toJson()).toList(),
        'customUnits': data.customUnits.map((u) => u.toJson()).toList(),
      }),
    );
    await temp.rename(file.path);
  }
}
