import 'package:flutter/material.dart';

import 'diagram.dart';
import 'edit_sheets.dart';
import 'gear_library_screen.dart';
import 'models.dart';
import 'packer.dart';
import 'preview_3d.dart';
import 'store.dart';
import 'units.dart';

/// The diagram plus the gear list for one container.
class PlanDetailScreen extends StatefulWidget {
  const PlanDetailScreen({
    super.key,
    required this.store,
    required this.planId,
  });

  final GearStore store;
  final String planId;

  @override
  State<PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends State<PlanDetailScreen> {
  String? _selectedEntryId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final plan = widget.store.planFor(widget.planId);

        // The plan can disappear if it was deleted from the list screen, or
        // if its container gear was deleted from the library.
        if (plan == null) {
          return const Scaffold(
            body: Center(child: Text('This plan is gone.')),
          );
        }

        return _build(context, plan);
      },
    );
  }

  Widget _build(BuildContext context, Plan plan) {
    final theme = Theme.of(context);
    final issues = findPlacementIssues(plan);
    final noSpace = toleranceLeavesNoSpace(plan);

    return Scaffold(
      appBar: AppBar(
        title: Text(plan.name),
        actions: [
          IconButton(
            tooltip: 'View dimensions',
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showDimensions(context, plan),
          ),
          IconButton(
            tooltip: 'Edit plan',
            icon: const Icon(Icons.straighten),
            onPressed: () => _editPlan(plan),
          ),
          PopupMenuButton<String>(
            onSelected: (value) => switch (value) {
              'loadout' => _applyLoadout(plan),
              'save-loadout' => _saveAsLoadout(plan),
              _ => null,
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'loadout',
                child: Text('Add from loadout'),
              ),
              const PopupMenuItem(
                value: 'save-loadout',
                child: Text('Save as loadout'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const horizontalPadding = 16.0;

            // Give the diagram exactly the height its shape needs rather than
            // a fixed fraction — a wide, shallow pouch should not reserve half
            // the screen for empty space above and below it.
            final wanted = _diagramHeightFor(
              plan,
              constraints.maxWidth - horizontalPadding * 2,
            );
            final diagramHeight = wanted.clamp(
              constraints.maxHeight * 0.2,
              constraints.maxHeight * 0.55,
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (noSpace)
                  _Banner(
                    message:
                        'The tolerance leaves no usable space in '
                        '${plan.container.name}. Lower it, or pack into '
                        'something bigger.',
                  ),
                if (plan.isThreeDimensional)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      horizontalPadding,
                      12,
                      horizontalPadding,
                      0,
                    ),
                    // Left out of diagramHeight's budget deliberately - its
                    // exact height depends on the chip theme and text scale
                    // factor, and natural flow sidesteps guessing at it.
                    child: _ViewVisibilityToolbar(
                      plan: plan,
                      store: widget.store,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    horizontalPadding,
                    12,
                    horizontalPadding,
                    4,
                  ),
                  child: SizedBox(
                    height: diagramHeight,
                    child: _Diagram(
                      plan: plan,
                      issues: issues,
                      selectedEntryId: _selectedEntryId,
                      onSelected: (entryId) =>
                          setState(() => _selectedEntryId = entryId),
                      onRotate: _rotate,
                      store: widget.store,
                    ),
                  ),
                ),
                if (plan.packed.isNotEmpty)
                  Text(
                    plan.isThreeDimensional
                        ? 'Drag gear in either view to adjust'
                        : 'Drag gear to adjust',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                _SummaryBar(plan: plan, issues: issues),
                const Divider(height: 1),
                Expanded(
                  child: _GearList(
                    plan: plan,
                    issues: issues,
                    selectedEntryId: _selectedEntryId,
                    onSelected: (entryId) => setState(
                      () => _selectedEntryId = _selectedEntryId == entryId
                          ? null
                          : entryId,
                    ),
                    onRemove: (entry) => _removeEntry(plan, entry),
                    onTogglePlaced: (entry) => _togglePlaced(plan, entry),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: plan.entries.isEmpty
                      ? null
                      : () => _autoPack(plan),
                  icon: const Icon(Icons.auto_awesome_mosaic),
                  label: const Text('Auto-pack'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _addGear(plan),
                  icon: const Icon(Icons.add),
                  label: const Text('Add gear'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The height the diagram needs to show the container at its true proportions
  /// across [availableWidth], including the axis label above each view.
  static double _diagramHeightFor(Plan plan, double availableWidth) {
    final container = plan.container;

    if (!plan.isThreeDimensional) {
      if (container.width <= 0) return kViewLabelHeight;
      final scale = (availableWidth - kViewPadding * 2) / container.width;
      return container.height * scale + kViewPadding * 2 + kViewLabelHeight;
    }

    final views = viewsFor(plan);
    final show3D = !plan.hiddenViews.contains('3d');
    final panelCount = views.length + (show3D ? 1 : 0);
    if (panelCount == 0) return kViewLabelHeight;

    // A Blender-style grid: every panel gets its own quadrant rather than
    // competing for a shared height budget down one column, so two panels
    // sit side by side and a third or fourth starts a new row.
    final columns = panelCount > 1 ? 2 : 1;
    final rows = (panelCount / columns).ceil();

    // Unbounded height: this is asking how tall the diagram wants to be, and
    // the caller clamps it.
    final scale = sharedScaleForGrid(
      plan,
      views,
      availableWidth: availableWidth,
      availableHeight: double.infinity,
      columns: columns,
      rows: rows,
    );

    var tallest = 0.0;
    for (final entry in views) {
      final axes = axesFor(entry.view, swapped: entry.swapped);
      final extent = packingExtent(plan, axes.vertical);
      if (extent > tallest) tallest = extent;
    }
    // The 3D panel doesn't share the 2D views' linear scale, but in a grid
    // it still only ever wants exactly one cell, same as everything else.
    final cellHeight = tallest * scale + kViewPadding * 2 + kViewLabelHeight;
    return rows * cellHeight + kViewGap * (rows - 1);
  }

  void _report(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _rotate(String entryId) async {
    final outcome = await widget.store.rotateGear(widget.planId, entryId);

    switch (outcome) {
      case RotateOutcome.rotated:
      case RotateOutcome.notFound:
        break;
      case RotateOutcome.wontFit:
        _report('Nothing else it can turn into fits.');
    }
  }

  Future<void> _autoPack(Plan plan) async {
    final result = await widget.store.autoPack(plan.id);
    _report(
      result.everythingFits
          ? 'Everything fits.'
          : "${result.unfitted.length} didn't fit: "
                '${result.unfitted.map((e) => e.item.name).join(', ')}',
    );
  }

  /// The measurements each panel's header used to print - moved here so they
  /// are a tap away instead of taking up room on every panel all the time.
  void _showDimensions(BuildContext context, Plan plan) {
    final unit = UnitScope.of(context);
    final theme = Theme.of(context);

    String lineFor(ViewAxis axis) {
      final axes = axesFor(
        axis,
        swapped: plan.swappedViews.contains(axis.name),
      );
      return '${axis.label}  ·  '
          '${axes.horizontal.axisLetter} '
          '${unit.format(containerExtent(plan, axes.horizontal))}'
          '  ×  '
          '${axes.vertical.axisLetter} '
          '${unit.formatWithSymbol(containerExtent(plan, axes.vertical))}';
    }

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${plan.container.name} dimensions'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final axis in plan.isThreeDimensional
                ? ViewAxis.values
                : [ViewAxis.front])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(lineFor(axis)),
              ),
            if (plan.heightOverflow > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Open top  ·  +'
                  '${unit.formatWithSymbol(plan.heightOverflow)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _editPlan(Plan plan) async {
    final draft = await showPlanSheet(
      context,
      containers: widget.store.containerItems,
      initial: plan.record,
    );
    if (draft == null) return;

    await widget.store.updatePlan(
      plan.id,
      name: draft.name,
      containerItemId: draft.containerItemId,
      tolerance: draft.tolerance,
      heightOverflow: draft.heightOverflow,
    );
  }

  Future<void> _addGear(Plan plan) async {
    final chosen = await showGearPicker(context, widget.store);
    if (chosen == null || chosen.isEmpty) return;

    final unfitted = <String>[];
    for (final itemId in chosen) {
      final placed = await widget.store.addGear(plan.id, itemId);
      if (!placed) {
        unfitted.add(widget.store.itemById(itemId)?.name ?? 'gear');
      }
    }

    if (unfitted.isEmpty) return;
    _report("No room for ${unfitted.join(', ')}. Try auto-pack.");
  }

  Future<void> _applyLoadout(Plan plan) async {
    final loadouts = widget.store.loadouts;
    if (loadouts.isEmpty) {
      _report('No loadouts yet. Make one from the Loadouts tab.');
      return;
    }

    final loadoutId = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final loadout in loadouts)
              ListTile(
                title: Text(loadout.name),
                subtitle: Text(
                  '${loadout.itemIds.length} '
                  '${loadout.itemIds.length == 1 ? 'item' : 'items'}',
                ),
                onTap: () => Navigator.of(context).pop(loadout.id),
              ),
          ],
        ),
      ),
    );
    if (loadoutId == null) return;

    final unfitted = await widget.store.applyLoadout(plan.id, loadoutId);
    _report(
      unfitted.isEmpty
          ? 'Loadout added, everything fits.'
          : "Loadout added. No room for "
                "${unfitted.map((i) => i.name).join(', ')}.",
    );
  }

  Future<void> _saveAsLoadout(Plan plan) async {
    if (plan.entries.isEmpty) {
      _report('Nothing in this plan to save.');
      return;
    }

    final name = await showNameDialog(
      context,
      title: 'Save as loadout',
      initial: plan.name,
      label: 'Loadout name',
    );
    if (name == null) return;

    await widget.store.savePlanAsLoadout(plan.id, name: name);
    _report('Saved "$name".');
  }

  Future<void> _removeEntry(Plan plan, PlanEntry entry) async {
    if (_selectedEntryId == entry.id) {
      setState(() => _selectedEntryId = null);
    }
    await widget.store.removeEntry(plan.id, entry.id);
  }

  Future<void> _togglePlaced(Plan plan, PlanEntry entry) async {
    if (entry.isPacked) {
      await widget.store.unplaceEntry(plan.id, entry.id);
      return;
    }

    final placed = await widget.store.placeEntry(plan.id, entry.id);
    if (placed) return;
    _report('No room left for ${entry.item.name}. Try auto-pack.');
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      color: theme.colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}

/// The front view, plus a side view when the plan has depth.
class _Diagram extends StatelessWidget {
  const _Diagram({
    required this.plan,
    required this.issues,
    required this.selectedEntryId,
    required this.onSelected,
    required this.onRotate,
    required this.store,
  });

  final Plan plan;
  final Map<String, Set<PlacementIssue>> issues;
  final String? selectedEntryId;
  final ValueChanged<String?> onSelected;
  final ValueChanged<String> onRotate;
  final GearStore store;

  void _onDragged(
    ViewAxis axis,
    bool swapped,
    String entryId,
    Offset planDelta,
  ) {
    // A drag moves along whichever two plan axes this view happens to show.
    final axes = axesFor(axis, swapped: swapped);
    final deltas = <PlanAxis, double>{
      axes.horizontal: planDelta.dx,
      axes.vertical: planDelta.dy,
    };

    store.moveGear(
      plan.id,
      entryId,
      dx: deltas[PlanAxis.width] ?? 0,
      dy: deltas[PlanAxis.height] ?? 0,
      dz: deltas[PlanAxis.depth] ?? 0,
    );
  }

  Widget _view(ViewAxis axis, {double? fixedScale}) {
    final swapped = plan.swappedViews.contains(axis.name);
    return ContainerView(
      plan: plan,
      axis: axis,
      swapped: swapped,
      issues: issues,
      selectedEntryId: selectedEntryId,
      onSelected: onSelected,
      onDragged: (entryId, delta) => _onDragged(axis, swapped, entryId, delta),
      onDragEnded: store.flush,
      onRotate: onRotate,
      onSwapAxes: () => store.toggleViewSwap(plan.id, axis.name),
      fixedScale: fixedScale,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!plan.isThreeDimensional) return _view(ViewAxis.front);

    final views = viewsFor(plan);
    final show3D = !plan.hiddenViews.contains('3d');

    if (views.isEmpty && !show3D) return const Text('No views selected.');

    // A Blender-style grid: every panel gets its own quadrant rather than
    // being squeezed into a shared height budget down one column, so two
    // panels sit side by side and a third or fourth starts a new row.
    final panelCount = views.length + (show3D ? 1 : 0);
    final columns = panelCount > 1 ? 2 : 1;
    final rows = (panelCount / columns).ceil();

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = sharedScaleForGrid(
          plan,
          views,
          availableWidth: constraints.maxWidth,
          availableHeight: constraints.maxHeight,
          columns: columns,
          rows: rows,
        );

        final cells = <Widget>[
          for (final entry in views) _view(entry.view, fixedScale: scale),
          if (show3D) Preview3D(plan: plan),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var r = 0; r < rows; r++) ...[
              if (r > 0) const SizedBox(height: kViewGap),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var c = 0; c < columns; c++) ...[
                      if (c > 0) const SizedBox(width: kViewGap),
                      Expanded(
                        child: r * columns + c < cells.length
                            ? cells[r * columns + c]
                            : const SizedBox(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Front/Top/Side/3D toggle chips, stacked together as up to four panels.
/// A chip for the last remaining visible panel disables itself — hiding it
/// would leave nothing on screen to pack by — rather than allowing the tap
/// and silently doing nothing.
class _ViewVisibilityToolbar extends StatelessWidget {
  const _ViewVisibilityToolbar({required this.plan, required this.store});

  final Plan plan;
  final GearStore store;

  @override
  Widget build(BuildContext context) {
    final visibleNames = <String>{
      for (final view in const [ViewAxis.front, ViewAxis.top, ViewAxis.side])
        if (!plan.hiddenViews.contains(view.name)) view.name,
      if (!plan.hiddenViews.contains('3d')) '3d',
    };

    Widget chip(String name, String label) => FilterChip(
      visualDensity: VisualDensity.compact,
      label: Text(label),
      selected: visibleNames.contains(name),
      onSelected: visibleNames.length == 1 && visibleNames.contains(name)
          ? null
          : (_) => store.toggleViewVisibility(plan.id, name),
    );

    // A horizontal scroller rather than a Wrap - four chips should read as
    // one row of controls, not wrap to a second line and push the diagram
    // down by an unpredictable amount.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(ViewAxis.front.name, ViewAxis.front.label),
          const SizedBox(width: 8),
          chip(ViewAxis.top.name, ViewAxis.top.label),
          const SizedBox(width: 8),
          chip(ViewAxis.side.name, ViewAxis.side.label),
          const SizedBox(width: 8),
          chip('3d', '3D'),
        ],
      ),
    );
  }
}

/// The views a plan shows, in the order they are stacked.
///
/// All three orthographic views cover a different pair of axes; which ones
/// are actually on screen is up to [Plan.hiddenViews] (defaults to Top +
/// Side — between them they already cover all three axes, and the top view
/// is the one you actually look at when you pack a tub, so Front starts
/// hidden rather than crowding a phone screen by default). Phones have far
/// more vertical room than horizontal, so visible views stack rather than
/// sit side by side.
List<({ViewAxis view, bool swapped})> viewsFor(Plan plan) => [
  for (final view in const [ViewAxis.front, ViewAxis.top, ViewAxis.side])
    if (!plan.hiddenViews.contains(view.name))
      (view: view, swapped: plan.swappedViews.contains(view.name)),
];

/// The one-line verdict: how full the container is and what is left over.
class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.plan, required this.issues});

  final Plan plan;
  final Map<String, Set<PlacementIssue>> issues;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unpacked = plan.unpacked.length;
    final clashing = issues.values
        .where((set) => set.contains(PlacementIssue.overlapping))
        .length;

    final volumeUsed = plan.volumeUsed;
    final fill = volumeUsed ?? plan.areaUsed;
    final fillLabel = volumeUsed == null ? 'area' : 'volume';

    final warnings = <String>[
      if (unpacked > 0) '$unpacked not packed',
      if (clashing > 0) '$clashing too close',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(fill * 100).round()}% of $fillLabel used',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: fill.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
          if (warnings.isNotEmpty) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                warnings.join(' · '),
                textAlign: TextAlign.end,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GearList extends StatelessWidget {
  const _GearList({
    required this.plan,
    required this.issues,
    required this.selectedEntryId,
    required this.onSelected,
    required this.onRemove,
    required this.onTogglePlaced,
  });

  final Plan plan;
  final Map<String, Set<PlacementIssue>> issues;
  final String? selectedEntryId;
  final ValueChanged<String> onSelected;
  final ValueChanged<PlanEntry> onRemove;
  final ValueChanged<PlanEntry> onTogglePlaced;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = UnitScope.of(context);

    if (plan.entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Nothing in here yet. Add gear from your library to see how it '
            'fits.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: plan.entries.length,
      itemBuilder: (context, index) {
        final entry = plan.entries[index];
        final item = entry.item;
        final entryIssues = issues[entry.id] ?? const <PlacementIssue>{};

        final notes = <String>[
          formatDimensions(
            unit,
            width: item.width,
            height: item.height,
            depth: item.depth,
          ),
          if (!entry.isPacked) 'not packed',
          if (entryIssues.contains(PlacementIssue.overlapping)) 'too close',
          if (entryIssues.contains(PlacementIssue.outOfBounds)) 'sticking out',
        ];

        return ListTile(
          selected: entry.id == selectedEntryId,
          onTap: () => onSelected(entry.id),
          leading: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: entry.isPacked ? 1 : 0.3),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: entryIssues.isNotEmpty
                    ? theme.colorScheme.error
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          title: Text(item.name),
          subtitle: Text(
            notes.join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: entryIssues.isNotEmpty || !entry.isPacked
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (value) => switch (value) {
              'toggle' => onTogglePlaced(entry),
              'remove' => onRemove(entry),
              _ => null,
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'toggle',
                child: Text(entry.isPacked ? 'Take out' : 'Put in'),
              ),
              const PopupMenuItem(
                value: 'remove',
                child: Text('Remove from container'),
              ),
            ],
          ),
        );
      },
    );
  }
}
