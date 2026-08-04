import 'package:flutter_test/flutter_test.dart';
import 'package:packplan/models.dart';
import 'package:packplan/packer.dart';

Good good(
  String id, {
  required double width,
  required double height,
  double? depth,
  bool rotatable = true,
}) => Good(
  id: id,
  name: id,
  width: width,
  height: height,
  depth: depth,
  colorValue: kGearPalette.first,
  rotatable: rotatable,
);

GearContainer container({
  required double width,
  required double height,
  double? depth,
  required List<Good> goods,
}) => GearContainer(
  id: 'c',
  name: 'container',
  width: width,
  height: height,
  depth: depth,
  colorValue: kGearPalette.first,
  goods: goods,
);

/// Placements must never share volume — that is the whole point of packing.
void expectNoOverlaps(PackResult result) {
  final placements = result.placements.values.toList();
  for (var i = 0; i < placements.length; i++) {
    for (var j = i + 1; j < placements.length; j++) {
      expect(
        placements[i].overlaps(placements[j]),
        isFalse,
        reason:
            '${placements[i].goodId} overlaps ${placements[j].goodId}',
      );
    }
  }
}

void expectInsideContainer(PackResult result, GearContainer c) {
  final depth = c.isThreeDimensional ? c.depth! : 1.0;
  for (final placement in result.placements.values) {
    expect(placement.x, greaterThanOrEqualTo(0));
    expect(placement.y, greaterThanOrEqualTo(0));
    expect(placement.z, greaterThanOrEqualTo(0));
    expect(placement.right, lessThanOrEqualTo(c.width));
    expect(placement.bottom, lessThanOrEqualTo(c.height));
    expect(placement.back, lessThanOrEqualTo(depth));
  }
}

void main() {
  group('flat packing', () {
    test('places goods that comfortably fit', () {
      final c = container(
        width: 30,
        height: 40,
        goods: [
          good('stove', width: 12, height: 10),
          good('mug', width: 9, height: 9),
          good('bag', width: 20, height: 12),
        ],
      );

      final result = packContainer(c);

      expect(result.everythingFits, isTrue);
      expect(result.placements, hasLength(3));
      expectNoOverlaps(result);
      expectInsideContainer(result, c);
    });

    test('reports goods too large for the container at all', () {
      final c = container(
        width: 20,
        height: 20,
        goods: [
          good('tarp', width: 50, height: 40),
          good('mug', width: 9, height: 9),
        ],
      );

      final result = packContainer(c);

      expect(result.unfitted.map((g) => g.id), ['tarp']);
      expect(result.placements.keys, ['mug']);
    });

    test('turns a good 90 degrees when that is the only way it fits', () {
      final c = container(
        width: 10,
        height: 30,
        goods: [good('pole', width: 25, height: 8)],
      );

      final result = packContainer(c);

      expect(result.everythingFits, isTrue);
      final placement = result.placements['pole']!;
      expect(placement.width, 8);
      expect(placement.height, 25);
    });

    test('leaves a good that may not be turned unpacked', () {
      final c = container(
        width: 10,
        height: 30,
        goods: [good('pole', width: 25, height: 8, rotatable: false)],
      );

      expect(packContainer(c).unfitted.map((g) => g.id), ['pole']);
    });

    test('fills a container exactly when the goods tile it', () {
      final c = container(
        width: 20,
        height: 20,
        goods: [
          good('a', width: 10, height: 10),
          good('b', width: 10, height: 10),
          good('c', width: 10, height: 10),
          good('d', width: 10, height: 10),
        ],
      );

      final result = packContainer(c);

      expect(result.everythingFits, isTrue);
      expectNoOverlaps(result);
      expectInsideContainer(result, c);
    });

    test('ignores container depth when no good has any', () {
      final c = container(
        width: 20,
        height: 20,
        depth: 15,
        goods: [good('a', width: 10, height: 10)],
      );

      expect(c.isThreeDimensional, isFalse);
      expect(packContainer(c).placements['a']!.z, 0);
    });
  });

  group('three-dimensional packing', () {
    test('stacks goods through the depth of the container', () {
      final c = container(
        width: 10,
        height: 10,
        depth: 20,
        goods: [
          good('a', width: 10, height: 10, depth: 10),
          good('b', width: 10, height: 10, depth: 10),
        ],
      );

      final result = packContainer(c);

      expect(result.everythingFits, isTrue);
      expectNoOverlaps(result);
      expectInsideContainer(result, c);
      // The only way both fit is one behind the other.
      final zs = result.placements.values.map((p) => p.z).toList()..sort();
      expect(zs, [0, 10]);
    });

    test('lays a good down when standing it up would be too deep', () {
      final c = container(
        width: 30,
        height: 30,
        depth: 11,
        goods: [good('pot', width: 10, height: 10, depth: 12)],
      );

      final result = packContainer(c);

      expect(result.everythingFits, isTrue);
      // 12 exceeds the depth, so the pot has to go in on its side.
      expect(result.placements['pot']!.depth, lessThanOrEqualTo(11));
    });

    test('rejects a good too deep to lie down either', () {
      final c = container(
        width: 30,
        height: 30,
        depth: 5,
        goods: [good('pot', width: 10, height: 10, depth: 12)],
      );

      expect(packContainer(c).unfitted.map((g) => g.id), ['pot']);
    });

    test('cannot save a good that exceeds the container on every axis pair', () {
      final c = container(
        width: 5,
        height: 5,
        depth: 5,
        goods: [good('tent', width: 40, height: 20, depth: 20)],
      );

      expect(packContainer(c).unfitted.map((g) => g.id), ['tent']);
    });

    test('gives a depthless good a nominal depth rather than dropping it', () {
      // Roomy enough that the map can sit beside the pot — the pot spans the
      // full depth, so the map has to clear it on the x axis.
      final c = container(
        width: 30,
        height: 30,
        depth: 10,
        goods: [
          good('pot', width: 10, height: 10, depth: 10),
          good('map', width: 15, height: 15),
        ],
      );

      final result = packContainer(c);

      expect(result.everythingFits, isTrue);
      expect(result.placements['map']!.depth, kFlatGoodDepth);
      expectNoOverlaps(result);
    });

    test('never stands a depthless good on the invented edge', () {
      final c = container(
        width: 20,
        height: 20,
        depth: 20,
        goods: [good('map', width: 15, height: 10)],
      );

      final placement = packContainer(c).placements['map']!;

      expect(placement.depth, kFlatGoodDepth);
      expect({placement.width, placement.height}, {15.0, 10.0});
    });

    test('packs a realistic kit without overlaps', () {
      final c = container(
        width: 30,
        height: 45,
        depth: 20,
        goods: [
          good('sleeping bag', width: 20, height: 20, depth: 20),
          good('stove', width: 12, height: 10, depth: 10),
          good('mug', width: 9, height: 9, depth: 9),
          good('headtorch', width: 6, height: 4, depth: 4),
          good('first aid', width: 14, height: 10, depth: 5),
          good('map', width: 20, height: 15),
        ],
      );

      final result = packContainer(c);

      expect(result.everythingFits, isTrue);
      expectNoOverlaps(result);
      expectInsideContainer(result, c);
    });

    test('is deterministic', () {
      final c = container(
        width: 30,
        height: 45,
        depth: 20,
        goods: [
          good('a', width: 20, height: 20, depth: 20),
          good('b', width: 12, height: 10, depth: 10),
          good('c', width: 9, height: 9, depth: 9),
        ],
      );

      final first = packContainer(c);
      final second = packContainer(c);

      for (final id in first.placements.keys) {
        expect(second.placements[id]!.x, first.placements[id]!.x);
        expect(second.placements[id]!.y, first.placements[id]!.y);
        expect(second.placements[id]!.z, first.placements[id]!.z);
      }
    });
  });

  group('placement issues', () {
    test('an auto-packed container has none', () {
      final c = container(
        width: 30,
        height: 40,
        goods: [
          good('a', width: 12, height: 10),
          good('b', width: 9, height: 9),
        ],
      );
      final packed = c.copyWith(placements: packContainer(c).placements);

      expect(findPlacementIssues(packed), isEmpty);
    });

    test('flags both goods when a drag overlaps them', () {
      final c = container(
        width: 30,
        height: 40,
        goods: [
          good('a', width: 12, height: 10),
          good('b', width: 9, height: 9),
        ],
      ).copyWith(
        placements: {
          'a': const Placement(
            goodId: 'a',
            x: 0,
            y: 0,
            z: 0,
            width: 12,
            height: 10,
            depth: 1,
          ),
          'b': const Placement(
            goodId: 'b',
            x: 5,
            y: 5,
            z: 0,
            width: 9,
            height: 9,
            depth: 1,
          ),
        },
      );

      final issues = findPlacementIssues(c);

      expect(issues['a'], contains(PlacementIssue.overlapping));
      expect(issues['b'], contains(PlacementIssue.overlapping));
    });

    test('flags a good dragged past the container edge', () {
      final c = container(
        width: 30,
        height: 40,
        goods: [good('a', width: 12, height: 10)],
      ).copyWith(
        placements: {
          'a': const Placement(
            goodId: 'a',
            x: 25,
            y: 0,
            z: 0,
            width: 12,
            height: 10,
            depth: 1,
          ),
        },
      );

      expect(findPlacementIssues(c)['a'], contains(PlacementIssue.outOfBounds));
    });

    test('touching faces are not an overlap', () {
      final c = container(
        width: 30,
        height: 40,
        goods: [
          good('a', width: 10, height: 10),
          good('b', width: 10, height: 10),
        ],
      ).copyWith(
        placements: {
          'a': const Placement(
            goodId: 'a',
            x: 0,
            y: 0,
            z: 0,
            width: 10,
            height: 10,
            depth: 1,
          ),
          'b': const Placement(
            goodId: 'b',
            x: 10,
            y: 0,
            z: 0,
            width: 10,
            height: 10,
            depth: 1,
          ),
        },
      );

      expect(findPlacementIssues(c), isEmpty);
    });
  });

  group('container reporting', () {
    test('area and volume usage reflect what was packed', () {
      final c = container(
        width: 10,
        height: 10,
        depth: 10,
        goods: [good('a', width: 5, height: 10, depth: 10)],
      );
      final packed = c.copyWith(placements: packContainer(c).placements);

      expect(packed.areaUsed, closeTo(0.5, 1e-9));
      expect(packed.volumeUsed, closeTo(0.5, 1e-9));
    });

    test('a flat plan reports no volume', () {
      final c = container(
        width: 10,
        height: 10,
        goods: [good('a', width: 5, height: 10)],
      );

      expect(c.volumeUsed, isNull);
    });

    test('unpacked goods are listed separately', () {
      final c = container(
        width: 10,
        height: 10,
        goods: [
          good('fits', width: 5, height: 5),
          good('huge', width: 50, height: 50),
        ],
      );
      final packed = c.copyWith(placements: packContainer(c).placements);

      expect(packed.packedGoods.map((g) => g.id), ['fits']);
      expect(packed.unpackedGoods.map((g) => g.id), ['huge']);
    });
  });
}
