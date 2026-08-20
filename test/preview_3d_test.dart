import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:packplan/preview_3d.dart';

void expectVec3Close(Vec3 actual, Vec3 expected, {double tolerance = 1e-9}) {
  expect(actual.$1, closeTo(expected.$1, tolerance));
  expect(actual.$2, closeTo(expected.$2, tolerance));
  expect(actual.$3, closeTo(expected.$3, tolerance));
}

void main() {
  group('rotate3', () {
    test('no rotation leaves a point exactly where it was', () {
      expectVec3Close(rotate3((3, 4, 5), 0, 0), (3, 4, 5));
    });

    test('azimuth spins the width/depth plane around the height axis', () {
      // A quarter turn sends "width" onto where "depth" was.
      expectVec3Close(rotate3((1, 0, 0), math.pi / 2, 0), (0, 0, 1));
      // Height never moves under azimuth alone.
      expectVec3Close(rotate3((0, 1, 0), math.pi / 2, 0), (0, 1, 0));
    });

    test('elevation tilts height against depth, leaving width alone', () {
      expectVec3Close(rotate3((1, 0, 0), 0, math.pi / 2), (1, 0, 0));
      expectVec3Close(rotate3((0, 1, 0), 0, math.pi / 2), (0, 0, 1));
    });

    test('a full turn returns to the start', () {
      expectVec3Close(
        rotate3((2, -3, 5), 2 * math.pi, 0),
        (2, -3, 5),
        tolerance: 1e-6,
      );
    });

    test('rotation preserves length - it never stretches a point', () {
      const v = (3.0, -4.0, 12.0);
      double length(Vec3 vec) =>
          math.sqrt(vec.$1 * vec.$1 + vec.$2 * vec.$2 + vec.$3 * vec.$3);

      final rotated = rotate3(v, 0.7, -1.1);
      expect(length(rotated), closeTo(length(v), 1e-9));
    });
  });
}
