import 'package:packplan/models.dart';

/// Builders that keep the tests readable. Entry ids mirror item ids so a test
/// can look a placement up by the name it used.
GearItem gear(
  String id, {
  required double width,
  required double height,
  double? depth,
  bool rotatable = true,
  List<String> tags = const [],
}) => GearItem(
  id: id,
  name: id,
  width: width,
  height: height,
  depth: depth,
  colorValue: kGearPalette.first,
  rotatable: rotatable,
  tags: tags,
);

Plan planOf({
  required double width,
  required double height,
  double? depth,
  double tolerance = 0,
  List<GearItem> items = const [],
  Map<String, Placement> placements = const {},
}) {
  final container = GearContainer(
    id: 'c',
    name: 'container',
    width: width,
    height: height,
    depth: depth,
    colorValue: kGearPalette.first,
    tolerance: tolerance,
    entries: items
        .map((item) => ContainerEntry(id: item.id, itemId: item.id))
        .toList(),
    placements: placements,
  );

  return Plan(
    container: container,
    entries: items
        .map(
          (item) => PlanEntry(
            id: item.id,
            item: item,
            placement: placements[item.id],
          ),
        )
        .toList(),
  );
}

/// Rebuilds a plan with the given placements attached.
Plan withPlacements(Plan plan, Map<String, Placement> placements) => Plan(
  container: plan.container.copyWith(placements: placements),
  entries: plan.entries
      .map(
        (entry) => PlanEntry(
          id: entry.id,
          item: entry.item,
          placement: placements[entry.id],
        ),
      )
      .toList(),
);

Placement placementAt({
  required String entryId,
  double x = 0,
  double y = 0,
  double z = 0,
  required double width,
  required double height,
  double depth = 1,
}) => Placement(
  entryId: entryId,
  x: x,
  y: y,
  z: z,
  width: width,
  height: height,
  depth: depth,
);
