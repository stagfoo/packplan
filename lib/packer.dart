import 'models.dart';

/// Depth assumed for a good that has none, when it is packed into a container
/// that does have depth. Flat gear — a map, a sit pad, a document wallet — is
/// thin but not weightless, and a real number keeps the overlap maths honest.
const double kFlatGoodDepth = 1.0;

/// The outcome of an auto-pack: where everything went, and what was left over.
class PackResult {
  const PackResult({required this.placements, required this.unfitted});

  final Map<String, Placement> placements;

  /// Goods that could not be placed, in the order they were attempted.
  final List<Good> unfitted;

  bool get everythingFits => unfitted.isEmpty;
}

/// One way a good may be turned. [index] is the orientation's position in the
/// candidate list, used only to break scoring ties in favour of leaving a good
/// the way the user entered it.
class _Orientation {
  const _Orientation(this.width, this.height, this.depth, this.index);

  final double width;
  final double height;
  final double depth;
  final int index;
}

class _Point {
  const _Point(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  @override
  bool operator ==(Object other) =>
      other is _Point && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);
}

/// Packs [container]'s goods using an extreme-point, first-fit-decreasing
/// heuristic.
///
/// Goods are tried largest first. For each one, every free corner produced by
/// an already-placed good is considered in every allowed orientation, and the
/// position closest to the back-bottom-left of the container wins. This fills
/// the container in depth layers, which is what makes the front and side views
/// legible rather than a jumble.
///
/// The heuristic is not optimal — bin packing is NP-hard and an exact solver
/// would be overkill for a bag of camping gear. It is deterministic, so the
/// same plan always packs the same way.
PackResult packContainer(GearContainer container) {
  final threeDimensional = container.isThreeDimensional;
  final containerDepth = threeDimensional ? container.depth! : 1.0;

  final goods = [...container.goods];
  goods.sort((a, b) {
    final aSize = _packingSize(a, threeDimensional);
    final bSize = _packingSize(b, threeDimensional);
    final bySize = bSize.compareTo(aSize);
    if (bySize != 0) return bySize;
    // Stable tie-break so a plan packs identically every time.
    return a.id.compareTo(b.id);
  });

  final placed = <Placement>[];
  final placements = <String, Placement>{};
  final unfitted = <Good>[];

  for (final good in goods) {
    final placement = _bestPlacement(
      good: good,
      placed: placed,
      containerWidth: container.width,
      containerHeight: container.height,
      containerDepth: containerDepth,
      threeDimensional: threeDimensional,
    );

    if (placement == null) {
      unfitted.add(good);
      continue;
    }

    placed.add(placement);
    placements[good.id] = placement;
  }

  return PackResult(placements: placements, unfitted: unfitted);
}

/// Finds room for a single [good] without moving anything already placed.
///
/// Used when a good is added to a container that the user has already arranged
/// by hand — re-running the whole pack would throw those adjustments away.
/// Returns null when there is no free spot.
Placement? findSpotFor(GearContainer container, Good good) {
  final threeDimensional = container.isThreeDimensional;
  return _bestPlacement(
    good: good,
    placed: container.placements.values.toList(),
    containerWidth: container.width,
    containerHeight: container.height,
    containerDepth: threeDimensional ? container.depth! : 1.0,
    threeDimensional: threeDimensional,
  );
}

/// The free corners worth trying: the container's own origin, plus the three
/// corners each already-placed good opens up.
Set<_Point> _candidatePoints(List<Placement> placed) => {
  const _Point(0, 0, 0),
  for (final placement in placed) ...[
    _Point(placement.right, placement.y, placement.z),
    _Point(placement.x, placement.bottom, placement.z),
    _Point(placement.x, placement.y, placement.back),
  ],
};

Placement? _bestPlacement({
  required Good good,
  required List<Placement> placed,
  required double containerWidth,
  required double containerHeight,
  required double containerDepth,
  required bool threeDimensional,
}) {
  final orientations = _orientationsFor(good, threeDimensional);

  _Point? bestPoint;
  _Orientation? bestOrientation;

  for (final point in _candidatePoints(placed)) {
    for (final orientation in orientations) {
      if (point.x + orientation.width > containerWidth + _epsilon) continue;
      if (point.y + orientation.height > containerHeight + _epsilon) continue;
      if (point.z + orientation.depth > containerDepth + _epsilon) continue;

      final candidate = Placement(
        goodId: good.id,
        x: point.x,
        y: point.y,
        z: point.z,
        width: orientation.width,
        height: orientation.height,
        depth: orientation.depth,
      );
      if (placed.any(candidate.overlaps)) continue;

      if (bestPoint == null ||
          _isBetter(point, orientation, bestPoint, bestOrientation!)) {
        bestPoint = point;
        bestOrientation = orientation;
      }
    }
  }

  if (bestPoint == null) return null;

  return Placement(
    goodId: good.id,
    x: bestPoint.x,
    y: bestPoint.y,
    z: bestPoint.z,
    width: bestOrientation!.width,
    height: bestOrientation.height,
    depth: bestOrientation.depth,
  );
}

const double _epsilon = 1e-9;

double _packingSize(Good good, bool threeDimensional) {
  if (!threeDimensional) return good.width * good.height;
  return good.width * good.height * (good.depth ?? kFlatGoodDepth);
}

/// Prefers the position nearest the back-bottom-left corner, then the good's
/// original orientation.
bool _isBetter(
  _Point point,
  _Orientation orientation,
  _Point bestPoint,
  _Orientation bestOrientation,
) {
  if (point.z != bestPoint.z) return point.z < bestPoint.z;
  if (point.y != bestPoint.y) return point.y < bestPoint.y;
  if (point.x != bestPoint.x) return point.x < bestPoint.x;
  return orientation.index < bestOrientation.index;
}

List<_Orientation> _orientationsFor(Good good, bool threeDimensional) {
  final depth = threeDimensional
      ? (good.depth ?? kFlatGoodDepth)
      : 1.0;

  if (good.width <= 0 || good.height <= 0 || depth <= 0) {
    return const [];
  }

  // A good whose depth we invented should not be stood on its edge — that
  // would turn a 1 cm assumption into a 1 cm-wide item. Only turn it in the
  // plane the user actually gave us.
  final turnInDepth = threeDimensional && good.hasDepth;

  if (!good.rotatable) {
    return [_Orientation(good.width, good.height, depth, 0)];
  }

  final orientations = <_Orientation>[
    _Orientation(good.width, good.height, depth, 0),
    _Orientation(good.height, good.width, depth, 1),
  ];

  if (turnInDepth) {
    orientations.addAll([
      _Orientation(good.width, depth, good.height, 2),
      _Orientation(depth, good.width, good.height, 3),
      _Orientation(good.height, depth, good.width, 4),
      _Orientation(depth, good.height, good.width, 5),
    ]);
  }

  return orientations;
}

/// A placement problem worth showing the user. Manual drags are never blocked,
/// so the diagram has to be able to say what is wrong instead.
enum PlacementIssue { overlapping, outOfBounds }

/// Finds placements that overlap another good or poke outside the container.
/// Only meaningful after a drag — [packContainer] never produces either.
Map<String, Set<PlacementIssue>> findPlacementIssues(GearContainer container) {
  final containerDepth = container.isThreeDimensional ? container.depth! : 1.0;
  final issues = <String, Set<PlacementIssue>>{};
  final placements = container.placements.values.toList();

  void flag(String goodId, PlacementIssue issue) =>
      issues.putIfAbsent(goodId, () => <PlacementIssue>{}).add(issue);

  for (var i = 0; i < placements.length; i++) {
    final placement = placements[i];

    if (placement.x < -_epsilon ||
        placement.y < -_epsilon ||
        placement.z < -_epsilon ||
        placement.right > container.width + _epsilon ||
        placement.bottom > container.height + _epsilon ||
        placement.back > containerDepth + _epsilon) {
      flag(placement.goodId, PlacementIssue.outOfBounds);
    }

    for (var j = i + 1; j < placements.length; j++) {
      if (placement.overlaps(placements[j])) {
        flag(placement.goodId, PlacementIssue.overlapping);
        flag(placements[j].goodId, PlacementIssue.overlapping);
      }
    }
  }

  return issues;
}
