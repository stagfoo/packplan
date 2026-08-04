import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:packplan/diagram.dart';
import 'package:packplan/models.dart';
import 'package:packplan/packer.dart';

GearContainer sampleContainer({double? depth}) => GearContainer(
  id: 'c',
  name: 'daypack',
  width: 30,
  height: 40,
  depth: depth,
  colorValue: kGearPalette.first,
  goods: [
    Good(
      id: 'a',
      name: 'stove',
      width: 10,
      height: 10,
      depth: depth == null ? null : 10,
      colorValue: kGearPalette[1],
    ),
    Good(
      id: 'b',
      name: 'mug',
      width: 10,
      height: 10,
      depth: depth == null ? null : 10,
      colorValue: kGearPalette[2],
    ),
  ],
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
      // Width allows 100/10 = 10, height allows 200/20 = 10.
      expect(geometry.scale, 10);
    });

    test('centres the container in the available space', () {
      expect(geometry.boardSize, const Size(100, 200));
      expect(geometry.origin, const Offset(10, 10));
    });

    test('puts plan y zero at the bottom of the board', () {
      // A 10x5 good sitting on the floor should touch the board's bottom edge.
      final rect = geometry.toCanvas(0, 0, 10, 5);

      expect(rect.bottom, geometry.boardRect.bottom);
      expect(rect.left, geometry.boardRect.left);
      expect(rect.height, 50);
    });

    test('places a raised good above the floor', () {
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
      final extents = extentsFor(sampleContainer(depth: 20), ViewAxis.front);

      expect(extents.horizontal, 30);
      expect(extents.vertical, 40);
    });

    test('the side view measures depth and height', () {
      final extents = extentsFor(sampleContainer(depth: 20), ViewAxis.side);

      expect(extents.horizontal, 20);
      expect(extents.vertical, 40);
    });

    test('a flat plan has a nominal side extent', () {
      final extents = extentsFor(sampleContainer(), ViewAxis.side);

      expect(extents.horizontal, 1);
    });

    test('a placement spans x in front and z from the side', () {
      const placement = Placement(
        goodId: 'a',
        x: 3,
        y: 0,
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
    ContainerViewPainter painterFor(GearContainer container, ViewAxis axis) =>
        ContainerViewPainter(
          container: container,
          axis: axis,
          issues: const {},
          selectedGoodId: null,
          textDirection: TextDirection.ltr,
          outlineColor: const Color(0xFF000000),
          labelColor: const Color(0xFF000000),
          emptyColor: const Color(0xFFEEEEEE),
        );

    test('finds the good under the pointer', () {
      final container = sampleContainer();
      final packed = container.copyWith(
        placements: packContainer(container).placements,
      );
      const size = Size(300, 400);
      final painter = painterFor(packed, ViewAxis.front);

      final placement = packed.placements['a']!;
      final geometry = painter.geometryFor(size);
      final rect = geometry.toCanvas(
        placement.x,
        placement.y,
        placement.width,
        placement.height,
      );

      expect(painter.goodAt(rect.center, size), 'a');
    });

    test('returns null over empty container space', () {
      final container = sampleContainer();
      final packed = container.copyWith(
        placements: packContainer(container).placements,
      );
      const size = Size(300, 400);
      final painter = painterFor(packed, ViewAxis.front);

      // The goods pack into the bottom-left, so the top-right corner is bare.
      final board = painter.geometryFor(size).boardRect;
      expect(
        painter.goodAt(
          Offset(board.right - 5, board.top + 5),
          size,
        ),
        isNull,
      );
    });

    test('returns null outside the container entirely', () {
      final container = sampleContainer();
      final packed = container.copyWith(
        placements: packContainer(container).placements,
      );
      final painter = painterFor(packed, ViewAxis.front);

      expect(painter.goodAt(Offset.zero, const Size(300, 400)), isNull);
    });

    test('picks the nearer good when two overlap in projection', () {
      // Both goods sit at the same x/y but different depths, so the front view
      // shows them stacked. The nearer one — smaller z — must win.
      final container = sampleContainer(depth: 30).copyWith(
        placements: {
          'a': const Placement(
            goodId: 'a',
            x: 0,
            y: 0,
            z: 20,
            width: 10,
            height: 10,
            depth: 10,
          ),
          'b': const Placement(
            goodId: 'b',
            x: 0,
            y: 0,
            z: 0,
            width: 10,
            height: 10,
            depth: 10,
          ),
        },
      );
      const size = Size(300, 400);
      final painter = painterFor(container, ViewAxis.front);
      final geometry = painter.geometryFor(size);
      final rect = geometry.toCanvas(0, 0, 10, 10);

      expect(painter.goodAt(rect.center, size), 'b');
    });
  });

  group('ContainerView interaction', () {
    Future<void> pumpView(
      WidgetTester tester, {
      required GearContainer container,
      required ViewAxis axis,
      required void Function(String, Offset) onDragged,
      ValueChanged<String?>? onSelected,
      VoidCallback? onDragEnded,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 400,
                child: ContainerView(
                  container: container,
                  axis: axis,
                  issues: const {},
                  selectedGoodId: null,
                  onSelected: onSelected ?? (_) {},
                  onDragged: onDragged,
                  onDragEnded: onDragEnded ?? () {},
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('tapping a good selects it', (tester) async {
      final container = sampleContainer();
      final packed = container.copyWith(
        placements: packContainer(container).placements,
      );
      String? selected;

      await pumpView(
        tester,
        container: packed,
        axis: ViewAxis.front,
        onDragged: (_, _) {},
        onSelected: (goodId) => selected = goodId,
      );

      // The packer puts goods in the bottom-left, so tap near there.
      final view = tester.getRect(find.byType(CustomPaint).last);
      await tester.tapAt(Offset(view.left + 30, view.bottom - 30));
      await tester.pump();

      expect(selected, isNotNull);
    });

    testWidgets('dragging reports a plan-space delta', (tester) async {
      final container = sampleContainer();
      final packed = container.copyWith(
        placements: packContainer(container).placements,
      );
      final deltas = <Offset>[];
      var ended = 0;

      await pumpView(
        tester,
        container: packed,
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
      final container = sampleContainer();
      final packed = container.copyWith(
        placements: packContainer(container).placements,
      );
      final deltas = <Offset>[];
      var ended = 0;

      await pumpView(
        tester,
        container: packed,
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
  });

  test('formatLength drops trailing zeroes', () {
    expect(formatLength(30), '30');
    expect(formatLength(30.5), '30.5');
  });
}
