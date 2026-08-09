import 'package:flutter_test/flutter_test.dart';
import 'package:packplan/models.dart';
import 'package:packplan/packer.dart';

import 'support.dart';

/// Placements must never share volume — that is the whole point of packing.
void expectNoOverlaps(PackResult result, {double clearance = 0}) {
  final placements = result.placements.values.toList();
  for (var i = 0; i < placements.length; i++) {
    for (var j = i + 1; j < placements.length; j++) {
      expect(
        placements[i].overlaps(placements[j], clearance: clearance),
        isFalse,
        reason: '${placements[i].entryId} clashes with ${placements[j].entryId}',
      );
    }
  }
}

void expectInsideContainer(PackResult result, Plan plan) {
  final margin = wallMarginFor(plan.tolerance);
  final depthMargin = plan.isThreeDimensional ? margin : 0.0;

  for (final placement in result.placements.values) {
    expect(placement.x, greaterThanOrEqualTo(margin));
    expect(placement.y, greaterThanOrEqualTo(margin));
    expect(placement.z, greaterThanOrEqualTo(depthMargin));
    expect(placement.right, lessThanOrEqualTo(plan.container.width - margin));
    expect(placement.bottom, lessThanOrEqualTo(plan.container.height - margin));
    expect(placement.back, lessThanOrEqualTo(plan.workingDepth - depthMargin));
  }
}

void main() {
  group('flat packing', () {
    test('places gear that comfortably fits', () {
      final plan = planOf(
        width: 30,
        height: 40,
        items: [
          gear('stove', width: 12, height: 10),
          gear('mug', width: 9, height: 9),
          gear('bag', width: 20, height: 12),
        ],
      );

      final result = packPlan(plan);

      expect(result.everythingFits, isTrue);
      expect(result.placements, hasLength(3));
      expectNoOverlaps(result);
      expectInsideContainer(result, plan);
    });

    test('reports gear too large for the container at all', () {
      final plan = planOf(
        width: 20,
        height: 20,
        items: [
          gear('tarp', width: 50, height: 40),
          gear('mug', width: 9, height: 9),
        ],
      );

      final result = packPlan(plan);

      expect(result.unfitted.map((e) => e.id), ['tarp']);
      expect(result.placements.keys, ['mug']);
    });

    test('turns gear 90 degrees when that is the only way it fits', () {
      final plan = planOf(
        width: 10,
        height: 30,
        items: [gear('pole', width: 25, height: 8)],
      );

      final placement = packPlan(plan).placements['pole']!;

      expect(placement.width, 8);
      expect(placement.height, 25);
    });

    test('leaves gear that may not be turned unpacked', () {
      final plan = planOf(
        width: 10,
        height: 30,
        items: [gear('pole', width: 25, height: 8, rotatable: false)],
      );

      expect(packPlan(plan).unfitted.map((e) => e.id), ['pole']);
    });

    test('fills a container exactly when the gear tiles it', () {
      final plan = planOf(
        width: 20,
        height: 20,
        items: [
          gear('a', width: 10, height: 10),
          gear('b', width: 10, height: 10),
          gear('c', width: 10, height: 10),
          gear('d', width: 10, height: 10),
        ],
      );

      final result = packPlan(plan);

      expect(result.everythingFits, isTrue);
      expectNoOverlaps(result);
      expectInsideContainer(result, plan);
    });

    test('ignores container depth when no gear has any', () {
      final plan = planOf(
        width: 20,
        height: 20,
        depth: 15,
        items: [gear('a', width: 10, height: 10)],
      );

      expect(plan.isThreeDimensional, isFalse);
      expect(packPlan(plan).placements['a']!.z, 0);
    });
  });

  group('three-dimensional packing', () {
    test('stacks gear through the depth of the container', () {
      final plan = planOf(
        width: 10,
        height: 10,
        depth: 20,
        items: [
          gear('a', width: 10, height: 10, depth: 10),
          gear('b', width: 10, height: 10, depth: 10),
        ],
      );

      final result = packPlan(plan);

      expect(result.everythingFits, isTrue);
      expectNoOverlaps(result);
      final zs = result.placements.values.map((p) => p.z).toList()..sort();
      expect(zs, [0, 10]);
    });

    test('lays gear down when standing it up would be too deep', () {
      final plan = planOf(
        width: 30,
        height: 30,
        depth: 11,
        items: [gear('pot', width: 10, height: 10, depth: 12)],
      );

      final result = packPlan(plan);

      expect(result.everythingFits, isTrue);
      expect(result.placements['pot']!.depth, lessThanOrEqualTo(11));
    });

    test('rejects gear too deep to lie down either', () {
      final plan = planOf(
        width: 30,
        height: 30,
        depth: 5,
        items: [gear('pot', width: 10, height: 10, depth: 12)],
      );

      expect(packPlan(plan).unfitted.map((e) => e.id), ['pot']);
    });

    test('gives depthless gear a nominal depth rather than dropping it', () {
      final plan = planOf(
        width: 30,
        height: 30,
        depth: 10,
        items: [
          gear('pot', width: 10, height: 10, depth: 10),
          gear('map', width: 15, height: 15),
        ],
      );

      final result = packPlan(plan);

      expect(result.everythingFits, isTrue);
      expect(result.placements['map']!.depth, kFlatGearDepth);
      expectNoOverlaps(result);
    });

    test('never stands depthless gear on the invented edge', () {
      final plan = planOf(
        width: 20,
        height: 20,
        depth: 20,
        items: [gear('map', width: 15, height: 10)],
      );

      final placement = packPlan(plan).placements['map']!;

      expect(placement.depth, kFlatGearDepth);
      expect({placement.width, placement.height}, {15.0, 10.0});
    });

    test('packs a realistic kit without overlaps', () {
      final plan = planOf(
        width: 30,
        height: 45,
        depth: 20,
        items: [
          gear('sleeping bag', width: 20, height: 20, depth: 20),
          gear('stove', width: 12, height: 10, depth: 10),
          gear('mug', width: 9, height: 9, depth: 9),
          gear('headtorch', width: 6, height: 4, depth: 4),
          gear('first aid', width: 14, height: 10, depth: 5),
          gear('map', width: 20, height: 15),
        ],
      );

      final result = packPlan(plan);

      expect(result.everythingFits, isTrue);
      expectNoOverlaps(result);
      expectInsideContainer(result, plan);
    });

    test('is deterministic', () {
      final plan = planOf(
        width: 30,
        height: 45,
        depth: 20,
        items: [
          gear('a', width: 20, height: 20, depth: 20),
          gear('b', width: 12, height: 10, depth: 10),
          gear('c', width: 9, height: 9, depth: 9),
        ],
      );

      final first = packPlan(plan);
      final second = packPlan(plan);

      for (final id in first.placements.keys) {
        expect(second.placements[id]!.x, first.placements[id]!.x);
        expect(second.placements[id]!.y, first.placements[id]!.y);
        expect(second.placements[id]!.z, first.placements[id]!.z);
      }
    });
  });

  group('tolerance', () {
    test('takes one tolerance off each dimension, not two', () {
      // A 3 cm tolerance turns a 105 cm tub into 102 cm of usable depth, so a
      // 100 cm box still goes in. Half the gap sits against each wall.
      final plan = planOf(
        width: 300,
        height: 300,
        depth: 105,
        tolerance: 3,
        items: [gear('chuckbox', width: 200, height: 100, depth: 100)],
      );

      final result = packPlan(plan);

      expect(result.everythingFits, isTrue);
      expect(result.placements['chuckbox']!.z, 1.5);
      expectInsideContainer(result, plan);
    });

    test('a box too big for the usable space is still refused', () {
      // Every side is over the 102 cm the tolerance leaves, so no amount of
      // turning gets it in.
      final plan = planOf(
        width: 300,
        height: 300,
        depth: 105,
        tolerance: 3,
        items: [gear('crate', width: 200, height: 150, depth: 103)],
      );

      expect(packPlan(plan).unfitted.map((e) => e.id), ['crate']);
    });

    test('but turning it can save a box that is only slightly too deep', () {
      final plan = planOf(
        width: 300,
        height: 300,
        depth: 105,
        tolerance: 3,
        items: [gear('chuckbox', width: 200, height: 100, depth: 103)],
      );

      // 103 will not go in the 102 of usable depth, but 100 will.
      final result = packPlan(plan);
      expect(result.everythingFits, isTrue);
      expect(result.placements['chuckbox']!.depth, lessThanOrEqualTo(102));
    });

    test('keeps gear clear of the container walls', () {
      final plan = planOf(
        width: 20,
        height: 20,
        tolerance: 1,
        items: [gear('a', width: 10, height: 10)],
      );

      final placement = packPlan(plan).placements['a']!;

      // Half the tolerance against each wall.
      expect(placement.x, 0.5);
      expect(placement.y, 0.5);
      expectInsideContainer(packPlan(plan), plan);
    });

    test('keeps a gap between two pieces of gear', () {
      final plan = planOf(
        width: 30,
        height: 20,
        tolerance: 2,
        items: [
          gear('a', width: 10, height: 10),
          gear('b', width: 10, height: 10),
        ],
      );

      final result = packPlan(plan);

      expect(result.everythingFits, isTrue);
      expectNoOverlaps(result, clearance: 2);
    });

    test('turns a snug fit into a misfit', () {
      // Two 10-wide pieces exactly fill a 20-wide container with no tolerance,
      // but cannot once a gap is required.
      final snug = planOf(
        width: 20,
        height: 10,
        items: [
          gear('a', width: 10, height: 10),
          gear('b', width: 10, height: 10),
        ],
      );
      expect(packPlan(snug).everythingFits, isTrue);

      final withGap = planOf(
        width: 20,
        height: 10,
        tolerance: 1,
        items: [
          gear('a', width: 10, height: 10),
          gear('b', width: 10, height: 10),
        ],
      );
      expect(packPlan(withGap).everythingFits, isFalse);
    });

    test('applies to depth in a three-dimensional plan', () {
      final plan = planOf(
        width: 20,
        height: 20,
        depth: 20,
        tolerance: 1,
        items: [gear('a', width: 5, height: 5, depth: 5)],
      );

      expect(packPlan(plan).placements['a']!.z, 0.5);
    });

    test('does not eat the invented depth axis of a flat plan', () {
      // A flat plan's depth is a nominal 1 cm; taking tolerance off it would
      // leave nothing and wrongly reject everything.
      final plan = planOf(
        width: 20,
        height: 20,
        tolerance: 2,
        items: [gear('a', width: 5, height: 5)],
      );

      expect(packPlan(plan).everythingFits, isTrue);
      expect(packPlan(plan).placements['a']!.z, 0);
    });

    test('reports when tolerance leaves no usable space', () {
      final plan = planOf(
        width: 10,
        height: 10,
        // More than the container is wide, so nothing can fit.
        tolerance: 12,
        items: [gear('a', width: 1, height: 1)],
      );

      expect(toleranceLeavesNoSpace(plan), isTrue);
      expect(packPlan(plan).placements, isEmpty);
      expect(packPlan(plan).unfitted, hasLength(1));
    });

    test('zero tolerance still lets gear sit flush', () {
      final plan = planOf(
        width: 20,
        height: 10,
        items: [
          gear('a', width: 10, height: 10),
          gear('b', width: 10, height: 10),
        ],
      );

      final result = packPlan(plan);
      final xs = result.placements.values.map((p) => p.x).toList()..sort();
      expect(xs, [0, 10]);
    });
  });

  group('placement issues', () {
    test('an auto-packed plan has none', () {
      final plan = planOf(
        width: 30,
        height: 40,
        items: [
          gear('a', width: 12, height: 10),
          gear('b', width: 9, height: 9),
        ],
      );
      final packed = withPlacements(plan, packPlan(plan).placements);

      expect(findPlacementIssues(packed), isEmpty);
    });

    test('an auto-packed plan with tolerance has none either', () {
      final plan = planOf(
        width: 30,
        height: 40,
        tolerance: 1.5,
        items: [
          gear('a', width: 12, height: 10),
          gear('b', width: 9, height: 9),
        ],
      );
      final packed = withPlacements(plan, packPlan(plan).placements);

      expect(findPlacementIssues(packed), isEmpty);
    });

    test('flags both pieces when a drag overlaps them', () {
      final plan = planOf(
        width: 30,
        height: 40,
        items: [
          gear('a', width: 12, height: 10),
          gear('b', width: 9, height: 9),
        ],
        placements: {
          'a': placementAt(entryId: 'a', width: 12, height: 10),
          'b': placementAt(entryId: 'b', x: 5, y: 5, width: 9, height: 9),
        },
      );

      final issues = findPlacementIssues(plan);

      expect(issues['a'], contains(PlacementIssue.overlapping));
      expect(issues['b'], contains(PlacementIssue.overlapping));
    });

    test('flags gear that is merely too close once tolerance applies', () {
      // Touching faces: fine at zero tolerance, a clash at 1 cm.
      Plan build(double tolerance) => planOf(
        width: 30,
        height: 40,
        tolerance: tolerance,
        items: [
          gear('a', width: 10, height: 10),
          gear('b', width: 10, height: 10),
        ],
        placements: {
          'a': placementAt(entryId: 'a', x: 0, y: 0, width: 10, height: 10),
          'b': placementAt(entryId: 'b', x: 10, y: 0, width: 10, height: 10),
        },
      );

      expect(findPlacementIssues(build(0)), isEmpty);
      expect(
        findPlacementIssues(build(1))['a'],
        contains(PlacementIssue.overlapping),
      );
    });

    test('flags gear inside the tolerance margin as out of bounds', () {
      final plan = planOf(
        width: 30,
        height: 40,
        tolerance: 2,
        items: [gear('a', width: 10, height: 10)],
        placements: {
          'a': placementAt(entryId: 'a', x: 0, y: 5, width: 10, height: 10),
        },
      );

      expect(
        findPlacementIssues(plan)['a'],
        contains(PlacementIssue.outOfBounds),
      );
    });

    test('flags gear dragged past the container edge', () {
      final plan = planOf(
        width: 30,
        height: 40,
        items: [gear('a', width: 12, height: 10)],
        placements: {
          'a': placementAt(entryId: 'a', x: 25, width: 12, height: 10),
        },
      );

      expect(
        findPlacementIssues(plan)['a'],
        contains(PlacementIssue.outOfBounds),
      );
    });
  });

  group('plan reporting', () {
    test('area and volume usage reflect what was packed', () {
      final plan = planOf(
        width: 10,
        height: 10,
        depth: 10,
        items: [gear('a', width: 5, height: 10, depth: 10)],
      );
      final packed = withPlacements(plan, packPlan(plan).placements);

      expect(packed.areaUsed, closeTo(0.5, 1e-9));
      expect(packed.volumeUsed, closeTo(0.5, 1e-9));
    });

    test('a flat plan reports no volume', () {
      final plan = planOf(
        width: 10,
        height: 10,
        items: [gear('a', width: 5, height: 10)],
      );

      expect(plan.volumeUsed, isNull);
    });

    test('unpacked gear is listed separately', () {
      final plan = planOf(
        width: 10,
        height: 10,
        items: [
          gear('fits', width: 5, height: 5),
          gear('huge', width: 50, height: 50),
        ],
      );
      final packed = withPlacements(plan, packPlan(plan).placements);

      expect(packed.packed.map((e) => e.id), ['fits']);
      expect(packed.unpacked.map((e) => e.id), ['huge']);
    });
  });

  group('tags', () {
    test('are lowercased, deduplicated, stripped and sorted', () {
      expect(normaliseTags(['Camp', '#cook', 'camp', ' EDC ']), [
        'camp',
        'cook',
        'edc',
      ]);
    });

    test('drop empties', () {
      expect(normaliseTags(['', '  ', '#']), isEmpty);
    });
  });
}
