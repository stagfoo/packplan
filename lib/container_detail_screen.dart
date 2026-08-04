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
class ContainerDetailScreen extends StatefulWidget {
  const ContainerDetailScreen({
    super.key,
    required this.store,
    required this.containerId,
  });

  final GearStore store;
  final String containerId;

  @override
  State<ContainerDetailScreen> createState() => _ContainerDetailScreenState();
}

class _ContainerDetailScreenState extends State<ContainerDetailScreen> {
  String? _selectedEntryId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final plan = widget.store.planFor(widget.containerId);

        // The container can disappear if it was deleted from the list screen
        // while this route was still on the stack.
        if (plan == null) {
          return const Scaffold(
            body: Center(child: Text('This container was deleted.')),
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
            tooltip: 'Edit container',
            icon: const Icon(Icons.straighten),
            onPressed: () => _editContainer(plan),
          ),
          PopupMenuButton<String>(
            onSelected: (value) => switch (value) {
              'recipe' => _applyRecipe(plan),
              'save-recipe' => _saveAsRecipe(plan),
              _ => null,
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'recipe',
                child: Text('Add from recipe'),
              ),
              const PopupMenuItem(
                value: 'save-recipe',
                child: Text('Save as recipe'),
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
                        'The tolerance leaves no usable space in this '
                        'container. Lower it or make the container bigger.',
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

  Future<void> _autoPack(Plan plan) async {
    final result = await widget.store.autoPack(plan.id);
    _report(
      result.everythingFits
          ? 'Everything fits.'
          : "${result.unfitted.length} didn't fit: "
                '${result.unfitted.map((e) => e.item.name).join(', ')}',
    );
  }

  Future<void> _editContainer(Plan plan) async {
    final draft = await showContainerSheet(context, initial: plan.container);
    if (draft == null) return;

    await widget.store.updateContainer(
      plan.id,
      name: draft.name,
      width: draft.width,
      height: draft.height,
      depth: draft.depth,
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

  Future<void> _applyRecipe(Plan plan) async {
    final recipes = widget.store.recipes;
    if (recipes.isEmpty) {
      _report('No recipes yet. Make one from the Recipes tab.');
      return;
    }

    final recipeId = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final recipe in recipes)
              ListTile(
                title: Text(recipe.name),
                subtitle: Text(
                  '${recipe.itemIds.length} '
                  '${recipe.itemIds.length == 1 ? 'item' : 'items'}',
                ),
                onTap: () => Navigator.of(context).pop(recipe.id),
              ),
          ],
        ),
      ),
    );
    if (recipeId == null) return;

    final unfitted = await widget.store.applyRecipe(plan.id, recipeId);
    _report(
      unfitted.isEmpty
          ? 'Recipe added, everything fits.'
          : "Recipe added. No room for "
                "${unfitted.map((i) => i.name).join(', ')}.",
    );
  }

  Future<void> _saveAsRecipe(Plan plan) async {
    if (plan.entries.isEmpty) {
      _report('Nothing in this container to save.');
      return;
    }

    final name = await showNameDialog(
      context,
      title: 'Save as recipe',
      initial: plan.name,
      label: 'Recipe name',
    );
    if (name == null) return;

    await widget.store.saveContainerAsRecipe(plan.id, name: name);
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
    required this.store,
  });

  final Plan plan;
  final Map<String, Set<PlacementIssue>> issues;
  final String? selectedEntryId;
  final ValueChanged<String?> onSelected;
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
