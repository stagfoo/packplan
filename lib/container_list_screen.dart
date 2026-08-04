import 'package:flutter/material.dart';

import 'container_detail_screen.dart';
import 'diagram.dart';
import 'edit_sheets.dart';
import 'models.dart';
import 'settings_screen.dart';
import 'store.dart';
import 'units.dart';

/// The plans tab: every container you have set up.
class ContainerListScreen extends StatelessWidget {
  const ContainerListScreen({super.key, required this.store});

  final GearStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Plans'),
            actions: [
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => SettingsScreen(store: store),
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _addContainer(context),
            icon: const Icon(Icons.add),
            label: const Text('New container'),
          ),
          body: !store.isLoaded
              ? const Center(child: CircularProgressIndicator())
              : store.containers.isEmpty
              ? const _EmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: store.containers.length,
                  itemBuilder: (context, index) {
                    final container = store.containers[index];
                    return _ContainerTile(
                      plan: store.planFor(container.id)!,
                      onOpen: () => _open(context, container.id),
                      onDuplicate: () => store.duplicateContainer(container.id),
                      onDelete: () => _confirmDelete(context, container),
                    );
                  },
                ),
        );
      },
    );
  }

  void _open(BuildContext context, String containerId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ContainerDetailScreen(
          store: store,
          containerId: containerId,
        ),
      ),
    );
  }

  Future<void> _addContainer(BuildContext context) async {
    final draft = await showContainerSheet(
      context,
      defaultTolerance: store.settings.defaultTolerance,
    );
    if (draft == null) return;

    final container = await store.addContainer(
      name: draft.name,
      width: draft.width,
      height: draft.height,
      depth: draft.depth,
      tolerance: draft.tolerance,
    );

    if (!context.mounted) return;
    _open(context, container.id);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    GearContainer container,
  ) async {
    final count = container.entries.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${container.name}?'),
        content: Text(
          count == 0
              ? 'This cannot be undone.'
              : 'The $count ${count == 1 ? 'piece' : 'pieces'} of gear in it '
                    'stay in your library. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) await store.deleteContainer(container.id);
  }
}

class _ContainerTile extends StatelessWidget {
  const _ContainerTile({
    required this.plan,
    required this.onOpen,
    required this.onDuplicate,
    required this.onDelete,
  });

  final Plan plan;
  final VoidCallback onOpen;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = UnitScope.of(context);
    final container = plan.container;
    final unpacked = plan.unpacked.length;

    final fill = plan.volumeUsed ?? plan.areaUsed;
    final count = plan.entries.length;

    final notes = <String>[
      formatDimensions(
        unit,
        width: container.width,
        height: container.height,
        depth: container.depth,
      ),
      '$count ${count == 1 ? 'item' : 'items'}',
      '${(fill * 100).round()}% full',
      if (container.tolerance > 0)
        '${unit.formatWithSymbol(container.tolerance)} tolerance',
      if (unpacked > 0) '$unpacked not packed',
    ];

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onOpen,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: container.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: container.color, width: 2),
          ),
          child: Icon(Icons.backpack_outlined, color: container.color),
        ),
        title: Text(container.name),
        subtitle: Text(
          notes.join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(
            color: unpacked > 0
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => switch (value) {
            'duplicate' => onDuplicate(),
            'delete' => onDelete(),
            _ => null,
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.backpack_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Nothing planned yet',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Add a pack, a dry bag or a pocket, then fill it with gear from '
              'your library to see what fits.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
