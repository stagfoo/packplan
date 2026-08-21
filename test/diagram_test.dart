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
    test('each axis has the CAD-convention X/Y/Z letter', () {
      expect(PlanAxis.width.axisLetter, 'X');
      expect(PlanAxis.depth.axisLetter, 'Y');
      expect(PlanAxis.height.axisLetter, 'Z');
    });

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

    test('top and side together still cover all three axes', () {
      final shown = <PlanAxis>{
        ...[
          axesFor(ViewAxis.top),
          axesFor(ViewAxis.side),
        ].expand((axes) => [axes.horizontal, axes.vertical]),
      };

      // Otherwise some dimension would be impossible to drag.
      expect(shown, PlanAxis.values.toSet());
    });

    test('front starts hidden - top and side are the default pair', () {
      final views = viewsFor(packedSample(depth: 20));
      expect(views, [ViewAxis.top, ViewAxis.side]);
    });

    test('showing front adds it in front-top-side order', () {
      final views = viewsFor(withHiddenViews(packedSample(depth: 20), {}));
      expect(views, [ViewAxis.front, ViewAxis.top, ViewAxis.side]);
    });

    test('hiding every view but one leaves just that one', () {
      final views = viewsFor(
        withHiddenViews(packedSample(depth: 20), {'front', 'top'}),
      );
      expect(views, [ViewAxis.side]);
    });

    test('the third axis is the one running into the screen', () {
      expect(axisIntoScreen(PlanAxis.width, PlanAxis.height), PlanAxis.depth);
      expect(axisIntoScreen(PlanAxis.width, PlanAxis.depth), PlanAxis.height);
      expect(axisIntoScreen(PlanAxis.depth, PlanAxis.height), PlanAxis.width);
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

    test(
      'packingExtent adds height overflow to height, leaves other axes alone',
      () {
        final plan = withHeightOverflow(samplePlan(depth: 20), 15);

        expect(packingExtent(plan, PlanAxis.height), 55);
        expect(packingExtent(plan, PlanAxis.width), 30);
        expect(packingExtent(plan, PlanAxis.depth), 20);
      },
    );

    test('packingExtent matches containerExtent with no overflow', () {
      final plan = samplePlan();

      expect(packingExtent(plan, PlanAxis.height), 40);
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
      placementAt(
        entryId: 'a',
        x: 0,
        y: 0,
        z: 0,
        width: 10,
        height: 10,
        depth: 10,
      ),
      placementAt(
        entryId: 'b',
        x: 0,
        y: 15,
        z: 0,
        width: 10,
        height: 10,
        depth: 10,
      ),
    ];

    test(
      'flags a pair sharing this view\'s axes even without a real 3D overlap',
      () {
        final conflicts = hiddenAxisConflicts(
          stackedInHeight,
          PlanAxis.width,
          PlanAxis.depth,
          const {},
        );
        expect(conflicts, {'a', 'b'});
      },
    );

    test('does not flag the view whose axes actually show them apart', () {
      final conflicts = hiddenAxisConflicts(
        stackedInHeight,
        PlanAxis.depth,
        PlanAxis.height,
        const {},
      );
      expect(conflicts, isEmpty);
    });

    test(
      'does not flag pieces that are actually separated on this view\'s own axes',
      () {
        final apart = [
          placementAt(
            entryId: 'a',
            x: 0,
            y: 0,
            z: 0,
            width: 10,
            height: 10,
            depth: 10,
          ),
          placementAt(
            entryId: 'b',
            x: 20,
            y: 0,
            z: 0,
            width: 10,
            height: 10,
            depth: 10,
          ),
        ];
        expect(
          hiddenAxisConflicts(apart, PlanAxis.width, PlanAxis.depth, const {}),
          isEmpty,
        );
      },
    );

    test('defers to a real overlap instead of double-flagging it', () {
      final trulyOverlapping = [
        placementAt(
          entryId: 'a',
          x: 0,
          y: 0,
          z: 0,
          width: 10,
          height: 10,
          depth: 10,
        ),
        placementAt(
          entryId: 'b',
          x: 5,
          y: 5,
          z: 5,
          width: 10,
          height: 10,
          depth: 10,
        ),
      ];
      final issues = {
        'a': {PlacementIssue.overlapping},
        'b': {PlacementIssue.overlapping},
      };
      expect(
        hiddenAxisConflicts(
          trulyOverlapping,
          PlanAxis.width,
          PlanAxis.depth,
          issues,
        ),
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

    testWidgets('the header just names the view - dimensions moved to the '
        'info icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
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
      );

      expect(find.text('Front'), findsOneWidget);
      expect(find.textContaining('×'), findsNothing);
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

  group('shared scale across a grid of views', () {
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
      final views = viewsFor(plan);
      final scale = sharedScaleForGrid(
        plan,
        views,
        availableWidth: 660,
        availableHeight: 400,
        columns: 2,
        rows: 1,
      );

      final boards = [
        for (final view in views)
          ViewGeometry(
            planWidth: containerExtent(plan, axesFor(view).horizontal),
            planHeight: containerExtent(plan, axesFor(view).vertical),
            size: const Size(100, 100),
            fixedScale: scale,
          ),
      ];

      expect(boards.map((b) => b.scale).toSet(), {scale});
    });

    test('depth reads truthfully against width', () {
      final plan = tub();
      final scale = sharedScaleForGrid(
        plan,
        viewsFor(plan),
        availableWidth: 660,
        availableHeight: 400,
        columns: 2,
        rows: 1,
      );

      // The top view is 300 across and 105 down: depth against width.
      expect(
        (plan.workingDepth * scale) / (plan.container.width * scale),
        closeTo(105 / 300, 1e-9),
      );
    });

    test('each cell fits the width it is given', () {
      final plan = tub();
      const available = 660.0;
      final views = viewsFor(plan);
      final scale = sharedScaleForGrid(
        plan,
        views,
        availableWidth: available,
        availableHeight: 400,
        columns: 2,
        rows: 1,
      );

      // Two columns, so each cell only gets half the width, minus the gap
      // between them.
      final cellWidth = (available - kViewGap) / 2;
      for (final view in views) {
        final axes = axesFor(view);
        final used =
            containerExtent(plan, axes.horizontal) * scale + kViewPadding * 2;
        expect(used, lessThanOrEqualTo(cellWidth + 1e-9));
      }
    });

    test('each cell fits the height it is given', () {
      final plan = tub();
      const available = 500.0;
      final views = viewsFor(plan);
      final scale = sharedScaleForGrid(
        plan,
        views,
        availableWidth: 1000,
        availableHeight: available,
        columns: 2,
        rows: 1,
      );

      for (final view in views) {
        final axes = axesFor(view);
        final used =
            containerExtent(plan, axes.vertical) * scale +
            kViewPadding * 2 +
            kViewLabelHeight;
        expect(used, lessThanOrEqualTo(available + 1e-9));
      }
    });

    test('a tall container is limited by the height instead', () {
      final plan = planOf(
        width: 10,
        height: 400,
        depth: 10,
        items: [gear('a', width: 5, height: 5, depth: 5)],
      );

      final scale = sharedScaleForGrid(
        plan,
        viewsFor(plan),
        availableWidth: 1000,
        availableHeight: 200,
        columns: 2,
        rows: 1,
      );

      expect(plan.container.height * scale, lessThanOrEqualTo(200));
    });

    test('a second row leaves each cell less height to work with', () {
      final plan = planOf(
        width: 10,
        height: 400,
        depth: 10,
        items: [gear('a', width: 5, height: 5, depth: 5)],
      );

      final oneRow = sharedScaleForGrid(
        plan,
        viewsFor(plan),
        availableWidth: 1000,
        availableHeight: 400,
        columns: 2,
        rows: 1,
      );
      final twoRows = sharedScaleForGrid(
        plan,
        viewsFor(plan),
        availableWidth: 1000,
        availableHeight: 400,
        columns: 1,
        rows: 2,
      );

      expect(twoRows, lessThan(oneRow));
    });

    test('an unbounded height asks only what the width allows', () {
      final plan = tub();

      final scale = sharedScaleForGrid(
        plan,
        viewsFor(plan),
        availableWidth: 660,
        availableHeight: double.infinity,
        columns: 2,
        rows: 1,
      );

      // Two columns, so each cell only gets half the width — the top view's
      // 300 of width sets the limit within that half.
      final cellWidth = (660 - kViewGap) / 2;
      expect(scale, closeTo((cellWidth - kViewPadding * 2) / 300, 1e-9));
    });

    test('an empty list of views does not divide by zero', () {
      final plan = tub();

      expect(
        sharedScaleForGrid(
          plan,
          const [],
          availableWidth: 100,
          availableHeight: 100,
          columns: 2,
          rows: 1,
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
