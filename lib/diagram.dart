import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';
import 'packer.dart';
import 'units.dart';

/// Which pair of axes a view draws.
///
/// The front view looks at the container head on: plan x runs across, plan y
/// runs up. The side view looks at it from the left: plan z runs across, plan y
/// still runs up. Between them the two views pin down all three axes, which is
/// why dragging in either one is enough to position gear completely.
enum ViewAxis { front, side }

extension ViewAxisLabel on ViewAxis {
  String get label => switch (this) {
    ViewAxis.front => 'Front',
    ViewAxis.side => 'Side',
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
  Rect toCanvas(double x, double y, double width, double height) =>
      Rect.fromLTWH(
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
({double horizontal, double vertical}) extentsFor(Plan plan, ViewAxis axis) =>
    switch (axis) {
      ViewAxis.front => (
        horizontal: plan.container.width,
        vertical: plan.container.height,
      ),
      ViewAxis.side => (
        horizontal: plan.workingDepth,
        vertical: plan.container.height,
      ),
    };

/// The horizontal position and size a placement occupies in [axis].
({double offset, double size}) spanFor(Placement placement, ViewAxis axis) =>
    switch (axis) {
      ViewAxis.front => (offset: placement.x, size: placement.width),
      ViewAxis.side => (offset: placement.z, size: placement.depth),
    };

/// Draws one orthographic view of a packed container.
class ContainerViewPainter extends CustomPainter {
  ContainerViewPainter({
    required this.plan,
    required this.axis,
    required this.issues,
    required this.selectedEntryId,
    required this.textDirection,
    required this.outlineColor,
    required this.labelColor,
    required this.emptyColor,
    required this.toleranceColor,
  });

  final Plan plan;
  final ViewAxis axis;
  final Map<String, Set<PlacementIssue>> issues;
  final String? selectedEntryId;
  final TextDirection textDirection;
  final Color outlineColor;
  final Color labelColor;
  final Color emptyColor;
  final Color toleranceColor;

  ViewGeometry geometryFor(Size size) {
    final extents = extentsFor(plan, axis);
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
    final boardRadius = RRect.fromRectAndRadius(
      board,
      const Radius.circular(6),
    );

    canvas.drawRRect(boardRadius, Paint()..color = emptyColor);
    _paintToleranceMargin(canvas, geometry);

    for (final entry in _drawOrder()) {
      _paintGear(canvas, geometry, entry);
    }

    // The container outline goes on top so gear dragged past the edge reads as
    // sticking out rather than quietly covering the frame.
    canvas.drawRRect(
      boardRadius,
      Paint()
        ..color = plan.container.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  /// Marks the strip the tolerance keeps clear, so the gap around the gear
  /// reads as deliberate rather than as sloppy packing.
  void _paintToleranceMargin(Canvas canvas, ViewGeometry geometry) {
    final tolerance = plan.tolerance;
    if (tolerance <= 0) return;

    // A flat plan's depth axis is a fiction, so it has no margin to show.
    final horizontal = axis == ViewAxis.side && !plan.isThreeDimensional
        ? 0.0
        : tolerance;

    final extents = extentsFor(plan, axis);
    final usableWidth = extents.horizontal - horizontal * 2;
    final usableHeight = extents.vertical - tolerance * 2;
    if (usableWidth <= 0 || usableHeight <= 0) return;

    canvas.drawRect(
      geometry.toCanvas(horizontal, tolerance, usableWidth, usableHeight),
      Paint()
        ..color = toleranceColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  /// Farthest gear first, so nearer pieces overlap it the way they would in a
  /// real projection.
  List<PlanEntry> _drawOrder() {
    final entries = plan.packed;

    entries.sort((a, b) {
      // Looking at the front, "far" means a large z. Looking from the left,
      // "far" means a large x.
      final aDepth = axis == ViewAxis.front
          ? a.placement!.z
          : a.placement!.x;
      final bDepth = axis == ViewAxis.front
          ? b.placement!.z
          : b.placement!.x;
      final byDepth = bDepth.compareTo(aDepth);
      if (byDepth != 0) return byDepth;
      return a.id.compareTo(b.id);
    });

    // The selected gear always sits on top so a drag stays visible.
    final selectedIndex = entries.indexWhere(
      (entry) => entry.id == selectedEntryId,
    );
    if (selectedIndex >= 0) entries.add(entries.removeAt(selectedIndex));

    return entries;
  }

  void _paintGear(Canvas canvas, ViewGeometry geometry, PlanEntry entry) {
    final placement = entry.placement!;
    final span = spanFor(placement, axis);
    final rect = geometry.toCanvas(
      span.offset,
      placement.y,
      span.size,
      placement.height,
    );
    final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(3));

    final entryIssues = issues[entry.id] ?? const <PlacementIssue>{};
    final isSelected = entry.id == selectedEntryId;

    canvas.drawRRect(
      rounded,
      Paint()
        ..color = entry.item.color.withValues(alpha: isSelected ? 0.95 : 0.8),
    );

    final borderColor = entryIssues.isNotEmpty
        ? const Color(0xFFDC2626)
        : (isSelected ? outlineColor : entry.item.color);
    canvas.drawRRect(
      rounded,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = entryIssues.isNotEmpty || isSelected ? 2.5 : 1,
    );

    _paintLabel(canvas, rect, entry.item);
  }

  void _paintLabel(Canvas canvas, Rect rect, GearItem item) {
    // Anything smaller than this cannot hold legible text, and a clipped label
    // is worse than none.
    if (rect.width < 26 || rect.height < 14) return;

    final painter = TextPainter(
      text: TextSpan(
        text: item.name,
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

  /// The topmost gear at [position], or null. Iterates the draw order backwards
  /// so the piece the user can actually see is the one they grab.
  String? entryAt(Offset position, Size size) {
    final geometry = geometryFor(size);
    for (final entry in _drawOrder().reversed) {
      final span = spanFor(entry.placement!, axis);
      final rect = geometry.toCanvas(
        span.offset,
        entry.placement!.y,
        span.size,
        entry.placement!.height,
      );
      if (rect.contains(position)) return entry.id;
    }
    return null;
  }

  @override
  bool shouldRepaint(ContainerViewPainter oldDelegate) => true;
}

/// One interactive view of a container. Tapping selects gear, dragging moves it
/// along this view's two axes.
class ContainerView extends StatefulWidget {
  const ContainerView({
    super.key,
    required this.plan,
    required this.axis,
    required this.issues,
    required this.selectedEntryId,
    required this.onSelected,
    required this.onDragged,
    required this.onDragEnded,
    required this.onRotate,
  });

  final Plan plan;
  final ViewAxis axis;
  final Map<String, Set<PlacementIssue>> issues;
  final String? selectedEntryId;
  final ValueChanged<String?> onSelected;

  /// Reports a drag as a plan-space delta along this view's horizontal and
  /// vertical axes. The screen decides which plan axes those map to.
  final void Function(String entryId, Offset planDelta) onDragged;

  /// Fires once when a drag finishes, so the screen can persist the result
  /// rather than writing on every frame.
  final VoidCallback onDragEnded;

  /// Turns the selected gear a quarter turn in *this* view's plane.
  final ValueChanged<String> onRotate;

  @override
  State<ContainerView> createState() => _ContainerViewState();
}

class _ContainerViewState extends State<ContainerView> {
  String? _draggingEntryId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extents = extentsFor(widget.plan, widget.axis);
    final unit = UnitScope.of(context);

    // Only placed gear can be turned — there is nothing on the diagram to turn
    // otherwise.
    final selectedId = widget.selectedEntryId;
    final selected = selectedId == null
        ? null
        : widget.plan.packed.where((e) => e.id == selectedId).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            '${widget.axis.label} · '
            '${unit.format(extents.horizontal)} × '
            '${unit.formatWithSymbol(extents.vertical)}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              final painter = ContainerViewPainter(
                plan: widget.plan,
                axis: widget.axis,
                issues: widget.issues,
                selectedEntryId: widget.selectedEntryId,
                textDirection: Directionality.of(context),
                outlineColor: theme.colorScheme.onSurface,
                labelColor: Colors.black.withValues(alpha: 0.8),
                emptyColor: theme.colorScheme.surfaceContainerHighest,
                toleranceColor: theme.colorScheme.outlineVariant,
              );

              final board = GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => widget.onSelected(
                  painter.entryAt(details.localPosition, size),
                ),
                onPanStart: (details) {
                  final entryId = painter.entryAt(details.localPosition, size);
                  _draggingEntryId = entryId;
                  if (entryId != null) widget.onSelected(entryId);
                },
                onPanUpdate: (details) {
                  final entryId = _draggingEntryId;
                  if (entryId == null) return;
                  final geometry = painter.geometryFor(size);
                  widget.onDragged(entryId, geometry.deltaToPlan(details.delta));
                },
                onPanEnd: (_) {
                  if (_draggingEntryId != null) widget.onDragEnded();
                  _draggingEntryId = null;
                },
                onPanCancel: () {
                  if (_draggingEntryId != null) widget.onDragEnded();
                  _draggingEntryId = null;
                },
                child: CustomPaint(size: size, painter: painter),
              );

              if (selected == null) return board;

              // Anchored to the container's own top-right rather than the
              // view's, so it stays attached to the shape instead of floating
              // in whatever empty space the aspect ratio leaves over.
              const buttonSize = 36.0;
              final frame = painter.geometryFor(size).boardRect;

              // The turn button sits in the view it turns things in, so there
              // is never a question of which way round "turn" means. It goes
              // over the diagram rather than in the header, where it would
              // squeeze the dimensions out of the side view's label.
              return Stack(
                children: [
                  Positioned.fill(child: board),
                  Positioned(
                    top: math.max(frame.top - 6, 0),
                    left: math.max(frame.right - buttonSize + 6, 0),
                    child: Material(
                      color: theme.colorScheme.surface.withValues(alpha: 0.85),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: IconButton(
                        tooltip: 'Turn ${selected.item.name}',
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
                        onPressed: () => widget.onRotate(selected.id),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Carries the chosen measurement unit down the tree, so no widget has to be
/// handed one just to render a number.
class UnitScope extends InheritedWidget {
  const UnitScope({super.key, required this.unit, required super.child});

  final MeasurementUnit unit;

  static MeasurementUnit of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<UnitScope>()
          ?.unit ??
      MeasurementUnit.centimetres;

  @override
  bool updateShouldNotify(UnitScope oldWidget) => oldWidget.unit != unit;
}
