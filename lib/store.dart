import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'packer.dart';
import 'repository.dart';
import 'units.dart';

/// Schema for a standalone gear library export - independent of
/// [kSchemaVersion] (the app's own save-file format), so an exported file
/// keeps working even if the app's internal storage shape changes later.
const int kLibraryExportVersion = 1;

/// What happened when a library export was brought in.
class ImportResult {
  const ImportResult({required this.added, required this.skipped});

  /// Items that were not already in the library by name.
  final int added;

  /// Skipped because something with the same name is already in the
  /// library - so importing the same file twice does not pile up
  /// duplicates.
  final int skipped;
}

/// What happened when the user asked to turn a piece of gear.
enum RotateOutcome {
  rotated,

  /// No orientation the item can be turned into fits the container.
  wontFit,

  /// The plan or the gear is gone.
  notFound,
}

/// Drag positions snap to this many centimetres. Gear measurements are not
/// precise enough to justify anything finer, and it keeps the numbers readable.
const double kDragSnap = 0.5;

/// Owns the gear library, the loadouts, the plans and the settings, and every
/// mutation to them. Saves after each change — there is no explicit save
/// button, and a packing plan you lose on a crash is worse than useless.
class GearStore extends ChangeNotifier {
  GearStore({GearRepository? repository, Uuid? uuid})
    : _repository = repository ?? GearRepository(),
      _uuid = uuid ?? const Uuid();

  final GearRepository _repository;
  final Uuid _uuid;

  AppSettings _settings = const AppSettings();
  List<GearItem> _items = [];
  List<Loadout> _loadouts = [];
  List<PlanRecord> _plans = [];
  List<CustomUnit> _customUnits = [];
  bool _loaded = false;

  AppSettings get settings => _settings;
  List<GearItem> get items => List.unmodifiable(_items);
  List<Loadout> get loadouts => List.unmodifiable(_loadouts);
  List<PlanRecord> get planRecords => List.unmodifiable(_plans);
  List<CustomUnit> get customUnits => List.unmodifiable(_customUnits);
  bool get isLoaded => _loaded;

  /// Library gear that a plan can be built around.
  List<GearItem> get containerItems =>
      _items.where((item) => item.isContainer).toList();

  // ------------------------------------------------------------------- units

  /// The unit currently in use. Falls back to centimetres if the chosen unit
  /// has since been deleted.
  MeasurementUnit get unit =>
      unitById(_settings.unitId) ?? MeasurementUnit.centimetres;

  /// Every unit available to choose from, built-ins first.
  List<MeasurementUnit> get availableUnits => [
    ...MeasurementUnit.builtIns,
    ..._customUnits.map(resolveCustomUnit),
  ];

  MeasurementUnit? unitById(String id) {
    final builtIn = MeasurementUnit.builtInById(id);
    if (builtIn != null) return builtIn;

    for (final custom in _customUnits) {
      if (custom.id == id) return resolveCustomUnit(custom);
    }
    return null;
  }

  CustomUnit? customUnitById(String id) {
    for (final custom in _customUnits) {
      if (custom.id == id) return custom;
    }
    return null;
  }

  /// Turns a stored definition into a usable unit, taking the length from its
  /// source gear when it has one — so re-measuring the gear re-calibrates the
  /// unit — and from the captured length when that gear is gone.
  MeasurementUnit resolveCustomUnit(CustomUnit custom) {
    final sourceId = custom.sourceItemId;
    if (sourceId == null) return custom.resolve();

    final item = itemById(sourceId);
    final axis = custom.sourceAxis;
    if (item == null || axis == null) return custom.resolve();

    return custom.resolve(liveLength: item.dimension(axis));
  }

  /// The gear a derived unit measures by, or null when it is free-form or its
  /// gear has been deleted.
  GearItem? sourceItemFor(CustomUnit custom) {
    final sourceId = custom.sourceItemId;
    return sourceId == null ? null : itemById(sourceId);
  }

  // ----------------------------------------------------------------- lookups

  /// Every tag in use across the library, sorted.
  List<String> get allTags => normaliseTags(_items.expand((item) => item.tags));

  GearItem? itemById(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  Loadout? loadoutById(String id) {
    for (final loadout in _loadouts) {
      if (loadout.id == id) return loadout;
    }
    return null;
  }

  PlanRecord? planRecordById(String id) {
    for (final plan in _plans) {
      if (plan.id == id) return plan;
    }
    return null;
  }

  /// Every plan, resolved. Plans whose container gear has been deleted are
  /// dropped rather than crashing a screen.
  List<Plan> get plans => _plans.map(_resolve).whereType<Plan>().toList();

  Plan? planFor(String planId) {
    final record = planRecordById(planId);
    return record == null ? null : _resolve(record);
  }

  Plan? _resolve(PlanRecord record) {
    final container = itemById(record.containerItemId);
    if (container == null) return null;

    final entries = <PlanEntry>[];
    for (final planItem in record.items) {
      final item = itemById(planItem.itemId);
      if (item == null) continue;
      entries.add(
        PlanEntry(
          id: planItem.id,
          item: item,
          placement: record.placements[planItem.id],
        ),
      );
    }

    return Plan(record: record, container: container, entries: entries);
  }

  // --------------------------------------------------------------- lifecycle

  /// Why loading failed, or null. The app starts empty rather than refusing to
  /// start, so this exists to say so instead of pretending there was no data.
  String? get loadError => _loadError;
  String? _loadError;

  /// Never throws. Whatever goes wrong, loading finishes — a screen stuck on a
  /// spinner tells the user nothing and cannot be recovered from.
  Future<void> load() async {
    try {
      final data = await _repository.load();
      _settings = data.settings;
      _items = [...data.items];
      _loadouts = [...data.loadouts];
      _plans = [...data.plans];
      _customUnits = [...data.customUnits];
      _loadError = null;
    } catch (error) {
      _loadError = '$error';
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> _commit() async {
    notifyListeners();
    await flush();
  }

  /// Writes the current state out. Called after every mutation, and at the end
  /// of a drag by [moveGear].
  Future<void> flush() => _repository.save(
    GearData(
      settings: _settings,
      items: _items,
      loadouts: _loadouts,
      plans: _plans,
      customUnits: _customUnits,
    ),
  );

  void _replace(PlanRecord record) {
    final index = _plans.indexWhere((plan) => plan.id == record.id);
    if (index >= 0) _plans[index] = record;
  }

  /// Picks the palette colour least used so far, so a new thing is easy to pick
  /// out from what is already on the diagram.
  int _nextColor(Iterable<int> taken) {
    final counts = {for (final color in kGearPalette) color: 0};
    for (final color in taken) {
      if (counts.containsKey(color)) counts[color] = counts[color]! + 1;
    }
    return counts.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
  }

  // ---------------------------------------------------------------- settings

  Future<void> setUnit(MeasurementUnit unit) => setUnitId(unit.id);

  Future<void> setUnitId(String unitId) async {
    _settings = _settings.copyWith(unitId: unitId);
    await _commit();
  }

  /// [tolerance] is in centimetres. Only affects plans made from now on;
  /// existing ones keep whatever they were given.
  Future<void> setDefaultTolerance(double tolerance) async {
    _settings = _settings.copyWith(defaultTolerance: tolerance);
    await _commit();
  }

  /// Defines a unit from a plain length, in centimetres — "my hand is 19 cm".
  Future<CustomUnit> addCustomUnit({
    required String name,
    required double centimetres,
  }) async {
    final custom = CustomUnit(
      id: _uuid.v4(),
      name: name,
      centimetres: centimetres < kMinimumUnitLength
          ? kMinimumUnitLength
          : centimetres,
    );
    _customUnits.add(custom);
    await _commit();
    return custom;
  }

  /// Defines a unit from a piece of gear, measured along [axis]. The length
  /// tracks the gear from then on, so correcting the gear's size corrects every
  /// measurement made with it.
  Future<CustomUnit?> addCustomUnitFromItem(
    String itemId, {
    GearAxis? axis,
    String? name,
  }) async {
    final item = itemById(itemId);
    if (item == null) return null;

    final chosen = axis ?? item.longestAxis;
    final length = item.dimension(chosen);
    if (length == null || length < kMinimumUnitLength) return null;

    final custom = CustomUnit(
      id: _uuid.v4(),
      name: name ?? item.name,
      centimetres: length,
      sourceItemId: itemId,
      sourceAxis: chosen,
    );
    _customUnits.add(custom);
    await _commit();
    return custom;
  }

  Future<void> updateCustomUnit(
    String unitId, {
    required String name,
    double? centimetres,
    GearAxis? axis,
  }) async {
    final index = _customUnits.indexWhere((unit) => unit.id == unitId);
    if (index < 0) return;

    final existing = _customUnits[index];
    _customUnits[index] = existing.copyWith(
      name: name,
      centimetres: centimetres == null
          ? null
          : (centimetres < kMinimumUnitLength
                ? kMinimumUnitLength
                : centimetres),
      sourceAxis: axis,
    );
    await _commit();
  }

  /// Deleting the unit in use falls back to centimetres rather than leaving
  /// every measurement dangling.
  Future<void> deleteCustomUnit(String unitId) async {
    _customUnits.removeWhere((unit) => unit.id == unitId);
    if (_settings.unitId == unitId) {
      _settings = _settings.copyWith(unitId: MeasurementUnit.centimetres.id);
    }
    await _commit();
  }

  // ----------------------------------------------------------------- library

  Future<GearItem> addItem({
    required String name,
    required double width,
    required double height,
    double? depth,
    bool rotatable = true,
    List<String> tags = const [],
    bool isContainer = false,
  }) async {
    final item = GearItem(
      id: _uuid.v4(),
      name: name,
      width: width,
      height: height,
      depth: depth,
      colorValue: _nextColor(_items.map((i) => i.colorValue)),
      rotatable: rotatable,
      tags: normaliseTags(tags),
      isContainer: isContainer,
    );
    _items.add(item);
    await _commit();
    return item;
  }

  /// Updating an item's size invalidates its placement everywhere it is used,
  /// so each affected plan finds it a fresh spot. Resizing a *container*
  /// re-packs every plan built on it, since every position is now suspect.
  Future<void> updateItem(
    String itemId, {
    required String name,
    required double width,
    required double height,
    double? depth,
    required bool rotatable,
    required List<String> tags,
    bool? isContainer,
  }) async {
    final index = _items.indexWhere((item) => item.id == itemId);
    if (index < 0) return;

    final existing = _items[index];
    final resized =
        existing.width != width ||
        existing.height != height ||
        existing.depth != depth;

    _items[index] = existing.copyWith(
      name: name,
      width: width,
      height: height,
      depth: depth,
      clearDepth: depth == null,
      rotatable: rotatable,
      tags: normaliseTags(tags),
      isContainer: isContainer,
    );

    if (resized) {
      for (var i = 0; i < _plans.length; i++) {
        final record = _plans[i];

        if (record.containerItemId == itemId) {
          final plan = _resolve(record);
          if (plan != null) {
            _plans[i] = record.copyWith(placements: packPlan(plan).placements);
          }
          continue;
        }

        final affected = record.items
            .where((planItem) => planItem.itemId == itemId)
            .map((planItem) => planItem.id)
            .toSet();
        if (affected.isEmpty) continue;
        _plans[i] = _reseat(record, affected);
      }
    }

    await _commit();
  }

  /// Drops the given entries' placements and finds each a new spot among what
  /// is left.
  PlanRecord _reseat(PlanRecord record, Set<String> entryIds) {
    var placements = {...record.placements}
      ..removeWhere((entryId, _) => entryIds.contains(entryId));
    var working = record.copyWith(placements: placements);

    for (final entryId in entryIds) {
      final plan = _resolve(working);
      if (plan == null) break;
      final entry = plan.entryById(entryId);
      if (entry == null) continue;
      final spot = findSpotFor(plan, entry);
      if (spot == null) continue;
      placements = {...placements, entryId: spot};
      working = working.copyWith(placements: placements);
    }

    return working;
  }

  /// How many plans currently use this item, either as their container or as
  /// gear inside one.
  int usageCount(String itemId) => _plans
      .where(
        (plan) =>
            plan.containerItemId == itemId ||
            plan.items.any((planItem) => planItem.itemId == itemId),
      )
      .length;

  /// Plans that would be deleted along with this item, because it is what they
  /// are packed into.
  List<PlanRecord> plansBuiltOn(String itemId) =>
      _plans.where((plan) => plan.containerItemId == itemId).toList();

  /// Deleting an item removes it from every plan and loadout too — a dangling
  /// reference would be worse than losing the placement. Plans built *on* the
  /// item go with it, since a plan with no container is meaningless.
  Future<void> deleteItem(String itemId) async {
    _items.removeWhere((item) => item.id == itemId);
    _plans.removeWhere((plan) => plan.containerItemId == itemId);

    for (var i = 0; i < _plans.length; i++) {
      final record = _plans[i];
      final removed = record.items
          .where((planItem) => planItem.itemId == itemId)
          .map((planItem) => planItem.id)
          .toSet();
      if (removed.isEmpty) continue;

      _plans[i] = record.copyWith(
        items: record.items
            .where((planItem) => planItem.itemId != itemId)
            .toList(),
        placements: {...record.placements}
          ..removeWhere((entryId, _) => removed.contains(entryId)),
      );
    }

    for (var i = 0; i < _loadouts.length; i++) {
      final loadout = _loadouts[i];
      if (!loadout.itemIds.contains(itemId)) continue;
      _loadouts[i] = Loadout(
        id: loadout.id,
        name: loadout.name,
        itemIds: loadout.itemIds.where((id) => id != itemId).toList(),
      );
    }

    await _commit();
  }

  /// A JSON snapshot of the gear library alone — not plans or loadouts, just
  /// the reusable items — worth sharing or keeping around as a starting
  /// point for a new install rather than re-entering everything by hand.
  String exportLibraryJson() => const JsonEncoder.withIndent('  ').convert({
    'kind': 'packplan-library',
    'version': kLibraryExportVersion,
    'items': _items.map((item) => item.toJson()).toList(),
  });

  /// Brings in items from [json] — a file this app (or another install of
  /// it) produced with [exportLibraryJson]. Every item gets a fresh id
  /// regardless of what the file says, since two installs could easily have
  /// picked the same id for different things, and one already in the
  /// library by name is left alone rather than duplicated.
  ///
  /// Throws [FormatException] if [json] is not a library export.
  Future<ImportResult> importLibraryJson(String json) async {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic> || decoded['items'] is! List) {
      throw const FormatException('Not a PackPlan library file.');
    }

    final existingNames = _items
        .map((item) => item.name.trim().toLowerCase())
        .toSet();
    var added = 0;
    var skipped = 0;

    for (final raw in decoded['items'] as List) {
      final rawItem = raw as Map<String, dynamic>;
      final key = ((rawItem['name'] as String?) ?? '').trim().toLowerCase();
      if (!existingNames.add(key)) {
        skipped++;
        continue;
      }

      _items.add(
        GearItem.fromJson({
          ...rawItem,
          'id': _uuid.v4(),
          'colorValue': _nextColor(_items.map((item) => item.colorValue)),
        }),
      );
      added++;
    }

    if (added > 0) await _commit();
    return ImportResult(added: added, skipped: skipped);
  }

  // ---------------------------------------------------------------- loadouts

  Future<Loadout> addLoadout({
    required String name,
    List<String> itemIds = const [],
  }) async {
    final loadout = Loadout(id: _uuid.v4(), name: name, itemIds: [...itemIds]);
    _loadouts.add(loadout);
    await _commit();
    return loadout;
  }

  Future<void> updateLoadout(
    String loadoutId, {
    required String name,
    required List<String> itemIds,
  }) async {
    final index = _loadouts.indexWhere((loadout) => loadout.id == loadoutId);
    if (index < 0) return;
    _loadouts[index] = Loadout(
      id: loadoutId,
      name: name,
      itemIds: [...itemIds],
    );
    await _commit();
  }

  Future<void> deleteLoadout(String loadoutId) async {
    _loadouts.removeWhere((loadout) => loadout.id == loadoutId);
    await _commit();
  }

  /// Saves what a plan currently holds as a reusable loadout. The container is
  /// not included — a loadout is gear, and drops into any bag.
  Future<Loadout> savePlanAsLoadout(
    String planId, {
    required String name,
  }) async {
    final record = planRecordById(planId);
    return addLoadout(
      name: name,
      itemIds: record == null
          ? const []
          : record.items.map((planItem) => planItem.itemId).toList(),
    );
  }

  /// Adds every item in a loadout to a plan, placing each in free space so any
  /// arrangement already made by hand survives. Returns the items that found no
  /// room.
  Future<List<GearItem>> applyLoadout(String planId, String loadoutId) async {
    final loadout = loadoutById(loadoutId);
    if (loadout == null) return const [];

    final unfitted = <GearItem>[];
    for (final itemId in loadout.itemIds) {
      final placed = await addGear(planId, itemId);
      if (!placed) {
        final item = itemById(itemId);
        if (item != null) unfitted.add(item);
      }
    }
    return unfitted;
  }

  // ------------------------------------------------------------------- plans

  /// Creates a plan around a container item. Returns null if that item is not
  /// in the library.
  Future<PlanRecord?> addPlan({
    required String containerItemId,
    String? name,
    double? tolerance,
    double heightOverflow = 0,
  }) async {
    final container = itemById(containerItemId);
    if (container == null) return null;

    final record = PlanRecord(
      id: _uuid.v4(),
      name: name ?? container.name,
      containerItemId: containerItemId,
      tolerance: tolerance ?? _settings.defaultTolerance,
      heightOverflow: heightOverflow,
    );
    _plans.add(record);
    await _commit();
    return record;
  }

  Future<void> updatePlan(
    String planId, {
    required String name,
    String? containerItemId,
    required double tolerance,
    double heightOverflow = 0,
  }) async {
    final record = planRecordById(planId);
    if (record == null) return;

    final swapped =
        containerItemId != null && containerItemId != record.containerItemId;
    final reshaped = swapped || record.tolerance != tolerance;

    var updated = record.copyWith(
      name: name,
      containerItemId: containerItemId,
      tolerance: tolerance,
      // Not folded into [reshaped] - existing placements that no longer fit
      // a smaller overflow allowance get flagged by findPlacementIssues
      // instead of being silently thrown out, the same as any other
      // out-of-bounds drag. Only tolerance and the container itself force a
      // full re-layout.
      heightOverflow: heightOverflow,
    );

    // A different bag or a different gap invalidates every position, so lay it
    // out again rather than leaving gear hanging outside its container.
    if (reshaped) {
      final plan = _resolve(updated);
      if (plan != null) {
        updated = updated.copyWith(placements: packPlan(plan).placements);
      }
    }

    _replace(updated);
    await _commit();
  }

  /// Shows or hides one of the three orthographic views. The caller is
  /// responsible for not hiding the last visible one — this just flips the
  /// flag, since the store has no opinion about how many views a screen
  /// needs to keep on display.
  Future<void> toggleViewVisibility(String planId, String viewName) async {
    final record = planRecordById(planId);
    if (record == null) return;

    final hidden = {...record.hiddenViews};
    if (!hidden.remove(viewName)) hidden.add(viewName);

    _replace(record.copyWith(hiddenViews: hidden));
    await _commit();
  }

  Future<void> deletePlan(String planId) async {
    _plans.removeWhere((plan) => plan.id == planId);
    await _commit();
  }

  Future<PlanRecord?> duplicatePlan(String planId) async {
    final record = planRecordById(planId);
    if (record == null) return null;

    // Entries get fresh ids, and placements are re-keyed to match.
    final entryIds = <String, String>{};
    final items = record.items.map((planItem) {
      final id = _uuid.v4();
      entryIds[planItem.id] = id;
      return PlanItem(id: id, itemId: planItem.itemId);
    }).toList();

    final placements = <String, Placement>{};
    record.placements.forEach((oldId, placement) {
      final newId = entryIds[oldId];
      if (newId == null) return;
      placements[newId] = Placement(
        entryId: newId,
        x: placement.x,
        y: placement.y,
        z: placement.z,
        width: placement.width,
        height: placement.height,
        depth: placement.depth,
      );
    });

    final copy = PlanRecord(
      id: _uuid.v4(),
      name: '${record.name} copy',
      containerItemId: record.containerItemId,
      tolerance: record.tolerance,
      heightOverflow: record.heightOverflow,
      items: items,
      placements: placements,
      hiddenViews: {...record.hiddenViews},
    );

    _plans.add(copy);
    await _commit();
    return copy;
  }

  // --------------------------------------------------------- gear in a plan

  /// Puts a library item into a plan, placing it in free space. Returns false
  /// when it was added but found no room.
  Future<bool> addGear(String planId, String itemId) async {
    final record = planRecordById(planId);
    if (record == null || itemById(itemId) == null) return false;

    final planItem = PlanItem(id: _uuid.v4(), itemId: itemId);
    var updated = record.copyWith(items: [...record.items, planItem]);

    final plan = _resolve(updated);
    final entry = plan?.entryById(planItem.id);
    final spot = (plan == null || entry == null)
        ? null
        : findSpotFor(plan, entry);

    if (spot != null) {
      updated = updated.copyWith(
        placements: {...updated.placements, planItem.id: spot},
      );
    }

    _replace(updated);
    await _commit();
    return spot != null;
  }

  Future<void> removeEntry(String planId, String entryId) async {
    final record = planRecordById(planId);
    if (record == null) return;

    _replace(
      record.copyWith(
        items: record.items
            .where((planItem) => planItem.id != entryId)
            .toList(),
        placements: {...record.placements}..remove(entryId),
      ),
    );
    await _commit();
  }

  /// Lays the whole plan out from scratch, discarding manual positions.
  Future<PackResult> autoPack(String planId) async {
    final record = planRecordById(planId);
    final plan = record == null ? null : _resolve(record);
    if (record == null || plan == null) {
      return const PackResult(placements: {}, unfitted: []);
    }

    final result = packPlan(plan);
    _replace(record.copyWith(placements: result.placements));
    await _commit();
    return result;
  }

  /// Takes gear out of the diagram without removing it from the plan.
  Future<void> unplaceEntry(String planId, String entryId) async {
    final record = planRecordById(planId);
    if (record == null) return;

    _replace(
      record.copyWith(placements: {...record.placements}..remove(entryId)),
    );
    await _commit();
  }

  /// Puts an unplaced entry back on the diagram, if there is room.
  Future<bool> placeEntry(String planId, String entryId) async {
    final record = planRecordById(planId);
    final plan = record == null ? null : _resolve(record);
    if (record == null || plan == null) return false;

    final entry = plan.entryById(entryId);
    if (entry == null) return false;

    final spot = findSpotFor(plan, entry);
    if (spot == null) return false;

    _replace(
      record.copyWith(placements: {...record.placements, entryId: spot}),
    );
    await _commit();
    return true;
  }

  /// Moves placed gear by a plan-space delta, clamped to stay inside the usable
  /// space. Clashes are allowed — the diagram flags them, because refusing the
  /// drag outright makes rearranging by hand miserable.
  ///
  /// Does not save: a drag fires this every frame. Call [flush] when it ends.
  void moveGear(
    String planId,
    String entryId, {
    double dx = 0,
    double dy = 0,
    double dz = 0,
  }) {
    final record = planRecordById(planId);
    final plan = record == null ? null : _resolve(record);
    if (record == null || plan == null) return;

    final placement = record.placements[entryId];
    if (placement == null) return;

    final margin = wallMarginFor(record.tolerance);
    final depthMargin = plan.isThreeDimensional ? margin : 0.0;

    final moved = placement.copyWith(
      x: _clamp(
        placement.x + dx,
        margin,
        plan.container.width - margin - placement.width,
      ),
      y: _clamp(
        placement.y + dy,
        margin,
        plan.container.height +
            record.heightOverflow -
            margin -
            placement.height,
      ),
      z: _clamp(
        placement.z + dz,
        depthMargin,
        plan.workingDepth - depthMargin - placement.depth,
      ),
    );

    _replace(
      record.copyWith(placements: {...record.placements, entryId: moved}),
    );
    notifyListeners();
  }

  /// Turns placed gear to the next orientation it can be turned into —
  /// cycling through every permutation of its own three lengths (not just
  /// the two shown in whichever view the button was pressed from), skipping
  /// straight past any that do not fit the container.
  ///
  /// Manual, so it ignores the gear's "can be turned" setting — that governs
  /// what auto-pack is allowed to do on its own, and this is the user saying
  /// otherwise about one placement. Clashes are allowed here for the same
  /// reason dragging allows them; only refused when literally nothing in the
  /// cycle fits.
  Future<RotateOutcome> rotateGear(String planId, String entryId) async {
    final record = planRecordById(planId);
    final plan = record == null ? null : _resolve(record);
    if (record == null || plan == null) return RotateOutcome.notFound;

    final placement = record.placements[entryId];
    if (placement == null) return RotateOutcome.notFound;

    final entry = plan.entryById(entryId);
    if (entry == null) return RotateOutcome.notFound;

    final orientations = turnableOrientationsOf(entry.item, placement.depth);
    final currentIndex = orientations.indexWhere(
      (o) =>
          o.$1 == placement.width &&
          o.$2 == placement.height &&
          o.$3 == placement.depth,
    );
    // The placement should always be one of the item's own permutations, but
    // fall back to the start of the cycle rather than crashing if it is not.
    final startIndex = currentIndex < 0 ? 0 : currentIndex;

    final margin = wallMarginFor(record.tolerance);
    final depthMargin = plan.isThreeDimensional ? margin : 0.0;

    // Strictly less than length - stopping one short of wrapping all the way
    // back to startIndex, or a container with only one fitting orientation
    // would silently "rotate" into the exact same placement it started at.
    for (var step = 1; step < orientations.length; step++) {
      final (width, height, depth) =
          orientations[(startIndex + step) % orientations.length];

      // Height gets the same allowance moveGear does for an open-top
      // container - a turn that only pokes up through the missing lid is
      // not "no room", it is exactly what the overflow room is for.
      if (width > plan.container.width - margin * 2 ||
          height > plan.container.height + record.heightOverflow - margin * 2 ||
          depth > plan.workingDepth - depthMargin * 2) {
        continue;
      }

      final settled = Placement(
        entryId: entryId,
        width: width,
        height: height,
        depth: depth,
        x: _clamp(placement.x, margin, plan.container.width - margin - width),
        y: _clamp(
          placement.y,
          margin,
          plan.container.height + record.heightOverflow - margin - height,
        ),
        z: _clamp(
          placement.z,
          depthMargin,
          plan.workingDepth - depthMargin - depth,
        ),
      );

      _replace(
        record.copyWith(placements: {...record.placements, entryId: settled}),
      );
      await _commit();
      return RotateOutcome.rotated;
    }

    return RotateOutcome.wontFit;
  }

  double _clamp(double value, double min, double max) {
    // Snapping before clamping would let a snap push gear back out of bounds.
    final snapped = (value / kDragSnap).round() * kDragSnap;
    if (max <= min) return min;
    return snapped.clamp(min, max);
  }
}
