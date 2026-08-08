import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'diagram.dart';
import 'edit_sheets.dart';
import 'gear_library_screen.dart';
import 'models.dart';
import 'packer.dart';
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
              children: [
                if (noSpace)
                  _Banner(
                    message:
                        'The tolerance leaves no usable space in '
                        '${plan.container.name}. Lower it, or pack into '
                        'something bigger.',
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
    const labelHeight = 20.0;

    double heightFor(double width, double planWidth, double planHeight) {
      if (planWidth <= 0) return 0;
      return width * planHeight / planWidth;
    }

    final container = plan.container;
    if (!plan.isThreeDimensional) {
      return heightFor(availableWidth, container.width, container.height) +
          labelHeight;
    }

    // Matches the 3:2 split the two views are laid out with.
    final usable = availableWidth - 12;
    final front = heightFor(usable * 3 / 5, container.width, container.height);
    final side = heightFor(usable * 2 / 5, container.depth!, container.height);
    return math.max(front, side) + labelHeight;
  }

  void _report(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _rotate(ViewAxis axis, String entryId) async {
    final outcome = await widget.store.rotateGear(
      widget.planId,
      entryId,
      axis == ViewAxis.front
          ? RotationPlane.widthHeight
          : RotationPlane.depthHeight,
    );

    switch (outcome) {
      case RotateOutcome.rotated:
      case RotateOutcome.notFound:
        break;
      case RotateOutcome.wontFit:
        _report("It doesn't fit that way round.");
      case RotateOutcome.noDepth:
        _report('Give this a depth before turning it on its side.');
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
  final void Function(ViewAxis axis, String entryId) onRotate;
  final GearStore store;

  void _onDragged(ViewAxis axis, String entryId, Offset planDelta) {
    // Both views share the vertical axis; they differ in what runs across.
    store.moveGear(
      plan.id,
      entryId,
      dx: axis == ViewAxis.front ? planDelta.dx : 0,
      dz: axis == ViewAxis.side ? planDelta.dx : 0,
      dy: planDelta.dy,
    );
  }

  Widget _view(ViewAxis axis) => ContainerView(
    plan: plan,
    axis: axis,
    issues: issues,
    selectedEntryId: selectedEntryId,
    onSelected: onSelected,
    onDragged: (entryId, delta) => _onDragged(axis, entryId, delta),
    onDragEnded: store.flush,
    onRotate: (entryId) => onRotate(axis, entryId),
  );

  @override
  Widget build(BuildContext context) {
    if (!plan.isThreeDimensional) return _view(ViewAxis.front);

    // The side view only needs to show depth, which is usually the smallest
    // dimension, so give the front view the bulk of the room.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 3, child: _view(ViewAxis.front)),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: _view(ViewAxis.side)),
      ],
    );
  }
}

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
