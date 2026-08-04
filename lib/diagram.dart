import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';
import 'packer.dart';

/// Which pair of axes a view draws.
///
/// The front view looks at the container head on: plan x runs across, plan y
/// runs up. The side view looks at it from the left: plan z runs across, plan y
/// still runs up. Between them the two views pin down all three axes, which is
/// why dragging in either one is enough to position a good completely.
enum ViewAxis { front, side }

extension ViewAxisLabel on ViewAxis {
  String get label => switch (this) {
    ViewAxis.front => 'Front',
    ViewAxis.side => 'Side',
  };

  /// What the horizontal axis of this view measures.
  String get horizontalLabel => switch (this) {
    ViewAxis.front => 'width',
    ViewAxis.side => 'depth',
  };
}

/// Maps between plan centimetres and canvas pixels for one view.
///
/// Plan y is measured up from the bottom of the container, so a packed
/// container settles on its floor instead of hanging from its lid.
class ViewGeometry {
  const ViewGeometry({
    required this.planWidth,
    required this.planHeight,
    required this.size,
    this.padding = 10,
  });

  final double planWidth;
  final double planHeight;
  final Size size;
  final double padding;

  double get scale {
    if (planWidth <= 0 || planHeight <= 0) return 1;
    final usableWidth = math.max(size.width - padding * 2, 1.0);
    final usableHeight = math.max(size.height - padding * 2, 1.0);
    return math.min(usableWidth / planWidth, usableHeight / planHeight);
  }

  Size get boardSize => Size(planWidth * scale, planHeight * scale);

  Offset get origin => Offset(
    (size.width - boardSize.width) / 2,
    (size.height - boardSize.height) / 2,
  );

  Rect get boardRect => origin & boardSize;

  /// Converts a plan-space rectangle to canvas pixels, flipping the y axis.
  Rect toCanvas(double x, double y, double width, double height) => Rect.fromLTWH(
    origin.dx + x * scale,
    origin.dy + (planHeight - y - height) * scale,
    width * scale,
    height * scale,
  );

  /// Converts a canvas delta to a plan-space delta. The y component is negated
  /// because dragging up on screen increases plan y.
  Offset deltaToPlan(Offset canvasDelta) =>
      Offset(canvasDelta.dx / scale, -canvasDelta.dy / scale);
}

/// The horizontal and vertical plan extents a container occupies in [axis].
({double horizontal, double vertical}) extentsFor(
  GearContainer container,
  ViewAxis axis,
) {
  final depth = container.isThreeDimensional ? container.depth! : 1.0;
  return switch (axis) {
    ViewAxis.front => (horizontal: container.width, vertical: container.height),
    ViewAxis.side => (horizontal: depth, vertical: container.height),
  };
}

/// The horizontal position and size a placement occupies in [axis].
({double offset, double size}) spanFor(Placement placement, ViewAxis axis) =>
    switch (axis) {
      ViewAxis.front => (offset: placement.x, size: placement.width),
      ViewAxis.side => (offset: placement.z, size: placement.depth),
    };

/// Draws one orthographic view of a packed container.
class ContainerViewPainter extends CustomPainter {
  ContainerViewPainter({
    required this.container,
    required this.axis,
    required this.issues,
    required this.selectedGoodId,
    required this.textDirection,
    required this.outlineColor,
    required this.labelColor,
    required this.emptyColor,
  });

  final GearContainer container;
  final ViewAxis axis;
  final Map<String, Set<PlacementIssue>> issues;
  final String? selectedGoodId;
  final TextDirection textDirection;
  final Color outlineColor;
  final Color labelColor;
  final Color emptyColor;

  ViewGeometry geometryFor(Size size) {
    final extents = extentsFor(container, axis);
    return ViewGeometry(
      planWidth: extents.horizontal,
      planHeight: extents.vertical,
      size: size,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = geometryFor(size);
    final board = geometry.boardRect;
    final boardRadius = RRect.fromRectAndRadius(board, const Radius.circular(6));

    canvas.drawRRect(boardRadius, Paint()..color = emptyColor);

    for (final entry in _drawOrder()) {
      _paintGood(canvas, geometry, entry.good, entry.placement);
    }

    // The container outline goes on top so goods dragged past the edge read as
    // sticking out rather than quietly covering the frame.
    canvas.drawRRect(
      boardRadius,
      Paint()
        ..color = container.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  /// Farthest goods first, so nearer ones overlap them the way they would in a
  /// real projection.
  List<({Good good, Placement placement})> _drawOrder() {
    final entries = <({Good good, Placement placement})>[];
    for (final good in container.goods) {
      final placement = container.placements[good.id];
      if (placement != null) entries.add((good: good, placement: placement));
    }

    entries.sort((a, b) {
      // Looking at the front, "far" means a large z. Looking from the left,
      // "far" means a large x.
      final aDepth = axis == ViewAxis.front ? a.placement.z : a.placement.x;
      final bDepth = axis == ViewAxis.front ? b.placement.z : b.placement.x;
      final byDepth = bDepth.compareTo(aDepth);
      if (byDepth != 0) return byDepth;
      return a.good.id.compareTo(b.good.id);
    });

    // The selected good always sits on top so a drag stays visible.
    final selectedIndex = entries.indexWhere(
      (entry) => entry.good.id == selectedGoodId,
    );
    if (selectedIndex >= 0) {
      entries.add(entries.removeAt(selectedIndex));
    }

    return entries;
  }

  void _paintGood(
    Canvas canvas,
    ViewGeometry geometry,
    Good good,
    Placement placement,
  ) {
    final span = spanFor(placement, axis);
    final rect = geometry.toCanvas(
      span.offset,
      placement.y,
      span.size,
      placement.height,
    );
    final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(3));

    final goodIssues = issues[good.id] ?? const <PlacementIssue>{};
    final isSelected = good.id == selectedGoodId;

    canvas.drawRRect(
      rounded,
      Paint()..color = good.color.withValues(alpha: isSelected ? 0.95 : 0.8),
    );

    final borderColor = goodIssues.isNotEmpty
        ? const Color(0xFFDC2626)
        : (isSelected ? outlineColor : good.color);
    canvas.drawRRect(
      rounded,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = goodIssues.isNotEmpty || isSelected ? 2.5 : 1,
    );

    _paintLabel(canvas, rect, good);
  }

  void _paintLabel(Canvas canvas, Rect rect, Good good) {
    // Anything smaller than this can't hold legible text, and a clipped label
    // is worse than none.
    if (rect.width < 26 || rect.height < 14) return;

    final painter = TextPainter(
      text: TextSpan(
        text: good.name,
        style: TextStyle(
          color: labelColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
      ),
      textDirection: textDirection,
      textAlign: TextAlign.center,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: rect.width - 4);

    if (painter.height > rect.height - 2) return;

    painter.paint(
      canvas,
      Offset(
        rect.left + (rect.width - painter.width) / 2,
        rect.top + (rect.height - painter.height) / 2,
      ),
    );
  }

  /// The topmost good at [position], or null. Iterates the draw order backwards
  /// so the good the user can actually see is the one they grab.
  String? goodAt(Offset position, Size size) {
    final geometry = geometryFor(size);
    for (final entry in _drawOrder().reversed) {
      final span = spanFor(entry.placement, axis);
      final rect = geometry.toCanvas(
        span.offset,
        entry.placement.y,
        span.size,
        entry.placement.height,
      );
      if (rect.contains(position)) return entry.good.id;
    }
    return null;
  }

  @override
  bool shouldRepaint(ContainerViewPainter oldDelegate) =>
      oldDelegate.container != container ||
      oldDelegate.axis != axis ||
      oldDelegate.issues != issues ||
      oldDelegate.selectedGoodId != selectedGoodId ||
      oldDelegate.outlineColor != outlineColor;
}

/// One interactive view of a container. Tapping selects a good, dragging moves
/// it along this view's two axes.
class ContainerView extends StatefulWidget {
  const ContainerView({
    super.key,
    required this.container,
    required this.axis,
    required this.issues,
    required this.selectedGoodId,
    required this.onSelected,
    required this.onDragged,
    required this.onDragEnded,
  });

  final GearContainer container;
  final ViewAxis axis;
  final Map<String, Set<PlacementIssue>> issues;
  final String? selectedGoodId;
  final ValueChanged<String?> onSelected;

  /// Reports a drag as a plan-space delta along this view's horizontal and
  /// vertical axes. The screen decides which plan axes those map to.
  final void Function(String goodId, Offset planDelta) onDragged;

  /// Fires once when a drag finishes, so the screen can persist the result
  /// rather than writing on every frame.
  final VoidCallback onDragEnded;

  @override
  State<ContainerView> createState() => _ContainerViewState();
}

class _ContainerViewState extends State<ContainerView> {
  String? _draggingGoodId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extents = extentsFor(widget.container, widget.axis);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            '${widget.axis.label} · '
            '${formatLength(extents.horizontal)} × '
            '${formatLength(extents.vertical)} cm',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              final painter = ContainerViewPainter(
                container: widget.container,
                axis: widget.axis,
                issues: widget.issues,
                selectedGoodId: widget.selectedGoodId,
                textDirection: Directionality.of(context),
                outlineColor: theme.colorScheme.onSurface,
                labelColor: Colors.black.withValues(alpha: 0.8),
                emptyColor: theme.colorScheme.surfaceContainerHighest,
              );

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) =>
                    widget.onSelected(painter.goodAt(details.localPosition, size)),
                onPanStart: (details) {
                  final goodId = painter.goodAt(details.localPosition, size);
                  _draggingGoodId = goodId;
                  if (goodId != null) widget.onSelected(goodId);
                },
                onPanUpdate: (details) {
                  final goodId = _draggingGoodId;
                  if (goodId == null) return;
                  final geometry = painter.geometryFor(size);
                  widget.onDragged(goodId, geometry.deltaToPlan(details.delta));
                },
                onPanEnd: (_) {
                  if (_draggingGoodId != null) widget.onDragEnded();
                  _draggingGoodId = null;
                },
                onPanCancel: () {
                  if (_draggingGoodId != null) widget.onDragEnded();
                  _draggingGoodId = null;
                },
                child: CustomPaint(size: size, painter: painter),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Trims the pointless '.0' off whole-number measurements.
String formatLength(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}
