import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:packplan/diagram.dart';
import 'package:packplan/models.dart';
import 'package:packplan/packer.dart';
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

  group('extents and spans', () {
    test('the front view measures width and height', () {
      final extents = extentsFor(samplePlan(depth: 20), ViewAxis.front);

      expect(extents.horizontal, 30);
      expect(extents.vertical, 40);
    });

    test('the side view measures depth and height', () {
      final extents = extentsFor(samplePlan(depth: 20), ViewAxis.side);

      expect(extents.horizontal, 20);
      expect(extents.vertical, 40);
    });

    test('a flat plan has a nominal side extent', () {
      expect(extentsFor(samplePlan(), ViewAxis.side).horizontal, 1);
    });

    test('a placement spans x in front and z from the side', () {
      final placement = placementAt(
        entryId: 'a',
        x: 3,
        z: 7,
        width: 10,
        height: 5,
        depth: 2,
      );

      expect(spanFor(placement, ViewAxis.front), (offset: 3.0, size: 10.0));
      expect(spanFor(placement, ViewAxis.side), (offset: 7.0, size: 2.0));
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

      expect(find.text('Front · 300 × 400 mm'), findsOneWidget);
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

    test('both views draw the height they share at the same size', () {
      final plan = tub();
      final scale = sharedScaleFor(
        plan,
        availableWidth: 660,
        availableHeight: 400,
      );

      final front = ViewGeometry(
        planWidth: plan.container.width,
        planHeight: plan.container.height,
        size: Size(plan.container.width * scale, plan.container.height * scale),
        padding: kViewPadding,
        fixedScale: scale,
      );
      final side = ViewGeometry(
        planWidth: plan.workingDepth,
        planHeight: plan.container.height,
        size: Size(plan.workingDepth * scale, plan.container.height * scale),
        padding: kViewPadding,
        fixedScale: scale,
      );

      expect(side.boardSize.height, front.boardSize.height);
      expect(side.scale, front.scale);
    });

    test('depth reads truthfully against width', () {
      final plan = tub();
      final scale = sharedScaleFor(
        plan,
        availableWidth: 660,
        availableHeight: 400,
      );

      final frontWidth = plan.container.width * scale;
      final sideWidth = plan.workingDepth * scale;

      // 105 of depth against 300 of width.
      expect(sideWidth / frontWidth, closeTo(105 / 300, 1e-9));
    });

    test('the two views fit the width they are given', () {
      final plan = tub();
      const available = 660.0;
      final scale = sharedScaleFor(
        plan,
        availableWidth: available,
        availableHeight: 400,
      );

      final used =
          plan.container.width * scale +
          plan.workingDepth * scale +
          kViewGap +
          kViewPadding * 4;
      expect(used, lessThanOrEqualTo(available + 1e-9));
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
        availableWidth: 1000,
        availableHeight: 200,
      );

      expect(plan.container.height * scale, lessThanOrEqualTo(200));
    });

    test('an unbounded height asks only what the width allows', () {
      final plan = tub();

      final scale = sharedScaleFor(
        plan,
        availableWidth: 660,
        availableHeight: double.infinity,
      );

      expect(scale, closeTo((660 - kViewGap - kViewPadding * 4) / 405, 1e-9));
    });

    test('a degenerate container does not divide by zero', () {
      final plan = planOf(width: 0, height: 0, depth: 0, items: const []);

      expect(
        sharedScaleFor(plan, availableWidth: 100, availableHeight: 100),
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
