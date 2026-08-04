import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'packer.dart';
import 'repository.dart';

/// Drag positions snap to this many centimetres. Gear measurements are not
/// precise enough to justify anything finer, and it keeps the numbers readable.
const double kDragSnap = 0.5;

/// Owns the plan list and every mutation to it. Saves after each change —
/// there is no explicit save button, and a packing plan you lose on a crash is
/// worse than useless.
class GearStore extends ChangeNotifier {
  GearStore({GearRepository? repository, Uuid? uuid})
    : _repository = repository ?? GearRepository(),
      _uuid = uuid ?? const Uuid();

  final GearRepository _repository;
  final Uuid _uuid;

  List<GearContainer> _containers = [];
  bool _loaded = false;

  List<GearContainer> get containers => List.unmodifiable(_containers);
  bool get isLoaded => _loaded;

  GearContainer? containerById(String id) {
    for (final container in _containers) {
      if (container.id == id) return container;
    }
    return null;
  }

  Future<void> load() async {
    _containers = await _repository.load();
    _loaded = true;
    notifyListeners();
  }

  Future<void> _commit() async {
    notifyListeners();
    await _repository.save(_containers);
  }

  int _replace(GearContainer container) {
    final index = _containers.indexWhere((c) => c.id == container.id);
    if (index >= 0) _containers[index] = container;
    return index;
  }

  /// Picks the palette colour least used so far, so a new item is easy to pick
  /// out from the ones already on the diagram.
  int _nextColor(Iterable<int> taken) {
    final counts = {for (final color in kGearPalette) color: 0};
    for (final color in taken) {
      if (counts.containsKey(color)) counts[color] = counts[color]! + 1;
    }
    return counts.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
  }

  Future<GearContainer> addContainer({
    required String name,
    required double width,
    required double height,
    double? depth,
  }) async {
    final container = GearContainer(
      id: _uuid.v4(),
      name: name,
      width: width,
      height: height,
      depth: depth,
      colorValue: _nextColor(_containers.map((c) => c.colorValue)),
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
  }) async {
    final container = containerById(containerId);
    if (container == null) return;

    final resized =
        container.width != width ||
        container.height != height ||
        container.depth != depth;

    var updated = container.copyWith(
      name: name,
      width: width,
      height: height,
      depth: depth,
      clearDepth: depth == null,
    );

    // Changing the shape invalidates every position, so lay it out again
    // rather than leaving goods hanging outside their container.
    if (resized) {
      updated = updated.copyWith(placements: packContainer(updated).placements);
    }

    _replace(updated);
    await _commit();
  }

  Future<void> deleteContainer(String containerId) async {
    _containers.removeWhere((c) => c.id == containerId);
    await _commit();
  }

  Future<void> addGood(
    String containerId, {
    required String name,
    required double width,
    required double height,
    double? depth,
    bool rotatable = true,
  }) async {
    final container = containerById(containerId);
    if (container == null) return;

    final good = Good(
      id: _uuid.v4(),
      name: name,
      width: width,
      height: height,
      depth: depth,
      colorValue: _nextColor(container.goods.map((g) => g.colorValue)),
      rotatable: rotatable,
    );

    // Slot the new good into whatever space is left instead of re-packing, so
    // any arrangement the user made by hand survives.
    final spot = findSpotFor(container, good);

    _replace(
      container.copyWith(
        goods: [...container.goods, good],
        placements: spot == null
            ? container.placements
            : {...container.placements, good.id: spot},
      ),
    );
    await _commit();
  }

  Future<void> updateGood(
    String containerId,
    String goodId, {
    required String name,
    required double width,
    required double height,
    double? depth,
    required bool rotatable,
  }) async {
    final container = containerById(containerId);
    if (container == null) return;

    final index = container.goods.indexWhere((g) => g.id == goodId);
    if (index < 0) return;

    final existing = container.goods[index];
    final updated = existing.copyWith(
      name: name,
      width: width,
      height: height,
      depth: depth,
      clearDepth: depth == null,
      rotatable: rotatable,
    );

    final goods = [...container.goods]..[index] = updated;
    final resized =
        existing.width != width ||
        existing.height != height ||
        existing.depth != depth;

    var placements = container.placements;
    if (resized) {
      // The old placement describes the old size, so drop it and find the
      // resized good a fresh spot among everything else.
      final without = {...placements}..remove(goodId);
      final spot = findSpotFor(
        container.copyWith(goods: goods, placements: without),
        updated,
      );
      placements = spot == null ? without : {...without, goodId: spot};
    }

    _replace(container.copyWith(goods: goods, placements: placements));
    await _commit();
  }

  Future<void> deleteGood(String containerId, String goodId) async {
    final container = containerById(containerId);
    if (container == null) return;

    _replace(
      container.copyWith(
        goods: container.goods.where((g) => g.id != goodId).toList(),
        placements: {...container.placements}..remove(goodId),
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

    final result = packContainer(container);
    _replace(container.copyWith(placements: result.placements));
    await _commit();
    return result;
  }

  /// Takes a good out of the diagram without deleting it.
  Future<void> unplaceGood(String containerId, String goodId) async {
    final container = containerById(containerId);
    if (container == null) return;

    _replace(
      container.copyWith(placements: {...container.placements}..remove(goodId)),
    );
    await _commit();
  }

  /// Puts an unplaced good back on the diagram, if there is room.
  /// Returns false when there is not.
  Future<bool> placeGood(String containerId, String goodId) async {
    final container = containerById(containerId);
    if (container == null) return false;

    final index = container.goods.indexWhere((g) => g.id == goodId);
    if (index < 0) return false;

    final spot = findSpotFor(container, container.goods[index]);
    if (spot == null) return false;

    _replace(
      container.copyWith(
        placements: {...container.placements, goodId: spot},
      ),
    );
    await _commit();
    return true;
  }

  /// Moves a placed good by a plan-space delta, clamped to stay inside the
  /// container. Overlaps are allowed — the diagram flags them, because
  /// refusing the drag outright makes rearranging by hand miserable.
  ///
  /// Does not save: a drag fires this every frame. Call [flush] when the drag
  /// ends.
  void moveGood(
    String containerId,
    String goodId, {
    double dx = 0,
    double dy = 0,
    double dz = 0,
  }) {
    final container = containerById(containerId);
    if (container == null) return;

    final placement = container.placements[goodId];
    if (placement == null) return;

    final containerDepth = container.isThreeDimensional
        ? container.depth!
        : 1.0;

    final moved = placement.copyWith(
      x: _clamp(placement.x + dx, container.width - placement.width),
      y: _clamp(placement.y + dy, container.height - placement.height),
      z: _clamp(placement.z + dz, containerDepth - placement.depth),
    );

    _replace(
      container.copyWith(
        placements: {...container.placements, goodId: moved},
      ),
    );

    notifyListeners();
  }

  /// Writes out changes made by [moveGood]. Called when a drag finishes.
  Future<void> flush() => _repository.save(_containers);

  double _clamp(double value, double max) {
    final snapped = (value / kDragSnap).round() * kDragSnap;
    if (max <= 0) return 0;
    return snapped.clamp(0.0, max);
  }
}
