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
    this.loadouts = const [],
    this.plans = const [],
    this.customUnits = const [],
  });

  final AppSettings settings;
  final List<GearItem> items;
  final List<Loadout> loadouts;
  final List<PlanRecord> plans;
  final List<CustomUnit> customUnits;
}

/// The schema version written to the file.
///
/// 1 — gear lived inside its container.
/// 2 — gear moved into a shared library; containers held entries.
/// 3 — containers became library items; a plan is one container plus gear.
const int kSchemaVersion = 3;

/// Reads and writes everything as one JSON file. There is never much data here
/// — a few plans and a few dozen items — so rewriting the file on each change
/// keeps things simple and atomic enough.
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
    // Loadouts were called recipes in the first release.
    loadouts: ((json['loadouts'] ?? json['recipes']) as List<dynamic>? ?? [])
        .map((loadout) => Loadout.fromJson(loadout as Map<String, dynamic>))
        .toList(),
    plans: (json['plans'] as List<dynamic>? ?? [])
        .map((plan) => PlanRecord.fromJson(plan as Map<String, dynamic>))
        .toList(),
    customUnits: (json['customUnits'] as List<dynamic>? ?? [])
        .map((unit) => CustomUnit.fromJson(unit as Map<String, dynamic>))
        .toList(),
  );

  /// Brings an older file up to [kSchemaVersion], one step at a time.
  Map<String, dynamic> _migrate(Map<String, dynamic> json) {
    var working = json;
    var version = working['version'] as int? ?? 1;

    if (version < 2) {
      working = _liftGoodsIntoLibrary(working);
      version = 2;
    }
    if (version < 3) {
      working = _liftContainersIntoLibrary(working);
      version = 3;
    }

    return {...working, 'version': kSchemaVersion};
  }

  /// Version 1 kept gear inside its container, with placements keyed by the
  /// good's own id. Each old good becomes a library item plus one container
  /// entry pointing at it.
  Map<String, dynamic> _liftGoodsIntoLibrary(Map<String, dynamic> json) {
    final items = <Map<String, dynamic>>[];
    final containers = <Map<String, dynamic>>[];

    for (final raw in (json['containers'] as List<dynamic>? ?? [])) {
      final container = Map<String, dynamic>.from(raw as Map<String, dynamic>);
      final goods = (container.remove('goods') as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      final oldPlacements =
          container.remove('placements') as Map<String, dynamic>? ?? {};

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
      ...json,
      'settings': json['settings'] ?? const <String, dynamic>{},
      'items': items,
      'containers': containers,
    };
  }

  /// Version 2 kept containers as their own kind of thing. A container is just
  /// gear that happens to hold other gear, so each one becomes a library item
  /// plus a plan built around it.
  Map<String, dynamic> _liftContainersIntoLibrary(Map<String, dynamic> json) {
    final items = [...(json['items'] as List<dynamic>? ?? [])];
    final plans = <Map<String, dynamic>>[];

    for (final raw in (json['containers'] as List<dynamic>? ?? [])) {
      final container = raw as Map<String, dynamic>;

      final itemId = _uuid.v4();
      items.add({
        'id': itemId,
        'name': container['name'],
        'width': container['width'],
        'height': container['height'],
        if (container['depth'] != null) 'depth': container['depth'],
        'colorValue': container['colorValue'],
        'rotatable': true,
        'tags': <String>[],
        'isContainer': true,
      });

      plans.add({
        // The container's id carries over as the plan's, so nothing else that
        // referenced it has to change.
        'id': container['id'],
        'name': container['name'],
        'containerItemId': itemId,
        'tolerance': container['tolerance'] ?? 0,
        'items': container['entries'] ?? const <dynamic>[],
        'placements': container['placements'] ?? const <String, dynamic>{},
      });
    }

    final migrated = {...json, 'items': items, 'plans': plans};
    migrated.remove('containers');
    return migrated;
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
        'loadouts': data.loadouts.map((loadout) => loadout.toJson()).toList(),
        'plans': data.plans.map((plan) => plan.toJson()).toList(),
        'customUnits': data.customUnits.map((u) => u.toJson()).toList(),
      }),
    );
    await temp.rename(file.path);
  }
}
