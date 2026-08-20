import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'diagram.dart' show PlanAxis, containerExtent;
import 'models.dart';

/// A point in plan space (centimetres), reusing the same width/height/depth
/// axes every other view reads from - not a separate model, so this can
/// never disagree with what the orthographic views show.
typedef Vec3 = (double x, double y, double z);

Vec3 _subtract(Vec3 a, Vec3 b) => (a.$1 - b.$1, a.$2 - b.$2, a.$3 - b.$3);

/// Rotates [v] by [azimuth] (around the height axis) then [elevation]
/// (tilting up/down) - the two angles an orbit camera needs. Also used to
/// rotate face normals for shading, since a pure rotation (no scaling)
/// transforms normals exactly the same way as points. Public (rather than
/// folded into the painter) so the math has tests of its own, the same way
/// the orthographic views' axis/projection helpers do in diagram.dart.
Vec3 rotate3(Vec3 v, double azimuth, double elevation) {
  final (x, y, z) = v;

  final cosA = math.cos(azimuth);
  final sinA = math.sin(azimuth);
  final x1 = x * cosA - z * sinA;
  final z1 = x * sinA + z * cosA;

  final cosE = math.cos(elevation);
  final sinE = math.sin(elevation);
  final y2 = y * cosE - z1 * sinE;
  final z2 = y * sinE + z1 * cosE;

  return (x1, y2, z2);
}

/// A drag-to-orbit 3D preview of a packed container.
///
/// View-only for now: dragging orbits the camera rather than moving gear -
/// the orthographic views stay the place to actually pack things, this is
/// just a way to see the shape of the result. Reuses [Plan.packed] and
/// each entry's [Placement] directly (the exact same data the orthographic
/// views draw from), so the cuboids drawn here can never disagree with what
/// those views show.
class Preview3D extends StatefulWidget {
  const Preview3D({super.key, required this.plan});

  final Plan plan;

  @override
  State<Preview3D> createState() => _Preview3DState();
}

class _Preview3DState extends State<Preview3D> {
  // A 3/4 angle to start, rather than straight-on - straight-on would just
  // look like the Front view and defeat the point of a 3D preview.
  double _azimuth = -math.pi / 4;
  double _elevation = math.pi / 6;

  static const double _minElevation = -math.pi / 2 + 0.05;
  static const double _maxElevation = math.pi / 2 - 0.05;

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _azimuth += details.delta.dx * 0.01;
      _elevation = (_elevation - details.delta.dy * 0.01).clamp(
        _minElevation,
        _maxElevation,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onPanUpdate: _onPanUpdate,
          child: CustomPaint(
            size: size,
            painter: _Preview3DPainter(
              plan: widget.plan,
              azimuth: _azimuth,
              elevation: _elevation,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              wireframeColor: widget.plan.container.color,
            ),
          ),
        );
      },
    );
  }
}

class _Face {
  _Face({required this.points, required this.depth, required this.color});

  final List<Offset> points;

  /// Rotated-space depth of this face's centroid - farther from the camera
  /// is more negative here (see [_Preview3DPainter._depthOf]), so sorting
  /// ascending draws back-to-front.
  final double depth;

  final Color color;
}

class _Preview3DPainter extends CustomPainter {
  _Preview3DPainter({
    required this.plan,
    required this.azimuth,
    required this.elevation,
    required this.backgroundColor,
    required this.wireframeColor,
  });

  final Plan plan;
  final double azimuth;
  final double elevation;
  final Color backgroundColor;
  final Color wireframeColor;

  // A fixed light direction (normalized (1,2,1)), pointing down and toward
  // the viewer - it does not rotate with the camera, so a face's shading
  // shifts believably as the user orbits around it, rather than staying a
  // constant shade regardless of which way it's actually facing.
  static const _light = (0.4082, 0.8165, 0.4082);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      Paint()..color = backgroundColor,
    );

    final w = containerExtent(plan, PlanAxis.width);
    final h = containerExtent(plan, PlanAxis.height);
    final d = containerExtent(plan, PlanAxis.depth);
    if (w <= 0 || h <= 0 || d <= 0) return;

    final center = (w / 2, h / 2, d / 2);
    // The container's own diagonal is the longest any projection can ever
    // be, at any rotation - scaling to fit it guarantees the box never
    // clips the canvas regardless of orbit angle.
    final diagonal = math.sqrt(w * w + h * h + d * d);
    final scale = diagonal <= 0
        ? 1.0
        : (math.min(size.width, size.height) * 0.72) / diagonal;
    final origin = Offset(size.width / 2, size.height / 2);

    Offset project(Vec3 world) {
      final rotated = rotate3(_subtract(world, center), azimuth, elevation);
      return origin + Offset(rotated.$1, -rotated.$2) * scale;
    }

    double depthOf(Vec3 world) =>
        rotate3(_subtract(world, center), azimuth, elevation).$3;

    _paintWireframe(canvas, project, w, h, d);

    final faces = <_Face>[
      for (final entry in plan.packed)
        ..._facesFor(entry.placement!, entry.item.color, project, depthOf),
    ]..sort((a, b) => a.depth.compareTo(b.depth));

    for (final face in faces) {
      canvas.drawPath(
        Path()..addPolygon(face.points, true),
        Paint()..color = face.color,
      );
    }
  }

  /// The container's own edges, drawn as lines only - it never fills, so it
  /// never hides packed gear no matter the draw order.
  void _paintWireframe(
    Canvas canvas,
    Offset Function(Vec3) project,
    double w,
    double h,
    double d,
  ) {
    final corners = [
      for (final x in [0.0, w])
        for (final y in [0.0, h])
          for (final z in [0.0, d]) (x, y, z),
    ];
    // Index bits: 4=x, 2=y, 1=z. Each pair below differs in exactly one bit,
    // i.e. is a real edge of the box, not a face diagonal.
    const edges = [
      [0, 1], [0, 2], [0, 4],
      [3, 1], [3, 2], [3, 7],
      [5, 1], [5, 4], [5, 7],
      [6, 2], [6, 4], [6, 7],
    ];
    final paint = Paint()
      ..color = wireframeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final edge in edges) {
      canvas.drawLine(
        project(corners[edge[0]]),
        project(corners[edge[1]]),
        paint,
      );
    }
  }

  List<_Face> _facesFor(
    Placement p,
    Color baseColor,
    Offset Function(Vec3) project,
    double Function(Vec3) depthOf,
  ) {
    final x0 = p.x, x1 = p.right;
    final y0 = p.y, y1 = p.bottom;
    final z0 = p.z, z1 = p.back;

    // Six faces, each wound consistently (doesn't matter for a flat fill,
    // but keeps this readable), paired with its outward-facing unit normal.
    final specs = <(List<Vec3>, Vec3)>[
      ([(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)], (1, 0, 0)),
      ([(x0, y0, z1), (x0, y1, z1), (x0, y1, z0), (x0, y0, z0)], (-1, 0, 0)),
      ([(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)], (0, 1, 0)),
      ([(x0, y0, z1), (x1, y0, z1), (x1, y0, z0), (x0, y0, z0)], (0, -1, 0)),
      ([(x1, y0, z1), (x1, y1, z1), (x0, y1, z1), (x0, y0, z1)], (0, 0, 1)),
      ([(x0, y0, z0), (x0, y1, z0), (x1, y1, z0), (x1, y0, z0)], (0, 0, -1)),
    ];

    return [
      for (final (corners, normal) in specs)
        _Face(
          points: [for (final c in corners) project(c)],
          depth:
              corners.map(depthOf).reduce((a, b) => a + b) / corners.length,
          color: _shade(baseColor, normal),
        ),
    ];
  }

  Color _shade(Color base, Vec3 normal) {
    final rotated = rotate3(normal, azimuth, elevation);
    final dot =
        rotated.$1 * _light.$1 + rotated.$2 * _light.$2 + rotated.$3 * _light.$3;
    final brightness = (0.55 + 0.45 * dot).clamp(0.35, 1.0);
    return Color.lerp(Colors.black, base, brightness)!;
  }

  @override
  bool shouldRepaint(covariant _Preview3DPainter oldDelegate) =>
      oldDelegate.plan != plan ||
      oldDelegate.azimuth != azimuth ||
      oldDelegate.elevation != elevation;
}
