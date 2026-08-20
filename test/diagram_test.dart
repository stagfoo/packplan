import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:packplan/diagram.dart';
import 'package:packplan/models.dart';
import 'package:packplan/packer.dart';
import 'package:packplan/plan_detail_screen.dart';
import 'package:packplan/units.dart';

import 'support.dart';

Plan samplePlan({double? depth}) => planOf(
  width: 30,
  height: 40,
  depth: depth,
  items: [
    gear('a', width: 10, height: 10, depth: depth == null ? null : 10),
    gear('b', width: 10, height: 10, depth: depth == null ? null : 10),
  ],
);

Plan packedSample({double? depth}) {
  final plan = samplePlan(depth: depth);
  return withPlacements(plan, packPlan(plan).placements);
}

ContainerViewPainter painterFor(Plan plan, ViewAxis axis) =>
    ContainerViewPainter(
      plan: plan,
      axis: axis,
      issues: const {},
      selectedEntryId: null,
      textDirection: TextDirection.ltr,
      outlineColor: const Color(0xFF000000),
      labelColor: const Color(0xFF000000),
      emptyColor: const Color(0xFFEEEEEE),
      toleranceColor: const Color(0xFFCCCCCC),
      hiddenConflictColor: const Color(0xFFF59E0B),
    );

void main() {
  group('ViewGeometry', () {
    const geometry = ViewGeometry(
      planWidth: 10,
      planHeight: 20,
      size: Size(120, 220),
      padding: 10,
    );

    test('scales to fit the smaller axis', () {
      expect(geometry.scale, 10);
    });

    test('centres the container in the available space', () {
      expect(geometry.boardSize, const Size(100, 200));
      expect(geometry.origin, const Offset(10, 10));
    });

    test('puts plan y zero at the bottom of the board', () {
      final rect = geometry.toCanvas(0, 0, 10, 5);

      expect(rect.bottom, geometry.boardRect.bottom);
      expect(rect.left, geometry.boardRect.left);
      expect(rect.height, 50);
    });

    test('places raised gear above the floor', () {
      final floor = geometry.toCanvas(0, 0, 10, 5);
      final raised = geometry.toCanvas(0, 5, 10, 5);

      expect(raised.bottom, floor.top);
    });

    test('treats dragging up as increasing plan y', () {
      expect(geometry.deltaToPlan(const Offset(20, -30)), const Offset(2, 3));
    });

    test('never divides by zero on a degenerate container', () {
      const degenerate = ViewGeometry(
        planWidth: 0,
        planHeight: 0,
        size: Size(100, 100),
      );

      expect(degenerate.scale, 1);
    });
  });

  group('view axes', () {
    test('each view shows a different pair of plan axes', () {
      expect(axesFor(ViewAxis.front), (
        horizontal: PlanAxis.width,
        vertical: PlanAxis.height,
      ));
      expect(axesFor(ViewAxis.top), (
        horizontal: PlanAxis.width,
        vertical: PlanAxis.depth,
      ));
      expect(axesFor(ViewAxis.side), (
        horizontal: PlanAxis.depth,
        vertical: PlanAxis.height,
      ));
    });

    test('swapping transposes a view', () {
      // A tall, narrow side view laid flat.
      expect(axesFor(ViewAxis.side, swapped: true), (
        horizontal: PlanAxis.height,
        vertical: PlanAxis.depth,
      ));
      expect(axesFor(ViewAxis.top, swapped: true), (
        horizontal: PlanAxis.depth,
        vertical: PlanAxis.width,
      ));
    });

    test('top and side together still cover all three axes', () {
      final shown = <PlanAxis>{
        ...[axesFor(ViewAxis.top), axesFor(ViewAxis.side)].expand(
          (axes) => [axes.horizontal, axes.vertical],
        ),
      };

      // Otherwise some dimension would be impossible to drag.
      expect(shown, PlanAxis.values.toSet());
    });

    test('the third axis is the one running into the screen', () {
      expect(axisIntoScreen(PlanAxis.width, PlanAxis.height), PlanAxis.depth);
      expect(axisIntoScreen(PlanAxis.width, PlanAxis.depth), PlanAxis.height);
      expect(axisIntoScreen(PlanAxis.depth, PlanAxis.height), PlanAxis.width);
    });

    test('a view names the turn its two axes describe', () {
      expect(
        rotationPlaneFor(PlanAxis.width, PlanAxis.height),
        RotationPlane.widthHeight,
      );
      expect(
        rotationPlaneFor(PlanAxis.depth, PlanAxis.height),
        RotationPlane.depthHeight,
      );
      expect(
        rotationPlaneFor(PlanAxis.width, PlanAxis.depth),
        RotationPlane.widthDepth,
      );
      // A swapped view describes the same turn.
      expect(
        rotationPlaneFor(PlanAxis.height, PlanAxis.depth),
        RotationPlane.depthHeight,
      );
    });

    test('container extents read off the right axis', () {
      final plan = samplePlan(depth: 20);

      expect(containerExtent(plan, PlanAxis.width), 30);
      expect(containerExtent(plan, PlanAxis.height), 40);
      expect(containerExtent(plan, PlanAxis.depth), 20);
    });

    test('a flat plan has a nominal depth extent', () {
      expect(containerExtent(samplePlan(), PlanAxis.depth), 1);
    });

    test('a placement spans the axis asked for', () {
      final placement = placementAt(
        entryId: 'a',
        x: 3,
        y: 4,
        z: 7,
        width: 10,
        height: 5,
        depth: 2,
      );

      expect(placementSpan(placement, PlanAxis.width), (
        offset: 3.0,
        size: 10.0,
      ));
      expect(placementSpan(placement, PlanAxis.height), (
        offset: 4.0,
        size: 5.0,
      ));
      expect(placementSpan(placement, PlanAxis.depth), (
        offset: 7.0,
        size: 2.0,
      ));
    });
  });

  group('hiddenAxisConflicts', () {
    // Same width and depth span, stacked apart in height only - not a real
    // 3D collision (height doesn't overlap), but Top view (width × depth)
    // can't tell them apart, while Side view (depth × height) correctly
    // shows them separated. This is exactly the "looks right in one view,
    // wrong in the other" report: no view but this one can move either
    // piece far enough apart in width or depth to actually fix it.
    final stackedInHeight = [
      placementAt(entryId: 'a', x: 0, y: 0, z: 0, width: 10, height: 10, depth: 10),
      placementAt(entryId: 'b', x: 0, y: 15, z: 0, width: 10, height: 10, depth: 10),
    ];

    test('flags a pair sharing this view\'s axes even without a real 3D overlap', () {
      final conflicts = hiddenAxisConflicts(
        stackedInHeight,
        PlanAxis.width,
        PlanAxis.depth,
        const {},
      );
      expect(conflicts, {'a', 'b'});
    });

    test('does not flag the view whose axes actually show them apart', () {
      final conflicts = hiddenAxisConflicts(
        stackedInHeight,
        PlanAxis.depth,
        PlanAxis.height,
        const {},
      );
      expect(conflicts, isEmpty);
    });

    test('does not flag pieces that are actually separated on this view\'s own axes', () {
      final apart = [
        placementAt(entryId: 'a', x: 0, y: 0, z: 0, width: 10, height: 10, depth: 10),
        placementAt(entryId: 'b', x: 20, y: 0, z: 0, width: 10, height: 10, depth: 10),
      ];
      expect(
        hiddenAxisConflicts(apart, PlanAxis.width, PlanAxis.depth, const {}),
        isEmpty,
      );
    });

    test('defers to a real overlap instead of double-flagging it', () {
      final trulyOverlapping = [
        placementAt(entryId: 'a', x: 0, y: 0, z: 0, width: 10, height: 10, depth: 10),
        placementAt(entryId: 'b', x: 5, y: 5, z: 5, width: 10, height: 10, depth: 10),
      ];
      final issues = {
        'a': {PlacementIssue.overlapping},
        'b': {PlacementIssue.overlapping},
      };
      expect(
        hiddenAxisConflicts(trulyOverlapping, PlanAxis.width, PlanAxis.depth, issues),
        isEmpty,
      );
    });
  });

  group('vertical flipping', () {
    test('height reads up from the floor', () {
      const geometry = ViewGeometry(
        planWidth: 10,
        planHeight: 20,
        size: Size(100, 200),
        padding: 0,
      );

      // Gear on the floor touches the bottom of the board.
      expect(geometry.toCanvas(0, 0, 10, 5).bottom, geometry.boardRect.bottom);
    });

    test('depth reads down from the top, the way you look into a bag', () {
      const geometry = ViewGeometry(
        planWidth: 10,
        planHeight: 20,
        size: Size(100, 200),
        padding: 0,
        flipVertical: false,
      );

      // The back of the container is at the top of the board.
      expect(geometry.toCanvas(0, 0, 10, 5).top, geometry.boardRect.top);
    });

    test('a drag down means more depth in an unflipped view', () {
      const geometry = ViewGeometry(
        planWidth: 10,
        planHeight: 20,
        size: Size(100, 200),
        padding: 0,
        flipVertical: false,
      );

      expect(geometry.deltaToPlan(const Offset(0, 10)).dy, greaterThan(0));
    });
  });

  group('hit testing', () {
    test('finds the gear under the pointer', () {
      final plan = packedSample();
      const size = Size(300, 400);
      final painter = painterFor(plan, ViewAxis.front);

      final placement = plan.entryById('a')!.placement!;
      final rect = painter
          .geometryFor(size)
          .toCanvas(
            placement.x,
            placement.y,
            placement.width,
            placement.height,
          );

      expect(painter.entryAt(rect.center, size), 'a');
    });

    test('returns null over empty container space', () {
      final plan = packedSample();
      const size = Size(300, 400);
      final painter = painterFor(plan, ViewAxis.front);

      // Gear packs into the bottom-left, so the top-right corner is bare.
      final board = painter.geometryFor(size).boardRect;
      expect(
        painter.entryAt(Offset(board.right - 5, board.top + 5), size),
        isNull,
      );
    });

    test('returns null outside the container entirely', () {
      final painter = painterFor(packedSample(), ViewAxis.front);

      expect(painter.entryAt(Offset.zero, const Size(300, 400)), isNull);
    });

    test('picks the nearer gear when two overlap in projection', () {
      // Both sit at the same x/y but different depths, so the front view shows
      // them stacked. The nearer one — smaller z — must win.
      final plan = withPlacements(samplePlan(depth: 30), {
        'a': placementAt(entryId: 'a', z: 20, width: 10, height: 10, depth: 10),
        'b': placementAt(entryId: 'b', z: 0, width: 10, height: 10, depth: 10),
      });
      const size = Size(300, 400);
      final painter = painterFor(plan, ViewAxis.front);
      final rect = painter.geometryFor(size).toCanvas(0, 0, 10, 10);

      expect(painter.entryAt(rect.center, size), 'b');
    });
  });

  group('ContainerView interaction', () {
    Future<void> pumpView(
      WidgetTester tester, {
      required Plan plan,
      required ViewAxis axis,
      required void Function(String, Offset) onDragged,
      ValueChanged<String?>? onSelected,
      VoidCallback? onDragEnded,
      ValueChanged<String>? onRotate,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: UnitScope(
            unit: MeasurementUnit.centimetres,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  height: 400,
                  child: ContainerView(
                    plan: plan,
                    axis: axis,
                    issues: const {},
                    selectedEntryId: null,
                    onSelected: onSelected ?? (_) {},
                    onDragged: onDragged,
                    onDragEnded: onDragEnded ?? () {},
                    onRotate: onRotate ?? (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('tapping gear selects it', (tester) async {
      String? selected;

      await pumpView(
        tester,
        plan: packedSample(),
        axis: ViewAxis.front,
        onDragged: (_, _) {},
        onSelected: (entryId) => selected = entryId,
      );

      final view = tester.getRect(find.byType(CustomPaint).last);
      await tester.tapAt(Offset(view.left + 30, view.bottom - 30));
      await tester.pump();

      expect(selected, isNotNull);
    });

    testWidgets('dragging reports a plan-space delta', (tester) async {
      final deltas = <Offset>[];
      var ended = 0;

      await pumpView(
        tester,
        plan: packedSample(),
        axis: ViewAxis.front,
        onDragged: (_, delta) => deltas.add(delta),
        onDragEnded: () => ended++,
      );

      final view = tester.getRect(find.byType(CustomPaint).last);
      await tester.dragFrom(
        Offset(view.left + 30, view.bottom - 30),
        const Offset(40, -40),
      );
      await tester.pump();

      expect(deltas, isNotEmpty);
      final total = deltas.reduce((a, b) => a + b);
      // Dragging right and up must increase both plan x and plan y.
      expect(total.dx, greaterThan(0));
      expect(total.dy, greaterThan(0));
      expect(ended, 1);
    });

    testWidgets('dragging empty space reports nothing', (tester) async {
      final deltas = <Offset>[];
      var ended = 0;

      await pumpView(
        tester,
        plan: packedSample(),
        axis: ViewAxis.front,
        onDragged: (_, delta) => deltas.add(delta),
        onDragEnded: () => ended++,
      );

      final view = tester.getRect(find.byType(CustomPaint).last);
      await tester.dragFrom(
        Offset(view.right - 20, view.top + 20),
        const Offset(-30, 30),
      );
      await tester.pump();

      expect(deltas, isEmpty);
      expect(ended, 0);
    });

    testWidgets('the axis label reports dimensions in the chosen unit', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: UnitScope(
            unit: MeasurementUnit.millimetres,
            child: Scaffold(
              body: SizedBox(
                width: 300,
                height: 400,
                child: ContainerView(
                  plan: packedSample(),
                  axis: ViewAxis.front,
                  issues: const {},
                  selectedEntryId: null,
                  onSelected: (_) {},
                  onDragged: (_, _) {},
                  onDragEnded: () {},
                  onRotate: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        find.textContaining('Front · 300 × 400 mm'),
        findsOneWidget,
      );
    });
  });

  group('UnitScope', () {
    testWidgets('defaults to centimetres when absent', (tester) async {
      late MeasurementUnit seen;

      await tester.pumpWidget(
        Builder(
          builder: (context) {
            seen = UnitScope.of(context);
            return const SizedBox();
          },
        ),
      );

      expect(seen, MeasurementUnit.centimetres);
    });
  });

  group('shared scale across the two views', () {
    // The reported case: a 300 x 300 x 105 tub, whose side view used to be
    // drawn almost twice the size of its own front view.
    Plan tub() => planOf(
      width: 300,
      height: 300,
      depth: 105,
      items: [gear('box', width: 200, height: 100, depth: 100)],
    );

    test('every view is drawn at the same scale', () {
      final plan = tub();
      final scale = sharedScaleFor(
        plan,
        viewsFor(plan),
        availableWidth: 660,
        availableHeight: 400,
      );

      final boards = [
        for (final entry in viewsFor(plan))
          ViewGeometry(
            planWidth: containerExtent(
              plan,
              axesFor(entry.view, swapped: entry.swapped).horizontal,
            ),
            planHeight: containerExtent(
              plan,
              axesFor(entry.view, swapped: entry.swapped).vertical,
            ),
            size: const Size(100, 100),
            fixedScale: scale,
          ),
      ];

      expect(boards.map((b) => b.scale).toSet(), {scale});
      // The top view's width and the front-facing width are the same measure,
      // so they must draw the same size.
      expect(
        boards.first.boardSize.width,
        closeTo(plan.container.width * scale, 1e-9),
      );
    });

    test('depth reads truthfully against width', () {
      final plan = tub();
      final scale = sharedScaleFor(
        plan,
        viewsFor(plan),
        availableWidth: 660,
        availableHeight: 400,
      );

      // The top view is 300 across and 105 down: depth against width.
      expect(
        (plan.workingDepth * scale) / (plan.container.width * scale),
        closeTo(105 / 300, 1e-9),
      );
    });

    test('the stack fits the width it is given', () {
      final plan = tub();
      const available = 660.0;
      final scale = sharedScaleFor(
        plan,
        viewsFor(plan),
        availableWidth: available,
        availableHeight: 400,
      );

      for (final entry in viewsFor(plan)) {
        final axes = axesFor(entry.view, swapped: entry.swapped);
        final used =
            containerExtent(plan, axes.horizontal) * scale + kViewPadding * 2;
        expect(used, lessThanOrEqualTo(available + 1e-9));
      }
    });

    test('the stack fits the height it is given', () {
      final plan = tub();
      const available = 500.0;
      final views = viewsFor(plan);
      final scale = sharedScaleFor(
        plan,
        views,
        availableWidth: 1000,
        availableHeight: available,
      );

      var used = kViewGap * (views.length - 1);
      for (final entry in views) {
        final axes = axesFor(entry.view, swapped: entry.swapped);
        used +=
            containerExtent(plan, axes.vertical) * scale +
            kViewPadding * 2 +
            kViewLabelHeight;
      }
      expect(used, lessThanOrEqualTo(available + 1e-9));
    });

    test('swapping a view changes what the stack has to fit', () {
      final plan = tub();
      final natural = sharedScaleFor(
        plan,
        viewsFor(plan),
        availableWidth: 660,
        availableHeight: 400,
      );

      // Laying the side view flat puts its 300 of height across the screen
      // instead of down it.
      final laidFlat = sharedScaleFor(
        plan,
        const [
          (view: ViewAxis.top, swapped: false),
          (view: ViewAxis.side, swapped: true),
        ],
        availableWidth: 660,
        availableHeight: 400,
      );

      expect(laidFlat, isNot(natural));
    });

    test('a tall container is limited by the height instead', () {
      final plan = planOf(
        width: 10,
        height: 400,
        depth: 10,
        items: [gear('a', width: 5, height: 5, depth: 5)],
      );

      final scale = sharedScaleFor(
        plan,
        viewsFor(plan),
        availableWidth: 1000,
        availableHeight: 200,
      );

      expect(plan.container.height * scale, lessThanOrEqualTo(200));
    });

    test('an unbounded height asks only what the width allows', () {
      final plan = tub();

      final scale = sharedScaleFor(
        plan,
        viewsFor(plan),
        availableWidth: 660,
        availableHeight: double.infinity,
      );

      // Stacked, the widest view sets the horizontal limit — the top view's
      // 300 of width — rather than the two adding up across a row.
      expect(scale, closeTo((660 - kViewPadding * 2) / 300, 1e-9));
    });

    test('a degenerate container does not divide by zero', () {
      final plan = planOf(width: 0, height: 0, depth: 0, items: const []);

      expect(
        sharedScaleFor(
          plan,
          viewsFor(plan),
          availableWidth: 100,
          availableHeight: 100,
        ),
        1,
      );
    });

    test('a forced scale overrides fitting to the box', () {
      const geometry = ViewGeometry(
        planWidth: 100,
        planHeight: 100,
        size: Size(50, 50),
        fixedScale: 2,
      );

      expect(geometry.scale, 2);
      expect(geometry.boardSize, const Size(200, 200));
    });
  });
}
