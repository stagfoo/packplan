import 'models.dart';

/// Depth assumed for gear that has none, when it is packed into a container
/// that does have depth. Flat gear — a map, a sit pad, a document wallet — is
/// thin but not weightless, and a real number keeps the overlap maths honest.
const double kFlatGearDepth = 1.0;

const double _epsilon = 1e-9;

/// The outcome of an auto-pack: where everything went, and what was left over.
class PackResult {
  const PackResult({required this.placements, required this.unfitted});

  /// Placements by container entry id.
  final Map<String, Placement> placements;

  /// Entries that could not be placed, in the order they were attempted.
  final List<PlanEntry> unfitted;

  bool get everythingFits => unfitted.isEmpty;
}

/// One way a piece of gear may be turned. [index] is its position in the
/// candidate list, used only to break scoring ties in favour of leaving gear
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

/// The space gear may actually occupy once the container's tolerance is taken
/// off every wall.
class _Bounds {
  const _Bounds({
    required this.originX,
    required this.originY,
    required this.originZ,
    required this.limitX,
    required this.limitY,
    required this.limitZ,
  });

  final double originX;
  final double originY;
  final double originZ;
  final double limitX;
  final double limitY;
  final double limitZ;

  /// True when the tolerance has eaten the container entirely, so nothing can
  /// possibly fit.
  bool get isEmpty =>
      limitX <= originX || limitY <= originY || limitZ <= originZ;
}

/// How much a tolerance takes off a single wall.
///
/// Every piece of gear is treated as carrying a halo of half the tolerance on
/// each side. Two pieces therefore end up a full tolerance apart, while a
/// container loses one tolerance from each *dimension* rather than two — so a
/// 3 cm tolerance turns a 105 cm tub into 102 cm of usable depth, which is what
/// the number reads like.
double wallMarginFor(double tolerance) => tolerance / 2;

/// [includeHeightOverflow] raises the height limit by [Plan.heightOverflow],
/// for containers with no lid — an open-top wagon or crate. Only
/// [findPlacementIssues] passes true: auto-pack always targets the
/// container's real walls, so gear it places on its own never depends on a
/// human having dragged something up over the rim first.
_Bounds _boundsFor(Plan plan, {bool includeHeightOverflow = false}) {
  final margin = wallMarginFor(plan.tolerance);
  // A flat plan's depth axis is a fiction, so tolerance must not eat into it.
  final depthMargin = plan.isThreeDimensional ? margin : 0.0;
  final heightOverflow = includeHeightOverflow ? plan.heightOverflow : 0.0;

  return _Bounds(
    originX: margin,
    originY: margin,
    originZ: depthMargin,
    limitX: plan.container.width - margin,
    limitY: plan.container.height + heightOverflow - margin,
    limitZ: plan.workingDepth - depthMargin,
  );
}

/// Packs a plan's gear using an extreme-point, first-fit-decreasing heuristic.
///
/// Gear is tried largest first. For each piece, every free corner produced by
/// already-placed gear is considered in every allowed orientation, and the
/// position closest to the back-bottom-left of the container wins. This fills
/// the container in depth layers, which is what makes the front and side views
/// legible rather than a jumble.
///
/// The heuristic is not optimal — bin packing is NP-hard and an exact solver
/// would be overkill for a bag of camping gear. It is deterministic, so the
/// same plan always packs the same way.
PackResult packPlan(Plan plan) {
  final bounds = _boundsFor(plan);
  if (bounds.isEmpty) {
    return PackResult(placements: const {}, unfitted: [...plan.entries]);
  }

  final entries = [...plan.entries];
  entries.sort((a, b) {
    final aSize = _packingSize(a.item, plan.isThreeDimensional);
    final bSize = _packingSize(b.item, plan.isThreeDimensional);
    final bySize = bSize.compareTo(aSize);
    if (bySize != 0) return bySize;
    // Stable tie-break so a plan packs identically every time.
    return a.id.compareTo(b.id);
  });

  final placed = <Placement>[];
  final placements = <String, Placement>{};
  final unfitted = <PlanEntry>[];

  for (final entry in entries) {
    final placement = _bestPlacement(
      entryId: entry.id,
      item: entry.item,
      placed: placed,
      bounds: bounds,
      clearance: plan.tolerance,
      threeDimensional: plan.isThreeDimensional,
    );

    if (placement == null) {
      unfitted.add(entry);
      continue;
    }

    placed.add(placement);
    placements[entry.id] = placement;
  }

  return PackResult(placements: placements, unfitted: unfitted);
}

/// Finds room for one entry without moving anything already placed.
///
/// Used when gear is added to a container the user has already arranged by
/// hand — re-running the whole pack would throw those adjustments away.
/// Returns null when there is no free spot.
Placement? findSpotFor(Plan plan, PlanEntry entry) {
  final bounds = _boundsFor(plan);
  if (bounds.isEmpty) return null;

  return _bestPlacement(
    entryId: entry.id,
    item: entry.item,
    placed: plan.packed
        .where((other) => other.id != entry.id)
        .map((other) => other.placement!)
        .toList(),
    bounds: bounds,
    clearance: plan.tolerance,
    threeDimensional: plan.isThreeDimensional,
  );
}

/// The free corners worth trying: the usable origin, plus the three corners
/// each already-placed piece opens up once its clearance is allowed for.
Set<_Point> _candidatePoints(
  List<Placement> placed,
  _Bounds bounds,
  double clearance,
) => {
  _Point(bounds.originX, bounds.originY, bounds.originZ),
  for (final placement in placed) ...[
    _Point(placement.right + clearance, placement.y, placement.z),
    _Point(placement.x, placement.bottom + clearance, placement.z),
    _Point(placement.x, placement.y, placement.back + clearance),
  ],
};

Placement? _bestPlacement({
  required String entryId,
  required GearItem item,
  required List<Placement> placed,
  required _Bounds bounds,
  required double clearance,
  required bool threeDimensional,
}) {
  final orientations = _orientationsFor(item, threeDimensional);

  _Point? bestPoint;
  _Orientation? bestOrientation;

  for (final point in _candidatePoints(placed, bounds, clearance)) {
    if (point.x < bounds.originX - _epsilon) continue;
    if (point.y < bounds.originY - _epsilon) continue;
    if (point.z < bounds.originZ - _epsilon) continue;

    for (final orientation in orientations) {
      if (point.x + orientation.width > bounds.limitX + _epsilon) continue;
      if (point.y + orientation.height > bounds.limitY + _epsilon) continue;
      if (point.z + orientation.depth > bounds.limitZ + _epsilon) continue;

      final candidate = Placement(
        entryId: entryId,
        x: point.x,
        y: point.y,
        z: point.z,
        width: orientation.width,
        height: orientation.height,
        depth: orientation.depth,
      );
      if (placed.any(
        (other) => candidate.overlaps(other, clearance: clearance),
      )) {
        continue;
      }

      if (bestPoint == null ||
          _isBetter(point, orientation, bestPoint, bestOrientation!)) {
        bestPoint = point;
        bestOrientation = orientation;
      }
    }
  }

  if (bestPoint == null) return null;

  return Placement(
    entryId: entryId,
    x: bestPoint.x,
    y: bestPoint.y,
    z: bestPoint.z,
    width: bestOrientation!.width,
    height: bestOrientation.height,
    depth: bestOrientation.depth,
  );
}

double _packingSize(GearItem item, bool threeDimensional) {
  if (!threeDimensional) return item.area;
  return item.width * item.height * (item.depth ?? kFlatGearDepth);
}

/// Prefers the position nearest the back-bottom-left corner, then the gear's
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

List<_Orientation> _orientationsFor(GearItem item, bool threeDimensional) {
  final depth = threeDimensional ? (item.depth ?? kFlatGearDepth) : 1.0;

  if (item.width <= 0 || item.height <= 0 || depth <= 0) return const [];

  if (!item.rotatable) {
    return [_Orientation(item.width, item.height, depth, 0)];
  }

  final orientations = <_Orientation>[
    _Orientation(item.width, item.height, depth, 0),
    _Orientation(item.height, item.width, depth, 1),
  ];

  // Gear whose depth we invented should not be stood on its edge — that would
  // turn a 1 cm assumption into a 1 cm-wide item. Only turn it in the plane
  // the user actually gave us.
  if (threeDimensional && item.hasDepth) {
    orientations.addAll([
      _Orientation(item.width, depth, item.height, 2),
      _Orientation(depth, item.width, item.height, 3),
      _Orientation(item.height, depth, item.width, 4),
      _Orientation(depth, item.height, item.width, 5),
    ]);
  }

  return orientations;
}

/// A placement problem worth showing the user. Manual drags are never blocked,
/// so the diagram has to be able to say what is wrong instead.
enum PlacementIssue {
  /// Closer to another piece of gear than the tolerance allows — which with a
  /// tolerance of zero means genuinely overlapping.
  overlapping,

  /// Outside the container, or inside the margin the tolerance reserves.
  outOfBounds,
}

/// Finds placements that clash with another piece or break out of the usable
/// space. Only meaningful after a drag or a settings change — [packPlan] never
/// produces either.
Map<String, Set<PlacementIssue>> findPlacementIssues(Plan plan) {
  final bounds = _boundsFor(plan, includeHeightOverflow: true);
  final clearance = plan.tolerance;
  final issues = <String, Set<PlacementIssue>>{};
  final placements = plan.packed.map((entry) => entry.placement!).toList();

  void flag(String entryId, PlacementIssue issue) =>
      issues.putIfAbsent(entryId, () => <PlacementIssue>{}).add(issue);

  for (var i = 0; i < placements.length; i++) {
    final placement = placements[i];

    if (placement.x < bounds.originX - _epsilon ||
        placement.y < bounds.originY - _epsilon ||
        placement.z < bounds.originZ - _epsilon ||
        placement.right > bounds.limitX + _epsilon ||
        placement.bottom > bounds.limitY + _epsilon ||
        placement.back > bounds.limitZ + _epsilon) {
      flag(placement.entryId, PlacementIssue.outOfBounds);
    }

    for (var j = i + 1; j < placements.length; j++) {
      if (placement.overlaps(placements[j], clearance: clearance)) {
        flag(placement.entryId, PlacementIssue.overlapping);
        flag(placements[j].entryId, PlacementIssue.overlapping);
      }
    }
  }

  return issues;
}

/// True when the container's tolerance leaves no room for anything at all —
/// worth telling the user rather than silently failing to pack.
bool toleranceLeavesNoSpace(Plan plan) => _boundsFor(plan).isEmpty;
