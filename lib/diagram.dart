import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';
import 'packer.dart';
import 'units.dart';

/// One of the container's three axes, in plan space.
enum PlanAxis {
  width('width'),
  height('height'),
  depth('depth');

  const PlanAxis(this.label);

  final String label;
}

/// Which way you are looking at the container.
///
/// Between them the views on screen have to cover all three axes, or some
/// dimension would be impossible to drag. Front plus side does it; so does top
/// plus side, which is what a plan with depth shows — the top view is the one
/// you actually look at when you pack a tub.
enum ViewAxis {
  front('Front'),
  top('Top'),
  side('Side');

  const ViewAxis(this.label);

  final String label;
}

/// The pair of plan axes a view draws, once any swap is applied.
///
/// Swapping transposes the view — the same two axes, turned a quarter turn on
/// screen. A tall, narrow container makes for a tall, narrow side view, and
/// laying it flat is the only way it reads on a phone.
({PlanAxis horizontal, PlanAxis vertical}) axesFor(
  ViewAxis view, {
  bool swapped = false,
}) {
  final natural = switch (view) {
    ViewAxis.front => (horizontal: PlanAxis.width, vertical: PlanAxis.height),
    ViewAxis.top => (horizontal: PlanAxis.width, vertical: PlanAxis.depth),
    ViewAxis.side => (horizontal: PlanAxis.depth, vertical: PlanAxis.height),
  };
  return swapped
      ? (horizontal: natural.vertical, vertical: natural.horizontal)
      : natural;
}

/// The axis running into the screen for a view showing [horizontal] and
/// [vertical] — what decides which gear is drawn in front of which.
PlanAxis axisIntoScreen(PlanAxis horizontal, PlanAxis vertical) =>
    PlanAxis.values.firstWhere(
      (axis) => axis != horizontal && axis != vertical,
    );

/// The turn a view's two axes describe, for the rotate button.
RotationPlane rotationPlaneFor(PlanAxis horizontal, PlanAxis vertical) {
  final pair = {horizontal, vertical};
  if (pair.containsAll({PlanAxis.width, PlanAxis.height})) {
    return RotationPlane.widthHeight;
  }
  if (pair.containsAll({PlanAxis.depth, PlanAxis.height})) {
    return RotationPlane.depthHeight;
  }
  return RotationPlane.widthDepth;
}

/// How far the container reaches along [axis].
double containerExtent(Plan plan, PlanAxis axis) => switch (axis) {
  PlanAxis.width => plan.container.width,
  PlanAxis.height => plan.container.height,
  PlanAxis.depth => plan.workingDepth,
};

/// Where a placement sits along [axis], and how far it reaches.
({double offset, double size}) placementSpan(Placement placement, PlanAxis axis) =>
    switch (axis) {
      PlanAxis.width => (offset: placement.x, size: placement.width),
      PlanAxis.height => (offset: placement.y, size: placement.height),
      PlanAxis.depth => (offset: placement.z, size: placement.depth),
    };

/// Maps between plan centimetres and canvas pixels for one view.
///
/// The vertical axis is flipped only when it is the container's height, so a
/// packed container settles on its floor instead of hanging from its lid.
/// Depth and width read top-down, the way you look into a bag from above.
class ViewGeometry {
  const ViewGeometry({
    required this.planWidth,
    required this.planHeight,
    required this.size,
    this.padding = kViewPadding,
    this.fixedScale,
    this.flipVertical = true,
  });

  final double planWidth;
  final double planHeight;
  final Size size;
  final double padding;

  /// Forces a scale rather than fitting to [size].
  ///
  /// Views drawn together have to share a scale, or the same container reads as
  /// two different sizes. The screen works it out across all of them and hands
  /// it to each.
  final double? fixedScale;

  /// Whether plan zero sits at the bottom of the board rather than the top.
  final bool flipVertical;

  double get scale {
    final forced = fixedScale;
    if (forced != null) return forced > 0 ? forced : 1;
    if (planWidth <= 0 || planHeight <= 0) return 1;
    final usableWidth = math.max(size.width - padding * 2, 1.0);
    final usableHeight = math.max(size.height - padding * 2, 1.0);
    return math.min(usableWidth / planWidth, usableHeight / planHeight);
  }

  Size get boardSize => Size(planWidth * scale, planHeight * scale);

  /// A view drawn on its own centres in whatever room it has. Views drawn
  /// together are pinned to the top left instead, so their boards line up down
  /// the stack and each one's label gets the full width to print in.
  Offset get origin => fixedScale != null
      ? Offset(padding, padding)
      : Offset(
          (size.width - boardSize.width) / 2,
          (size.height - boardSize.height) / 2,
        );

  Rect get boardRect => origin & boardSize;

  /// Converts a plan-space rectangle to canvas pixels.
  Rect toCanvas(double x, double y, double width, double height) =>
      Rect.fromLTWH(
        origin.dx + x * scale,
        origin.dy +
            (flipVertical ? planHeight - y - height : y) * scale,
        width * scale,
        height * scale,
      );

  /// Converts a canvas delta to a plan-space delta.
  Offset deltaToPlan(Offset canvasDelta) => Offset(
    canvasDelta.dx / scale,
    (flipVertical ? -canvasDelta.dy : canvasDelta.dy) / scale,
  );
}

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
    this.fixedScale,
    this.swapped = false,
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

  /// Set when this view is drawn with others and they must agree.
  final double? fixedScale;

  /// Whether this view is transposed — the same axes, a quarter turn on screen.
  final bool swapped;

  ({PlanAxis horizontal, PlanAxis vertical}) get axes =>
      axesFor(axis, swapped: swapped);

  bool get _flipVertical => axes.vertical == PlanAxis.height;

  ViewGeometry geometryFor(Size size) => ViewGeometry(
    planWidth: containerExtent(plan, axes.horizontal),
    planHeight: containerExtent(plan, axes.vertical),
    size: size,
    fixedScale: fixedScale,
    flipVertical: _flipVertical,
  );

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
    if (plan.tolerance <= 0) return;
    final margin = wallMarginFor(plan.tolerance);

    // A flat plan's depth axis is a fiction, so it has no margin to show.
    double marginOn(PlanAxis planAxis) =>
        planAxis == PlanAxis.depth && !plan.isThreeDimensional ? 0.0 : margin;

    final horizontal = marginOn(axes.horizontal);
    final vertical = marginOn(axes.vertical);
    final usableWidth =
        containerExtent(plan, axes.horizontal) - horizontal * 2;
    final usableHeight = containerExtent(plan, axes.vertical) - vertical * 2;
    if (usableWidth <= 0 || usableHeight <= 0) return;

    canvas.drawRect(
      geometry.toCanvas(horizontal, vertical, usableWidth, usableHeight),
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

    // Farthest first along whichever axis runs into the screen, so nearer
    // pieces overlap them the way they would in a real projection.
    final into = axisIntoScreen(axes.horizontal, axes.vertical);
    entries.sort((a, b) {
      final byDepth = placementSpan(b.placement!, into).offset.compareTo(
        placementSpan(a.placement!, into).offset,
      );
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
    final across = placementSpan(placement, axes.horizontal);
    final down = placementSpan(placement, axes.vertical);
    final rect = geometry.toCanvas(
      across.offset,
      down.offset,
      across.size,
      down.size,
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
      final across = placementSpan(entry.placement!, axes.horizontal);
      final down = placementSpan(entry.placement!, axes.vertical);
      final rect = geometry.toCanvas(
        across.offset,
        down.offset,
        across.size,
        down.size,
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
    this.fixedScale,
    this.swapped = false,
    this.onSwapAxes,
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

  /// Draw at this many pixels per centimetre instead of fitting to the space,
  /// so the views drawn alongside this one agree with it.
  final double? fixedScale;

  /// Whether this view is transposed.
  final bool swapped;

  /// Lays this view on its side. Null hides the control.
  final VoidCallback? onSwapAxes;

  @override
  State<ContainerView> createState() => _ContainerViewState();
}

class _ContainerViewState extends State<ContainerView> {
  String? _draggingEntryId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axes = axesFor(widget.axis, swapped: widget.swapped);
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
        SizedBox(
          height: kViewLabelHeight,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.axis.label} · '
                  '${unit.format(containerExtent(widget.plan, axes.horizontal))}'
                  ' × '
                  '${unit.formatWithSymbol(containerExtent(widget.plan, axes.vertical))}'
                  '  (${axes.horizontal.label} × ${axes.vertical.label})',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.onSwapAxes != null)
                IconButton(
                  tooltip: 'Lay the ${widget.axis.label.toLowerCase()} view '
                      'on its side',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 28,
                  ),
                  iconSize: 18,
                  isSelected: widget.swapped,
                  icon: const Icon(Icons.swap_horiz),
                  onPressed: widget.onSwapAxes,
                ),
            ],
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
                fixedScale: widget.fixedScale,
                swapped: widget.swapped,
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

/// Space reserved above each view for its axis label. Enough for two lines, so
/// a narrow side view whose dimensions wrap does not sit lower than the front.
const double kViewLabelHeight = 34.0;

/// Breathing room around a board, so its outline is not clipped.
const double kViewPadding = 6.0;

/// Space between the front and side views.
const double kViewGap = 12.0;

/// The pixels-per-centimetre a stack of views should all be drawn at.
///
/// Every view has to use one scale, or the same container reads as a different
/// size in each and the diagram stops being comparable. Stacked, the widest
/// view sets the horizontal limit and the heights add up.
double sharedScaleFor(
  Plan plan,
  List<({ViewAxis view, bool swapped})> views, {
  required double availableWidth,
  required double availableHeight,
}) {
  if (views.isEmpty) return 1;

  var widest = 0.0;
  var totalHeight = 0.0;
  for (final entry in views) {
    final axes = axesFor(entry.view, swapped: entry.swapped);
    widest = math.max(widest, containerExtent(plan, axes.horizontal));
    totalHeight += containerExtent(plan, axes.vertical);
  }
  if (widest <= 0 || totalHeight <= 0) return 1;

  final usableWidth = math.max(availableWidth - kViewPadding * 2, 1.0);
  final byWidth = usableWidth / widest;
  if (!availableHeight.isFinite) return byWidth;

  // Each view carries its own label and padding.
  final chrome = views.length * (kViewLabelHeight + kViewPadding * 2) +
      kViewGap * (views.length - 1);
  final usableHeight = math.max(availableHeight - chrome, 1.0);
  return math.min(byWidth, usableHeight / totalHeight);
}
