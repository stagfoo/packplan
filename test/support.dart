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
  bool isContainer = false,
}) => GearItem(
  id: id,
  name: id,
  width: width,
  height: height,
  depth: depth,
  colorValue: kGearPalette.first,
  rotatable: rotatable,
  tags: tags,
  isContainer: isContainer,
);

Plan planOf({
  required double width,
  required double height,
  double? depth,
  double tolerance = 0,
  List<GearItem> items = const [],
  Map<String, Placement> placements = const {},
}) {
  final container = gear(
    'container',
    width: width,
    height: height,
    depth: depth,
    isContainer: true,
  );

  final record = PlanRecord(
    id: 'p',
    name: 'plan',
    containerItemId: container.id,
    tolerance: tolerance,
    items: items
        .map((item) => PlanItem(id: item.id, itemId: item.id))
        .toList(),
    placements: placements,
  );

  return Plan(
    record: record,
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
  record: plan.record.copyWith(placements: placements),
  container: plan.container,
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

/// Rebuilds a plan with the given set of hidden views.
Plan withHiddenViews(Plan plan, Set<String> hiddenViews) => Plan(
  record: plan.record.copyWith(hiddenViews: hiddenViews),
  container: plan.container,
  entries: plan.entries,
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
