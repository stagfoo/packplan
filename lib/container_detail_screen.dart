import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'diagram.dart';
import 'edit_sheets.dart';
import 'models.dart';
import 'packer.dart';
import 'store.dart';

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
  String? _selectedGoodId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final container = widget.store.containerById(widget.containerId);

        // The container can disappear if it was deleted from the list screen
        // while this route was still on the stack.
        if (container == null) {
          return const Scaffold(
            body: Center(child: Text('This container was deleted.')),
          );
        }

        return _build(context, container);
      },
    );
  }

  Widget _build(BuildContext context, GearContainer container) {
    final theme = Theme.of(context);
    final issues = findPlacementIssues(container);

    return Scaffold(
      appBar: AppBar(
        title: Text(container.name),
        actions: [
          IconButton(
            tooltip: 'Edit container',
            icon: const Icon(Icons.straighten),
            onPressed: () => _editContainer(container),
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
              container,
              constraints.maxWidth - horizontalPadding * 2,
            );
            final diagramHeight = wanted.clamp(
              constraints.maxHeight * 0.2,
              constraints.maxHeight * 0.55,
            );

            return Column(
              children: [
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
                      container: container,
                      issues: issues,
                      selectedGoodId: _selectedGoodId,
                      onSelected: (goodId) =>
                          setState(() => _selectedGoodId = goodId),
                      store: widget.store,
                    ),
                  ),
                ),
                if (container.placements.isNotEmpty)
                  Text(
                    container.isThreeDimensional
                        ? 'Drag gear in either view to adjust'
                        : 'Drag gear to adjust',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                _SummaryBar(container: container, issues: issues),
                const Divider(height: 1),
                Expanded(
                  child: _GoodsList(
                    container: container,
                    issues: issues,
                    selectedGoodId: _selectedGoodId,
                    onSelected: (goodId) => setState(
                      () => _selectedGoodId = _selectedGoodId == goodId
                          ? null
                          : goodId,
                    ),
                    onEdit: (good) => _editGood(container, good),
                    onDelete: (good) => _deleteGood(container, good),
                    onTogglePlaced: (good) => _togglePlaced(container, good),
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
                  onPressed: container.goods.isEmpty
                      ? null
                      : () => _autoPack(container),
                  icon: const Icon(Icons.auto_awesome_mosaic),
                  label: const Text('Auto-pack'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _addGood(container),
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
  static double _diagramHeightFor(
    GearContainer container,
    double availableWidth,
  ) {
    const labelHeight = 20.0;

    double heightFor(double width, double planWidth, double planHeight) {
      if (planWidth <= 0) return 0;
      return width * planHeight / planWidth;
    }

    if (!container.isThreeDimensional) {
      return heightFor(availableWidth, container.width, container.height) +
          labelHeight;
    }

    // Matches the 3:2 split the two views are laid out with.
    final usable = availableWidth - 12;
    final front = heightFor(
      usable * 3 / 5,
      container.width,
      container.height,
    );
    final side = heightFor(usable * 2 / 5, container.depth!, container.height);
    return math.max(front, side) + labelHeight;
  }

  Future<void> _autoPack(GearContainer container) async {
    final result = await widget.store.autoPack(container.id);
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.everythingFits
              ? 'Everything fits.'
              : "${result.unfitted.length} didn't fit: "
                    '${result.unfitted.map((g) => g.name).join(', ')}',
        ),
      ),
    );
  }

  Future<void> _editContainer(GearContainer container) async {
    final draft = await showGearEditSheet(
      context,
      title: 'Edit container',
      nameLabel: 'Container name',
      initial: draftFromContainer(container),
    );
    if (draft == null) return;

    await widget.store.updateContainer(
      container.id,
      name: draft.name,
      width: draft.width,
      height: draft.height,
      depth: draft.depth,
    );
  }

  Future<void> _addGood(GearContainer container) async {
    final draft = await showGearEditSheet(
      context,
      title: 'Add gear',
      nameLabel: 'Gear name',
      showRotatable: true,
    );
    if (draft == null) return;

    await widget.store.addGood(
      container.id,
      name: draft.name,
      width: draft.width,
      height: draft.height,
      depth: draft.depth,
      rotatable: draft.rotatable,
    );
  }

  Future<void> _editGood(GearContainer container, Good good) async {
    final draft = await showGearEditSheet(
      context,
      title: 'Edit gear',
      nameLabel: 'Gear name',
      initial: draftFromGood(good),
      showRotatable: true,
    );
    if (draft == null) return;

    await widget.store.updateGood(
      container.id,
      good.id,
      name: draft.name,
      width: draft.width,
      height: draft.height,
      depth: draft.depth,
      rotatable: draft.rotatable,
    );
  }

  Future<void> _deleteGood(GearContainer container, Good good) async {
    if (_selectedGoodId == good.id) setState(() => _selectedGoodId = null);
    await widget.store.deleteGood(container.id, good.id);
  }

  Future<void> _togglePlaced(GearContainer container, Good good) async {
    if (container.placements.containsKey(good.id)) {
      await widget.store.unplaceGood(container.id, good.id);
      return;
    }

    final placed = await widget.store.placeGood(container.id, good.id);
    if (placed || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No room left for ${good.name}. Try auto-pack.'),
      ),
    );
  }
}

/// The front view, plus a side view when the plan has depth.
class _Diagram extends StatelessWidget {
  const _Diagram({
    required this.container,
    required this.issues,
    required this.selectedGoodId,
    required this.onSelected,
    required this.store,
  });

  final GearContainer container;
  final Map<String, Set<PlacementIssue>> issues;
  final String? selectedGoodId;
  final ValueChanged<String?> onSelected;
  final GearStore store;

  void _onDragged(ViewAxis axis, String goodId, Offset planDelta) {
    // Both views share the vertical axis; they differ in what runs across.
    store.moveGood(
      container.id,
      goodId,
      dx: axis == ViewAxis.front ? planDelta.dx : 0,
      dz: axis == ViewAxis.side ? planDelta.dx : 0,
      dy: planDelta.dy,
    );
  }

  Widget _view(ViewAxis axis) => ContainerView(
    container: container,
    axis: axis,
    issues: issues,
    selectedGoodId: selectedGoodId,
    onSelected: onSelected,
    onDragged: (goodId, delta) => _onDragged(axis, goodId, delta),
    onDragEnded: store.flush,
  );

  @override
  Widget build(BuildContext context) {
    if (!container.isThreeDimensional) return _view(ViewAxis.front);

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
  const _SummaryBar({required this.container, required this.issues});

  final GearContainer container;
  final Map<String, Set<PlacementIssue>> issues;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unpacked = container.unpackedGoods.length;
    final overlapping = issues.values
        .where((set) => set.contains(PlacementIssue.overlapping))
        .length;

    final volumeUsed = container.volumeUsed;
    final fill = volumeUsed ?? container.areaUsed;
    final fillLabel = volumeUsed == null ? 'area' : 'volume';

    final warnings = <String>[
      if (unpacked > 0) '$unpacked not packed',
      if (overlapping > 0) '$overlapping overlapping',
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

class _GoodsList extends StatelessWidget {
  const _GoodsList({
    required this.container,
    required this.issues,
    required this.selectedGoodId,
    required this.onSelected,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePlaced,
  });

  final GearContainer container;
  final Map<String, Set<PlacementIssue>> issues;
  final String? selectedGoodId;
  final ValueChanged<String> onSelected;
  final ValueChanged<Good> onEdit;
  final ValueChanged<Good> onDelete;
  final ValueChanged<Good> onTogglePlaced;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (container.goods.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No gear yet. Add something to see how it fits.',
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
      itemCount: container.goods.length,
      itemBuilder: (context, index) {
        final good = container.goods[index];
        final placed = container.placements.containsKey(good.id);
        final goodIssues = issues[good.id] ?? const <PlacementIssue>{};

        final dimensions = [
          formatLength(good.width),
          formatLength(good.height),
          if (good.depth != null) formatLength(good.depth!),
        ].join(' × ');

        final notes = <String>[
          '$dimensions cm',
          if (!placed) 'not packed',
          if (goodIssues.contains(PlacementIssue.overlapping)) 'overlapping',
          if (goodIssues.contains(PlacementIssue.outOfBounds)) 'sticking out',
          if (!good.rotatable) 'fixed orientation',
        ];

        return ListTile(
          selected: good.id == selectedGoodId,
          onTap: () => onSelected(good.id),
          leading: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: good.color.withValues(alpha: placed ? 1 : 0.3),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: goodIssues.isNotEmpty
                    ? theme.colorScheme.error
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          title: Text(good.name),
          subtitle: Text(
            notes.join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: goodIssues.isNotEmpty || !placed
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (value) => switch (value) {
              'edit' => onEdit(good),
              'toggle' => onTogglePlaced(good),
              'delete' => onDelete(good),
              _ => null,
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                value: 'toggle',
                child: Text(placed ? 'Take out' : 'Put in'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        );
      },
    );
  }
}
