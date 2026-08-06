import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'packer.dart';
import 'repository.dart';
import 'units.dart';

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
  List<GearContainer> _containers = [];
  List<CustomUnit> _customUnits = [];
  bool _loaded = false;

  AppSettings get settings => _settings;
  List<GearItem> get items => List.unmodifiable(_items);
  List<Loadout> get loadouts => List.unmodifiable(_loadouts);
  List<GearContainer> get containers => List.unmodifiable(_containers);
  List<CustomUnit> get customUnits => List.unmodifiable(_customUnits);
  bool get isLoaded => _loaded;

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

  /// Every tag in use across the library, sorted.
  List<String> get allTags =>
      normaliseTags(_items.expand((item) => item.tags));

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

  GearContainer? containerById(String id) {
    for (final container in _containers) {
      if (container.id == id) return container;
    }
    return null;
  }

  /// Resolves a container's entries against the library. Entries whose item has
  /// been deleted are dropped, so a stale reference can never crash a screen.
  Plan? planFor(String containerId) {
    final container = containerById(containerId);
    if (container == null) return null;
    return _planOf(container);
  }

  Plan _planOf(GearContainer container) {
    final entries = <PlanEntry>[];
    for (final entry in container.entries) {
      final item = itemById(entry.itemId);
      if (item == null) continue;
      entries.add(
        PlanEntry(
          id: entry.id,
          item: item,
          placement: container.placements[entry.id],
        ),
      );
    }
    return Plan(container: container, entries: entries);
  }

  Future<void> load() async {
    final data = await _repository.load();
    _settings = data.settings;
    _items = [...data.items];
    _loadouts = [...data.loadouts];
    _containers = [...data.containers];
    _customUnits = [...data.customUnits];
    _loaded = true;
    notifyListeners();
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
      containers: _containers,
      customUnits: _customUnits,
    ),
  );

  void _replace(GearContainer container) {
    final index = _containers.indexWhere((c) => c.id == container.id);
    if (index >= 0) _containers[index] = container;
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

  /// [tolerance] is in centimetres. Only affects containers made from now on;
  /// existing ones keep whatever they were given.
  Future<void> setDefaultTolerance(double tolerance) async {
    _settings = _settings.copyWith(defaultTolerance: tolerance);
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
    );
    _items.add(item);
    await _commit();
    return item;
  }

  /// Updating an item's size invalidates its placement everywhere it is used,
  /// so each affected container finds it a fresh spot.
  Future<void> updateItem(
    String itemId, {
    required String name,
    required double width,
    required double height,
    double? depth,
    required bool rotatable,
    required List<String> tags,
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
    );

    if (resized) {
      for (final container in [..._containers]) {
        final affected = container.entries
            .where((entry) => entry.itemId == itemId)
            .map((entry) => entry.id)
            .toSet();
        if (affected.isEmpty) continue;
        _replace(_reseat(container, affected));
      }
    }

    await _commit();
  }

  /// Drops the given entries' placements and finds each a new spot among what
  /// is left.
  GearContainer _reseat(GearContainer container, Set<String> entryIds) {
    var placements = {...container.placements}
      ..removeWhere((entryId, _) => entryIds.contains(entryId));
    var working = container.copyWith(placements: placements);

    for (final entryId in entryIds) {
      final plan = _planOf(working);
      final entry = plan.entryById(entryId);
      if (entry == null) continue;
      final spot = findSpotFor(plan, entry);
      if (spot == null) continue;
      placements = {...placements, entryId: spot};
      working = working.copyWith(placements: placements);
    }

    return working;
  }

  /// Deleting an item removes it from every container and loadout too — a
  /// dangling reference would be worse than losing the placement.
  Future<void> deleteItem(String itemId) async {
    _items.removeWhere((item) => item.id == itemId);

    for (var i = 0; i < _containers.length; i++) {
      final container = _containers[i];
      final removed = container.entries
          .where((entry) => entry.itemId == itemId)
          .map((entry) => entry.id)
          .toSet();
      if (removed.isEmpty) continue;

      _containers[i] = container.copyWith(
        entries: container.entries
            .where((entry) => entry.itemId != itemId)
            .toList(),
        placements: {...container.placements}
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

  /// How many containers currently hold this item — worth showing before a
  /// delete removes it from all of them.
  int usageCount(String itemId) => _containers
      .where((c) => c.entries.any((entry) => entry.itemId == itemId))
      .length;

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
    _loadouts[index] = Loadout(id: loadoutId, name: name, itemIds: [...itemIds]);
    await _commit();
  }

  Future<void> deleteLoadout(String loadoutId) async {
    _loadouts.removeWhere((loadout) => loadout.id == loadoutId);
    await _commit();
  }

  /// Saves what a container currently holds as a reusable loadout.
  Future<Loadout> saveContainerAsLoadout(
    String containerId, {
    required String name,
  }) async {
    final container = containerById(containerId);
    return addLoadout(
      name: name,
      itemIds: container == null
          ? const []
          : container.entries.map((entry) => entry.itemId).toList(),
    );
  }

  /// Adds every item in a loadout to a container, placing each in free space so
  /// any arrangement already made by hand survives. Returns the items that
  /// found no room.
  Future<List<GearItem>> applyLoadout(
    String containerId,
    String loadoutId,
  ) async {
    final loadout = loadoutById(loadoutId);
    if (loadout == null) return const [];

    final unfitted = <GearItem>[];
    for (final itemId in loadout.itemIds) {
      final placed = await addGear(containerId, itemId);
      if (!placed) {
        final item = itemById(itemId);
        if (item != null) unfitted.add(item);
      }
    }
    return unfitted;
  }

  // -------------------------------------------------------------- containers

  Future<GearContainer> addContainer({
    required String name,
    required double width,
    required double height,
    double? depth,
    double? tolerance,
  }) async {
    final container = GearContainer(
      id: _uuid.v4(),
      name: name,
      width: width,
      height: height,
      depth: depth,
      colorValue: _nextColor(_containers.map((c) => c.colorValue)),
      tolerance: tolerance ?? _settings.defaultTolerance,
    );
    _containers.add(container);
    await _commit();
    return container;
  }

  Future<void> updateContainer(
    String containerId, {
    required String name,
    required double width,
    required double height,
    double? depth,
    required double tolerance,
  }) async {
    final container = containerById(containerId);
    if (container == null) return;

    final reshaped =
        container.width != width ||
        container.height != height ||
        container.depth != depth ||
        container.tolerance != tolerance;

    var updated = container.copyWith(
      name: name,
      width: width,
      height: height,
      depth: depth,
      clearDepth: depth == null,
      tolerance: tolerance,
    );

    // Changing the shape or the tolerance invalidates every position, so lay it
    // out again rather than leaving gear hanging outside its container.
    if (reshaped) {
      updated = updated.copyWith(
        placements: packPlan(_planOf(updated)).placements,
      );
    }

    _replace(updated);
    await _commit();
  }

  Future<void> deleteContainer(String containerId) async {
    _containers.removeWhere((c) => c.id == containerId);
    await _commit();
  }

  Future<GearContainer?> duplicateContainer(String containerId) async {
    final container = containerById(containerId);
    if (container == null) return null;

    // Entries get fresh ids, and placements are re-keyed to match.
    final entryIds = <String, String>{};
    final entries = container.entries.map((entry) {
      final id = _uuid.v4();
      entryIds[entry.id] = id;
      return ContainerEntry(id: id, itemId: entry.itemId);
    }).toList();

    final placements = <String, Placement>{};
    container.placements.forEach((oldId, placement) {
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

    final copy = GearContainer(
      id: _uuid.v4(),
      name: '${container.name} copy',
      width: container.width,
      height: container.height,
      depth: container.depth,
      colorValue: container.colorValue,
      tolerance: container.tolerance,
      entries: entries,
      placements: placements,
    );

    _containers.add(copy);
    await _commit();
    return copy;
  }

  // -------------------------------------------------------- gear in a container

  /// Puts a library item into a container, placing it in free space. Returns
  /// false when it was added but found no room.
  Future<bool> addGear(String containerId, String itemId) async {
    final container = containerById(containerId);
    if (container == null || itemById(itemId) == null) return false;

    final entry = ContainerEntry(id: _uuid.v4(), itemId: itemId);
    var updated = container.copyWith(entries: [...container.entries, entry]);

    final plan = _planOf(updated);
    final planEntry = plan.entryById(entry.id);
    final spot = planEntry == null ? null : findSpotFor(plan, planEntry);

    if (spot != null) {
      updated = updated.copyWith(
        placements: {...updated.placements, entry.id: spot},
      );
    }

    _replace(updated);
    await _commit();
    return spot != null;
  }

  Future<void> removeEntry(String containerId, String entryId) async {
    final container = containerById(containerId);
    if (container == null) return;

    _replace(
      container.copyWith(
        entries: container.entries
            .where((entry) => entry.id != entryId)
            .toList(),
        placements: {...container.placements}..remove(entryId),
      ),
    );
    await _commit();
  }

  /// Lays the whole container out from scratch, discarding manual positions.
  Future<PackResult> autoPack(String containerId) async {
    final container = containerById(containerId);
    if (container == null) {
      return const PackResult(placements: {}, unfitted: []);
    }

    final result = packPlan(_planOf(container));
    _replace(container.copyWith(placements: result.placements));
    await _commit();
    return result;
  }

  /// Takes gear out of the diagram without removing it from the container.
  Future<void> unplaceEntry(String containerId, String entryId) async {
    final container = containerById(containerId);
    if (container == null) return;

    _replace(
      container.copyWith(placements: {...container.placements}..remove(entryId)),
    );
    await _commit();
  }

  /// Puts an unplaced entry back on the diagram, if there is room.
  Future<bool> placeEntry(String containerId, String entryId) async {
    final container = containerById(containerId);
    if (container == null) return false;

    final plan = _planOf(container);
    final entry = plan.entryById(entryId);
    if (entry == null) return false;

    final spot = findSpotFor(plan, entry);
    if (spot == null) return false;

    _replace(
      container.copyWith(
        placements: {...container.placements, entryId: spot},
      ),
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
    String containerId,
    String entryId, {
    double dx = 0,
    double dy = 0,
    double dz = 0,
  }) {
    final container = containerById(containerId);
    if (container == null) return;

    final placement = container.placements[entryId];
    if (placement == null) return;

    final plan = _planOf(container);
    final tolerance = container.tolerance;
    final depthTolerance = plan.isThreeDimensional ? tolerance : 0.0;

    final moved = placement.copyWith(
      x: _clamp(
        placement.x + dx,
        tolerance,
        container.width - tolerance - placement.width,
      ),
      y: _clamp(
        placement.y + dy,
        tolerance,
        container.height - tolerance - placement.height,
      ),
      z: _clamp(
        placement.z + dz,
        depthTolerance,
        plan.workingDepth - depthTolerance - placement.depth,
      ),
    );

    _replace(
      container.copyWith(
        placements: {...container.placements, entryId: moved},
      ),
    );
    notifyListeners();
  }

  double _clamp(double value, double min, double max) {
    // Snapping before clamping would let a snap push gear back out of bounds.
    final snapped = (value / kDragSnap).round() * kDragSnap;
    if (max <= min) return min;
    return snapped.clamp(min, max);
  }
}
